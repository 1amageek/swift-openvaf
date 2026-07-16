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

        let sandbox = try E2ETemporaryDirectory(name: "openvaf-e2e")
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
        let stagedSourceURL = try stagedSourceArtifact.locator.location.resolvedFileURL()
        let outputArtifact = try #require(artifact.outputArtifact)
        let outputURL = try outputArtifact.locator.location.resolvedFileURL()

        #expect(invocation.executable == executableURL.path)
        #expect(invocation.arguments.last == "wrapped-resistor.va")
        #expect(stagedSourceURL.lastPathComponent == "wrapped-resistor.va")
        #expect(outputURL.lastPathComponent == "wrapped-resistor.osdi")
        #expect(stagedSourceArtifact.digest.hexadecimalValue.count == 64)
        #expect(artifact.exitCode == 0)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))

        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = try #require(attributes[FileAttributeKey.size] as? NSNumber)
        #expect(fileSize.intValue > 0)
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

    init(name: String) throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenVAFSupportTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            Issue.record("Failed to remove temporary directory \(url.path): \(error)")
        }
    }
}
