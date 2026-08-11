import CircuiteFoundation
import Foundation
import Testing
@testable import OpenVAFSupport

#if OpenVAFCLI

@Suite("OpenVAF end-to-end", .timeLimit(.minutes(2)))
struct OpenVAFE2ETests {
    private static let environment = ProcessInfo.processInfo.environment
    private static let executableLocation = locateExecutable(environment: environment)
    private static let executableURL = executableLocation.url
    private static let isExplicitlyRequested = environment["OPENVAF_E2E"] == "1"
    private static let isEnabled = isExplicitlyRequested

    @Test(
        "Compiles a real Verilog-A fixture into OSDI",
        .enabled(if: OpenVAFE2ETests.isEnabled)
    )
    func compilesRealVerilogASourceIntoOSDI() async throws {
        let executableURL = try #require(
            Self.executableURL,
            "OPENVAF_E2E=1 requires OPENVAF_BIN or openvaf on PATH. \(Self.executableLocation.failureMessage)"
        )

        let sandbox = try E2ETemporaryDirectory(
            name: "openvaf-e2e-success",
            retainedRoot: Self.retainedEvidenceRoot
        )
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("resistor.va")
        try Data(Self.resistorModel.utf8).write(to: sourceURL)

        let compiler = CommandLineOpenVAFCompiler(configuration: OpenVAFConfiguration(
            executable: .path(executableURL.path),
            compileTimeout: .seconds(30),
            availabilityTimeout: .seconds(10),
            processEnvironment: Self.environment
        ))

        let availability = await compiler.availability()
        try #require(availability.isAvailable, "OpenVAF availability failed: \(availability)")

        let artifact = try await compiler.compile(OpenVAFCompilationRequest(
            sourceURL: sourceURL,
            outputDirectory: sandbox.url.appendingPathComponent("out"),
            outputFileName: "wrapped-resistor.osdi"
        ))

        let invocation = try #require(artifact.provenance.invocation)
        let stagedSourceArtifact = try #require(artifact.provenance.inputs.first)
        let stagedSourceBinding = try #require(artifact.artifactBindings.first {
            $0.reference == stagedSourceArtifact
        })
        let stagedSourceURL = try stagedSourceBinding.localFileURL()
        let outputBinding = try #require(artifact.outputBinding)
        let outputURL = try outputBinding.localFileURL()

        #expect(invocation.executable == executableURL.path)
        #expect(invocation.arguments.last == "wrapped-resistor.va")
        #expect(stagedSourceURL.lastPathComponent == "wrapped-resistor.va")
        #expect(outputURL.lastPathComponent == "wrapped-resistor.osdi")
        #expect(stagedSourceArtifact.digest.hexadecimalValue.count == 64)
        #expect(artifact.exitCode == 0)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        #expect(artifact.logArtifacts.count == 2)
        for binding in artifact.artifactBindings where binding.descriptor.kind == .log {
            let url = try binding.localFileURL()
            #expect(FileManager.default.fileExists(atPath: url.path))
            #expect(binding.digest.hexadecimalValue.count == 64)
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = try #require(attributes[FileAttributeKey.size] as? NSNumber)
        #expect(fileSize.intValue > 0)
        try Self.retain(artifact, named: "openvaf-success.json", in: sandbox.url)
    }

    @Test(
        "Retains real OpenVAF failure evidence",
        .enabled(if: OpenVAFE2ETests.isEnabled)
    )
    func retainsRealCompilationFailure() async throws {
        let executableURL = try #require(
            Self.executableURL,
            "OPENVAF_E2E=1 requires OPENVAF_BIN or openvaf on PATH. \(Self.executableLocation.failureMessage)"
        )
        let sandbox = try E2ETemporaryDirectory(
            name: "openvaf-e2e-failure",
            retainedRoot: Self.retainedEvidenceRoot
        )
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("invalid.va")
        try Data(Self.invalidModel.utf8).write(to: sourceURL)
        let compiler = CommandLineOpenVAFCompiler(configuration: OpenVAFConfiguration(
            executable: .path(executableURL.path),
            compileTimeout: .seconds(30),
            availabilityTimeout: .seconds(10),
            processEnvironment: Self.environment
        ))

        do {
            _ = try await compiler.compile(OpenVAFCompilationRequest(
                sourceURL: sourceURL,
                outputDirectory: sandbox.url.appendingPathComponent("out"),
                outputFileName: "invalid.osdi"
            ))
            Issue.record("Malformed Verilog-A must not produce a successful OSDI result.")
        } catch {
            guard case .compilationFailed(let failure) = error else {
                Issue.record("Expected a retained compilation failure, got \(error).")
                return
            }
            #expect(failure.exitCode != 0)
            #expect(failure.logArtifacts.count == 2)
            #expect(failure.diagnostics.contains {
                $0.code.rawValue == "openvaf.compilation.failed"
            })
            #expect(failure.provenance.invocation?.executable == executableURL.path)
            try Self.retain(failure, named: "openvaf-failure.json", in: sandbox.url)
        }
    }

    private static func locateExecutable(environment: [String: String]) -> ExecutableLocation {
        do {
            let url = try PATHOpenVAFExecutableResolver().resolve(
                .environment(variable: "OPENVAF_BIN", fallbackName: "openvaf"),
                environment: environment
            )
            return .resolved(url)
        } catch {
            return .failed(error)
        }
    }

    private static var retainedEvidenceRoot: URL? {
        guard let path = environment["OPENVAF_EVIDENCE_ROOT"], !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    private static func retain<Value: Encodable>(
        _ value: Value,
        named fileName: String,
        in directory: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(
            to: directory.appendingPathComponent(fileName),
            options: .atomic
        )
    }

    private static let resistorModel = """
`include "disciplines.vams"

module resistor(p, n);
    inout p, n;
    electrical p, n;

    parameter real resistance = 1.0;

    analog begin
        I(p, n) <+ V(p, n) / resistance;
    end
endmodule
"""

    private static let invalidModel = """
`include "disciplines.vams"

module invalid(p, n);
    inout p, n;
    electrical p, n;

    analog begin
        I(p, n) <+ ;
    end
endmodule
"""
}

private enum ExecutableLocation: Sendable {
    case resolved(URL)
    case failed(OpenVAFError)

    var url: URL? {
        switch self {
        case .resolved(let url):
            return url
        case .failed:
            return nil
        }
    }

    var failureMessage: String {
        switch self {
        case .resolved:
            return ""
        case .failed(let error):
            return error.localizedDescription
        }
    }
}

#endif

private struct E2ETemporaryDirectory {
    let url: URL
    let isRetained: Bool

    init(name: String, retainedRoot: URL?) throws {
        if let retainedRoot {
            url = retainedRoot.appendingPathComponent(name, isDirectory: true)
            isRetained = true
        } else {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("OpenVAFSupportTests-\(name)-\(UUID().uuidString)")
            isRetained = false
        }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        guard !isRetained else { return }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            Issue.record("Failed to remove temporary directory \(url.path): \(error)")
        }
    }
}
