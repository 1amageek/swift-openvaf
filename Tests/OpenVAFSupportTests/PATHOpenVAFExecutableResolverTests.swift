import Foundation
import Testing
@testable import OpenVAFSupport

@Suite("PATHOpenVAFExecutableResolver", .timeLimit(.minutes(1)))
struct PATHOpenVAFExecutableResolverTests {
    @Test("Environment variable takes precedence over PATH fallback")
    func environmentVariableTakesPrecedenceOverPATHFallback() throws {
        let sandbox = try TemporaryDirectory(name: "resolver-environment")
        defer { sandbox.remove() }

        let envDirectory = sandbox.url.appendingPathComponent("env")
        let pathDirectory = sandbox.url.appendingPathComponent("path")
        try FileManager.default.createDirectory(at: envDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pathDirectory, withIntermediateDirectories: true)

        let envExecutable = try createExecutable(at: envDirectory.appendingPathComponent("configured-openvaf"))
        _ = try createExecutable(at: pathDirectory.appendingPathComponent("openvaf"))

        let resolved = try PATHOpenVAFExecutableResolver().resolve(
            .environment(variable: "OPENVAF_BIN", fallbackName: "openvaf"),
            environment: [
                "OPENVAF_BIN": envExecutable.path,
                "PATH": pathDirectory.path,
            ]
        )

        #expect(resolved == envExecutable)
    }

    @Test("PATH lookup finds executable by name")
    func pathLookupFindsExecutableByName() throws {
        let sandbox = try TemporaryDirectory(name: "resolver-path")
        defer { sandbox.remove() }

        let executable = try createExecutable(at: sandbox.url.appendingPathComponent("openvaf"))

        let resolved = try PATHOpenVAFExecutableResolver().resolve(
            .name("openvaf"),
            environment: ["PATH": sandbox.url.path]
        )

        #expect(resolved == executable)
    }

    @Test("Path lookup rejects non-executable file")
    func pathLookupRejectsNonExecutableFile() throws {
        let sandbox = try TemporaryDirectory(name: "resolver-not-executable")
        defer { sandbox.remove() }

        let fileURL = sandbox.url.appendingPathComponent("openvaf")
        try Data("#!/bin/sh\n".utf8).write(to: fileURL)

        #expect(throws: OpenVAFError.notExecutable(path: fileURL.path)) {
            try PATHOpenVAFExecutableResolver().resolve(.path(fileURL.path), environment: [:])
        }
    }
}

@discardableResult
private func createExecutable(at url: URL) throws -> URL {
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: url.path
    )
    return url
}

private struct TemporaryDirectory {
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
