import Foundation
import Testing
@testable import OpenVAFSupport

@Suite("OpenVAF end-to-end", .timeLimit(.minutes(2)))
struct OpenVAFE2ETests {
    private static let environment = ProcessInfo.processInfo.environment
    private static let executableURL = locateExecutable(environment: environment)
    private static let isExplicitlyRequested = environment["OPENVAF_E2E"] == "1"
    private static let isEnabled = isExplicitlyRequested || executableURL != nil

    @Test(
        "Compiles a real Verilog-A fixture into OSDI",
        .enabled(if: OpenVAFE2ETests.isEnabled)
    )
    func compilesRealVerilogASourceIntoOSDI() async throws {
        let executableURL = try #require(
            Self.executableURL,
            "OPENVAF_E2E=1 requires OPENVAF_BIN or openvaf on PATH"
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
        #expect(availability.isAvailable)

        let artifact = try await compiler.compile(OpenVAFCompilationRequest(
            sourceURL: sourceURL,
            outputDirectory: sandbox.url.appendingPathComponent("out"),
            outputFileName: "wrapped-resistor.osdi"
        ))

        #expect(artifact.command.executableURL.path == executableURL.path)
        #expect(artifact.command.arguments.last == "wrapped-resistor.va")
        #expect(artifact.stagedSourceURL.lastPathComponent == "wrapped-resistor.va")
        #expect(artifact.outputURL.lastPathComponent == "wrapped-resistor.osdi")
        #expect(artifact.sourceSHA256.count == 64)
        #expect(artifact.exitCode == 0)
        #expect(FileManager.default.fileExists(atPath: artifact.outputURL.path))

        let attributes = try FileManager.default.attributesOfItem(atPath: artifact.outputURL.path)
        let fileSize = try #require(attributes[FileAttributeKey.size] as? NSNumber)
        #expect(fileSize.intValue > 0)
    }

    private static func locateExecutable(environment: [String: String]) -> URL? {
        do {
            return try PATHOpenVAFExecutableResolver().resolve(
                .environment(variable: "OPENVAF_BIN", fallbackName: "openvaf"),
                environment: environment
            )
        } catch {
            return nil
        }
    }

    private static let resistorModel = """
`include "disciplines.vams"

module resistor(p, n);
    inout p, n;
    electrical p, n;

    parameter real resistance = 1.0 from (0:inf);

    analog begin
        I(p, n) <+ V(p, n) / resistance;
    end
endmodule
"""
}

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
