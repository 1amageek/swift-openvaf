import Foundation
import Testing
@testable import OpenVAFSupport

@Suite("CommandLineOpenVAFCompiler", .timeLimit(.minutes(1)))
struct CommandLineOpenVAFCompilerTests {
    @Test("Availability reports resolved version")
    func availabilityReportsResolvedVersion() async throws {
        let executableURL = URL(fileURLWithPath: "/tmp/openvaf")
        let runner = RecordingProcessRunner { command in
            #expect(command.arguments == ["--version"])
            return OpenVAFProcessResult(
                exitCode: 0,
                standardOutput: "OpenVAF build 2026 version 1.2.3\n",
                standardError: "",
                startedAt: Date(timeIntervalSince1970: 1),
                finishedAt: Date(timeIntervalSince1970: 2)
            )
        }
        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": "/tmp"]),
            executableResolver: StaticExecutableResolver(url: executableURL),
            processRunner: runner
        )

        let availability = await compiler.availability()

        switch availability {
        case .available(let installation):
            #expect(installation.executableURL == executableURL)
            #expect(installation.version == "1.2.3")
            #expect(installation.rawVersionOutput == "OpenVAF build 2026 version 1.2.3\n")
        case .unavailable(let reason):
            Issue.record("Expected available OpenVAF, got \(reason)")
        }
    }

    @Test("Availability prefers OpenVAF version over date-like tokens")
    func availabilityPrefersOpenVAFVersionOverDateLikeTokens() async throws {
        let executableURL = URL(fileURLWithPath: "/tmp/openvaf")
        let runner = RecordingProcessRunner { _ in
            OpenVAFProcessResult(
                exitCode: 0,
                standardOutput: "Build date 2026.01.15\nOpenVAF version 1.2.3\n",
                standardError: "",
                startedAt: Date(),
                finishedAt: Date()
            )
        }
        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": "/tmp"]),
            executableResolver: StaticExecutableResolver(url: executableURL),
            processRunner: runner
        )

        let availability = await compiler.availability()

        switch availability {
        case .available(let installation):
            #expect(installation.version == "1.2.3")
        case .unavailable(let reason):
            Issue.record("Expected available OpenVAF, got \(reason)")
        }
    }

    @Test("Availability reports missing executable without launching")
    func availabilityReportsMissingExecutable() async throws {
        let runner = RecordingProcessRunner { _ in
            Issue.record("Runner should not be called when executable resolution fails")
            return OpenVAFProcessResult(
                exitCode: 0,
                standardOutput: "",
                standardError: "",
                startedAt: Date(),
                finishedAt: Date()
            )
        }
        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": "/missing"]),
            executableResolver: StaticExecutableResolver(error: .executableNotFound(
                name: "openvaf",
                searchedPaths: ["/missing"]
            )),
            processRunner: runner
        )

        let availability = await compiler.availability()

        #expect(availability == .unavailable(.executableNotFound(
            name: "openvaf",
            searchedPaths: ["/missing"]
        )))
    }

    @Test("Compile stages source and returns an artifact")
    func compileStagesSourceAndReturnsArtifact() async throws {
        let sandbox = try TemporaryDirectory(name: "compile-success")
        defer { sandbox.remove() }

        let sourceDirectory = sandbox.url.appendingPathComponent("src")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

        let sourceURL = sourceDirectory.appendingPathComponent("resistor.va")
        try "module resistor; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let executableURL = sandbox.url.appendingPathComponent("bin/openvaf")
        let runner = RecordingProcessRunner { command in
            if command.arguments == ["--version"] {
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "OpenVAF 1.2.3\n",
                    standardError: "",
                    startedAt: Date(timeIntervalSince1970: 8),
                    finishedAt: Date(timeIntervalSince1970: 9)
                )
            }

            #expect(command.executableURL == executableURL)
            #expect(command.arguments == ["--compact", "resistor.va"])
            #expect(command.workingDirectory.path.hasPrefix(outputDirectory.path))
            #expect(command.workingDirectory != outputDirectory)

            let outputURL = command.workingDirectory.appendingPathComponent("resistor.osdi")
            try Data("osdi".utf8).write(to: outputURL)

            return OpenVAFProcessResult(
                exitCode: 0,
                standardOutput: "compiled\n",
                standardError: "",
                startedAt: Date(timeIntervalSince1970: 10),
                finishedAt: Date(timeIntervalSince1970: 11)
            )
        }
        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(
                processEnvironment: ["PATH": sandbox.url.path],
                compilerArguments: ["--compact"]
            ),
            executableResolver: StaticExecutableResolver(url: executableURL),
            processRunner: runner
        )

        let artifact = try await compiler.compile(
            sourceAt: sourceURL,
            to: outputDirectory
        )

        #expect(artifact.sourceURL == sourceURL)
        #expect(artifact.sourceSHA256 == "7a3d26582b481c84f7300001cbf01b123be5c77da0da7bd1b690a406c5b11687")
        #expect(artifact.stagedSourceURL == artifact.command.workingDirectory.appendingPathComponent("resistor.va"))
        #expect(artifact.outputURL == artifact.command.workingDirectory.appendingPathComponent("resistor.osdi"))
        #expect(artifact.openVAFVersion == "1.2.3")
        #expect(artifact.exitCode == 0)
        #expect(artifact.standardOutput == "compiled\n")
        #expect(artifact.command.environmentKeys == ["PATH"])
        #expect(artifact.command.environment.source == .explicit)
        #expect(isSHA256Hex(artifact.command.environment.valueSHA256))
        #expect(FileManager.default.fileExists(atPath: artifact.stagedSourceURL.path))
        #expect(FileManager.default.fileExists(atPath: artifact.outputURL.path))
    }

    @Test("Compile honors custom OSDI output file name")
    func compileHonorsCustomOSDIOutputFileName() async throws {
        let sandbox = try TemporaryDirectory(name: "custom-output-file-name")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("original.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module original; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let runner = RecordingProcessRunner { command in
            if command.arguments == ["--version"] {
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "OpenVAF 1.2.3\n",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }

            #expect(command.arguments == ["custom.va"])
            let outputURL = command.workingDirectory.appendingPathComponent("custom.osdi")
            try Data("osdi".utf8).write(to: outputURL)

            return OpenVAFProcessResult(
                exitCode: 0,
                standardOutput: "",
                standardError: "",
                startedAt: Date(),
                finishedAt: Date()
            )
        }
        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: runner
        )

        let artifact = try await compiler.compile(OpenVAFCompilationRequest(
            sourceURL: sourceURL,
            outputDirectory: outputDirectory,
            outputFileName: "custom.osdi"
        ))

        #expect(artifact.stagedSourceURL.lastPathComponent == "custom.va")
        #expect(artifact.outputURL.lastPathComponent == "custom.osdi")
        #expect(FileManager.default.fileExists(atPath: artifact.outputURL.path))
    }

    @Test("Compile maps non-zero OpenVAF exit")
    func compileMapsNonZeroOpenVAFExit() async throws {
        let sandbox = try TemporaryDirectory(name: "compile-failed")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("bad.va")
        try "module bad; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let runner = RecordingProcessRunner { _ in
            OpenVAFProcessResult(
                exitCode: 2,
                standardOutput: "",
                standardError: "syntax error",
                startedAt: Date(),
                finishedAt: Date()
            )
        }
        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: runner
        )

        do {
            _ = try await compiler.compile(
                sourceAt: sourceURL,
                to: sandbox.url.appendingPathComponent("out")
            )
            Issue.record("Expected compile failure")
        } catch let error {
            switch error {
            case .compilationFailed(let failure):
                #expect(failure.exitCode == 2)
                #expect(failure.standardOutput == "")
                #expect(failure.standardError == "syntax error")
                #expect(failure.sourceURL == sourceURL)
                #expect(failure.stagedSourceURL.lastPathComponent == "bad.va")
                #expect(failure.outputURL.lastPathComponent == "bad.osdi")
                #expect(failure.command.arguments == ["bad.va"])
            default:
                Issue.record("Expected compile failure, got \(error)")
            }
        }
        #expect(openVAFWorkingDirectories(in: sandbox.url.appendingPathComponent("out")).isEmpty)
    }

    @Test("Compile keeps failed working directory when configured")
    func compileKeepsFailedWorkingDirectoryWhenConfigured() async throws {
        let sandbox = try TemporaryDirectory(name: "kept-failed-working-directory")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("kept.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module kept; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let runner = RecordingProcessRunner { _ in
            OpenVAFProcessResult(
                exitCode: 2,
                standardOutput: "",
                standardError: "syntax error",
                startedAt: Date(),
                finishedAt: Date()
            )
        }
        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(
                processEnvironment: ["PATH": sandbox.url.path],
                keepsFailedWorkingDirectories: true
            ),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: runner
        )

        do {
            _ = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
            Issue.record("Expected compilation failure")
        } catch let error {
            switch error {
            case .compilationFailed(let failure):
                #expect(FileManager.default.fileExists(atPath: failure.command.workingDirectory.path))
                #expect(FileManager.default.fileExists(atPath: failure.stagedSourceURL.path))
            default:
                Issue.record("Expected compilation failure, got \(error)")
            }
        }
        #expect(openVAFWorkingDirectories(in: outputDirectory).count == 1)
    }

    @Test("Compile maps process timeout to failure artifact")
    func compileMapsProcessTimeoutToFailureArtifact() async throws {
        let sandbox = try TemporaryDirectory(name: "process-timeout")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("timeout.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module timeout; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let startedAt = Date(timeIntervalSince1970: 10)
        let finishedAt = Date(timeIntervalSince1970: 11)
        let runner = RecordingProcessRunner { command in
            if command.arguments == ["--version"] {
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "OpenVAF 1.2.3\n",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }

            throw OpenVAFProcessError.timedOut(
                executablePath: command.executableURL.path,
                timeout: .milliseconds(50),
                standardOutput: "partial",
                standardError: "still running",
                startedAt: startedAt,
                finishedAt: finishedAt
            )
        }
        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: runner
        )

        do {
            _ = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
            Issue.record("Expected process timeout")
        } catch let error {
            switch error {
            case .compilationTimedOut(let failure, let timeout):
                #expect(timeout == .milliseconds(50))
                #expect(failure.command.arguments == ["timeout.va"])
                #expect(failure.standardOutput == "partial")
                #expect(failure.standardError == "still running")
                #expect(failure.startedAt == startedAt)
                #expect(failure.finishedAt == finishedAt)
            default:
                Issue.record("Expected process timeout, got \(error)")
            }
        }
        #expect(openVAFWorkingDirectories(in: outputDirectory).isEmpty)
    }

    @Test("Compile maps process cancellation to failure artifact")
    func compileMapsProcessCancellationToFailureArtifact() async throws {
        let sandbox = try TemporaryDirectory(name: "process-cancellation")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("cancelled.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module cancelled; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let startedAt = Date(timeIntervalSince1970: 20)
        let finishedAt = Date(timeIntervalSince1970: 21)
        let runner = RecordingProcessRunner { command in
            if command.arguments == ["--version"] {
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "OpenVAF 1.2.3\n",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }

            throw OpenVAFProcessError.cancelled(
                executablePath: command.executableURL.path,
                standardOutput: "partial",
                standardError: "cancelled",
                startedAt: startedAt,
                finishedAt: finishedAt
            )
        }
        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: runner
        )

        do {
            _ = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
            Issue.record("Expected process cancellation")
        } catch let error {
            switch error {
            case .compilationCancelled(let failure):
                #expect(failure.command.arguments == ["cancelled.va"])
                #expect(failure.standardOutput == "partial")
                #expect(failure.standardError == "cancelled")
                #expect(failure.startedAt == startedAt)
                #expect(failure.finishedAt == finishedAt)
            default:
                Issue.record("Expected process cancellation, got \(error)")
            }
        }
        #expect(openVAFWorkingDirectories(in: outputDirectory).isEmpty)
    }

    @Test("Compile fails when OSDI output is missing")
    func compileFailsWhenOutputIsMissing() async throws {
        let sandbox = try TemporaryDirectory(name: "output-missing")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("missing.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module missing; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let runner = RecordingProcessRunner { _ in
            OpenVAFProcessResult(
                exitCode: 0,
                standardOutput: "ok",
                standardError: "",
                startedAt: Date(),
                finishedAt: Date()
            )
        }
        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: runner
        )

        do {
            _ = try await compiler.compile(
                sourceAt: sourceURL,
                to: outputDirectory
            )
            Issue.record("Expected missing output error")
        } catch let error {
            switch error {
            case .outputMissing(let failure):
                #expect(failure.outputURL.lastPathComponent == "missing.osdi")
                #expect(failure.outputURL.deletingLastPathComponent().path.hasPrefix(outputDirectory.path))
                #expect(failure.standardOutput == "ok")
                #expect(failure.standardError == "")
                #expect(failure.exitCode == 0)
            default:
                Issue.record("Expected missing output error, got \(error)")
            }
        }
        #expect(openVAFWorkingDirectories(in: outputDirectory).isEmpty)
    }

    @Test("Compile rejects output file names without OSDI extension")
    func compileRejectsOutputFileNamesWithoutOSDIExtension() async throws {
        let sandbox = try TemporaryDirectory(name: "invalid-output-extension")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("model.va")
        try "module model; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when output file name is invalid")
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        await #expect(throws: OpenVAFError.invalidOutputFileName(
            "model.so",
            message: "File name must use the .osdi extension"
        )) {
            try await compiler.compile(OpenVAFCompilationRequest(
                sourceURL: sourceURL,
                outputDirectory: sandbox.url.appendingPathComponent("out"),
                outputFileName: "model.so"
            ))
        }
    }

    @Test("Compile rejects output file names with path components")
    func compileRejectsOutputFileNamesWithPathComponents() async throws {
        let sandbox = try TemporaryDirectory(name: "invalid-output-file-name")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("model.va")
        try "module model; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let runner = RecordingProcessRunner { _ in
            Issue.record("Runner should not be called when output file name is invalid")
            return OpenVAFProcessResult(
                exitCode: 0,
                standardOutput: "",
                standardError: "",
                startedAt: Date(),
                finishedAt: Date()
            )
        }
        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: runner
        )

        await #expect(throws: OpenVAFError.invalidOutputFileName(
            "../escape.osdi",
            message: "File name must not contain path components"
        )) {
            try await compiler.compile(OpenVAFCompilationRequest(
                sourceURL: sourceURL,
                outputDirectory: sandbox.url.appendingPathComponent("out"),
                outputFileName: "../escape.osdi"
            ))
        }
    }

    @Test("Compile does not create working directory when executable is missing")
    func compileDoesNotCreateWorkingDirectoryWhenExecutableIsMissing() async throws {
        let sandbox = try TemporaryDirectory(name: "missing-executable")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("model.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module model; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": "/missing"]),
            executableResolver: StaticExecutableResolver(error: .executableNotFound(
                name: "openvaf",
                searchedPaths: ["/missing"]
            )),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when executable resolution fails")
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        await #expect(throws: OpenVAFError.executableNotFound(
            name: "openvaf",
            searchedPaths: ["/missing"]
        )) {
            try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    @Test("Compile cleans working directory when source disappears during staging")
    func compileCleansWorkingDirectoryWhenSourceDisappearsDuringStaging() async throws {
        let sandbox = try TemporaryDirectory(name: "stage-copy-failure")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("vanishing.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module vanishing; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let runner = RecordingProcessRunner { command in
            #expect(command.arguments == ["--version"])
            return OpenVAFProcessResult(
                exitCode: 0,
                standardOutput: "OpenVAF 1.2.3\n",
                standardError: "",
                startedAt: Date(),
                finishedAt: Date()
            )
        }
        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: DeletingExecutableResolver(
                url: sandbox.url.appendingPathComponent("openvaf"),
                fileToDelete: sourceURL
            ),
            processRunner: runner
        )

        do {
            _ = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
            Issue.record("Expected staging failure")
        } catch let error {
            switch error {
            case .fileSystemFailure(let operation, let path, _):
                #expect(operation == "stage source")
                #expect(path.hasSuffix("vanishing.va"))
            default:
                Issue.record("Expected staging failure, got \(error)")
            }
        }
        #expect(openVAFWorkingDirectories(in: outputDirectory).isEmpty)
    }

    @Test("Compile reuses cached OpenVAF version")
    func compileReusesCachedOpenVAFVersion() async throws {
        let sandbox = try TemporaryDirectory(name: "version-cache")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("cache.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module cache; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let executableURL = sandbox.url.appendingPathComponent("openvaf")
        let runner = RecordingProcessRunner { command in
            if command.arguments == ["--version"] {
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "OpenVAF 9.8.7\n",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }

            let outputURL = command.workingDirectory.appendingPathComponent("cache.osdi")
            try Data("osdi".utf8).write(to: outputURL)
            return OpenVAFProcessResult(
                exitCode: 0,
                standardOutput: "",
                standardError: "",
                startedAt: Date(),
                finishedAt: Date()
            )
        }
        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: executableURL),
            processRunner: runner
        )

        let first = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        let second = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        let commands = await runner.recordedCommands()

        #expect(first.openVAFVersion == "9.8.7")
        #expect(second.openVAFVersion == "9.8.7")
        #expect(commands.filter { $0.arguments == ["--version"] }.count == 1)
    }
}

private struct StaticExecutableResolver: OpenVAFExecutableResolving {
    let url: URL?
    let error: OpenVAFError?

    init(url: URL) {
        self.url = url
        self.error = nil
    }

    init(error: OpenVAFError) {
        self.url = nil
        self.error = error
    }

    func resolve(
        _ executable: OpenVAFExecutable,
        environment: [String: String]
    ) throws(OpenVAFError) -> URL {
        if let error {
            throw error
        }
        guard let url else {
            throw .executableNotFound(name: "openvaf", searchedPaths: [])
        }
        return url
    }
}

private struct DeletingExecutableResolver: OpenVAFExecutableResolving {
    let url: URL
    let fileToDelete: URL

    func resolve(
        _ executable: OpenVAFExecutable,
        environment: [String: String]
    ) throws(OpenVAFError) -> URL {
        do {
            if FileManager.default.fileExists(atPath: fileToDelete.path) {
                try FileManager.default.removeItem(at: fileToDelete)
            }
        } catch {
            throw .fileSystemFailure(
                operation: "delete source",
                path: fileToDelete.path,
                message: error.localizedDescription
            )
        }
        return url
    }
}

private actor RecordingProcessRunner: OpenVAFProcessRunning {
    typealias Behavior = @Sendable (OpenVAFProcessCommand) async throws -> OpenVAFProcessResult

    private let behavior: Behavior
    private(set) var commands: [OpenVAFProcessCommand] = []

    init(behavior: @escaping Behavior) {
        self.behavior = behavior
    }

    func run(_ command: OpenVAFProcessCommand) async throws -> OpenVAFProcessResult {
        commands.append(command)
        return try await behavior(command)
    }

    func recordedCommands() -> [OpenVAFProcessCommand] {
        commands
    }
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

private func openVAFWorkingDirectories(in outputDirectory: URL) -> [URL] {
    do {
        guard FileManager.default.fileExists(atPath: outputDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("openvaf-") }
    } catch {
        Issue.record("Failed to list output directory \(outputDirectory.path): \(error)")
        return []
    }
}

private func isSHA256Hex(_ value: String) -> Bool {
    guard value.count == 64 else { return false }
    return value.allSatisfy { character in
        character.isNumber || ("a"..."f").contains(character)
    }
}
