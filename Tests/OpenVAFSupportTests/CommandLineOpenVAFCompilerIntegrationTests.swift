import Foundation
import Testing
@testable import OpenVAFSupport

@Suite("CommandLineOpenVAFCompiler integration", .timeLimit(.minutes(1)))
struct CommandLineOpenVAFCompilerIntegrationTests {
    @Test("Compiler resolves and runs fake OpenVAF through Foundation process runner")
    func compilerResolvesAndRunsFakeOpenVAFThroughFoundationProcessRunner() async throws {
        let sandbox = try IntegrationTemporaryDirectory(name: "fake-openvaf")
        defer { sandbox.remove() }

        let binDirectory = sandbox.url.appendingPathComponent("bin")
        let sourceDirectory = sandbox.url.appendingPathComponent("src")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

        let executableURL = binDirectory.appendingPathComponent("openvaf")
        try createFakeOpenVAFExecutable(at: executableURL)

        let sourceURL = sourceDirectory.appendingPathComponent("model.va")
        try "module model; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let compiler = CommandLineOpenVAFCompiler(configuration: OpenVAFConfiguration(
            executable: .name("openvaf"),
            compileTimeout: .seconds(5),
            availabilityTimeout: .seconds(5),
            processEnvironment: ["PATH": binDirectory.path]
        ))

        let availability = await compiler.availability()
        switch availability {
        case .available(let installation):
            #expect(installation.executableURL == executableURL)
            #expect(installation.version == "7.6.5")
        case .unavailable(let reason):
            Issue.record("Expected fake OpenVAF to be available, got \(reason)")
        }

        let artifact = try await compiler.compile(OpenVAFCompilationRequest(
            sourceURL: sourceURL,
            outputDirectory: outputDirectory,
            outputFileName: "renamed.osdi"
        ))

        #expect(artifact.command.executableURL == executableURL)
        #expect(artifact.command.arguments == ["renamed.va"])
        #expect(artifact.command.workingDirectory.path.hasPrefix(outputDirectory.path))
        #expect(artifact.stagedSourceURL.lastPathComponent == "renamed.va")
        #expect(artifact.outputURL.lastPathComponent == "renamed.osdi")
        #expect(artifact.openVAFVersion == "7.6.5")
        #expect(artifact.exitCode == 0)
        #expect(artifact.standardOutput == "compiled renamed.va\n")
        #expect(artifact.standardError == "")

        let output = try String(contentsOf: artifact.outputURL, encoding: .utf8)
        #expect(output == "fake-osdi:renamed.va\n")
    }
}

private func createFakeOpenVAFExecutable(at url: URL) throws {
    let script = """
#!/bin/sh
set -eu
if [ "${1:-}" = "--version" ]; then
    printf 'OpenVAF 7.6.5\\n'
    exit 0
fi
source_file="${1:?missing source}"
output_file="${source_file%.*}.osdi"
printf 'fake-osdi:%s\\n' "$source_file" > "$output_file"
printf 'compiled %s\\n' "$source_file"
"""
    try Data(script.utf8).write(to: url)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: url.path
    )
}

private struct IntegrationTemporaryDirectory {
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
