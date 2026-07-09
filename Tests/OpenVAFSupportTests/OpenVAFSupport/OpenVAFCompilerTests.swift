import Foundation
import Darwin
import Testing
@testable import OpenVAFSupport
@testable import VerilogACompiler

#if OpenVAFCLI

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

    @Test("Availability skips OpenVAF-prefixed date-like tokens")
    func availabilitySkipsOpenVAFPrefixedDateLikeTokens() async throws {
        let executableURL = URL(fileURLWithPath: "/tmp/openvaf")
        let runner = RecordingProcessRunner { _ in
            OpenVAFProcessResult(
                exitCode: 0,
                standardOutput: "OpenVAF build 2026.01.15 version 1.2.3\n",
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

    @Test("Availability refreshes version when executable changes during version check")
    func availabilityRefreshesVersionWhenExecutableChangesDuringVersionCheck() async throws {
        let sandbox = try TemporaryDirectory(name: "availability-version-replacement")
        defer { sandbox.remove() }

        let executableURL = sandbox.url.appendingPathComponent("openvaf")
        try writeExecutableMarker("first", to: executableURL)

        let runner = RecordingProcessRunner { command in
            let executableData = try Data(contentsOf: command.executableURL)
            let executableText = String(decoding: executableData, as: UTF8.self)
            if executableText.contains("first") {
                try writeExecutableMarker("second", to: command.executableURL)
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "OpenVAF 1.0.0\n",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }

            return OpenVAFProcessResult(
                exitCode: 0,
                standardOutput: "OpenVAF 2.0.0\n",
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

        let availability = await compiler.availability()
        let commands = await runner.recordedCommands()

        switch availability {
        case .available(let installation):
            #expect(installation.version == "2.0.0")
            #expect(installation.rawVersionOutput == "OpenVAF 2.0.0\n")
        case .unavailable(let reason):
            Issue.record("Expected refreshed OpenVAF availability, got \(reason)")
        }
        #expect(commands.filter { $0.arguments == ["--version"] }.count == 2)
    }

    @Test("Availability rejects executables that keep changing during version checks")
    func availabilityRejectsExecutablesThatKeepChangingDuringVersionChecks() async throws {
        let sandbox = try TemporaryDirectory(name: "availability-version-unstable")
        defer { sandbox.remove() }

        let executableURL = sandbox.url.appendingPathComponent("openvaf")
        try writeExecutableMarker("first", to: executableURL)

        let runner = RecordingProcessRunner { command in
            let executableData = try Data(contentsOf: command.executableURL)
            let executableText = String(decoding: executableData, as: UTF8.self)
            if executableText.contains("first") {
                try writeExecutableMarker("second", to: command.executableURL)
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "OpenVAF 1.0.0\n",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }

            try writeExecutableMarker("third", to: command.executableURL)
            return OpenVAFProcessResult(
                exitCode: 0,
                standardOutput: "OpenVAF 2.0.0\n",
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

        let availability = await compiler.availability()
        let commands = await runner.recordedCommands()

        switch availability {
        case .unavailable(.launchFailed(let executablePath, let message)):
            #expect(executablePath == executableURL.path)
            #expect(message == "Executable changed during version check")
        case .available, .unavailable:
            Issue.record("Expected unstable executable availability, got \(availability)")
        }
        #expect(commands.filter { $0.arguments == ["--version"] }.count == 2)
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

    @Test("Availability reports invalid executable names without launching")
    func availabilityReportsInvalidExecutableNamesWithoutLaunching() async throws {
        let compiler = CommandLineOpenVAFCompiler(configuration: OpenVAFConfiguration(
            executable: .name("../openvaf"),
            processEnvironment: ["PATH": "/missing"]
        ))

        let availability = await compiler.availability()

        #expect(availability == .unavailable(.invalidExecutableName(
            "../openvaf",
            message: "Name must not contain path components"
        )))
    }

    @Test("Availability reports invalid configuration without launching")
    func availabilityReportsInvalidConfigurationWithoutLaunching() async throws {
        let runner = RecordingProcessRunner { _ in
            Issue.record("Runner should not be called when configuration is invalid")
            return OpenVAFProcessResult(
                exitCode: 0,
                standardOutput: "",
                standardError: "",
                startedAt: Date(),
                finishedAt: Date()
            )
        }
        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(
                availabilityTimeout: .zero,
                processEnvironment: ["PATH": "/missing"]
            ),
            executableResolver: StaticExecutableResolver(url: URL(fileURLWithPath: "/tmp/openvaf")),
            processRunner: runner
        )

        let availability = await compiler.availability()

        #expect(availability == .unavailable(.invalidConfiguration(
            field: "availabilityTimeout",
            message: "Duration must be greater than zero"
        )))
    }

    @Test("Availability rejects negative termination grace")
    func availabilityRejectsNegativeTerminationGrace() async throws {
        let runner = RecordingProcessRunner { _ in
            Issue.record("Runner should not be called when termination grace is invalid")
            return OpenVAFProcessResult(
                exitCode: 0,
                standardOutput: "",
                standardError: "",
                startedAt: Date(),
                finishedAt: Date()
            )
        }
        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(
                terminationGrace: .seconds(-1),
                processEnvironment: ["PATH": "/missing"]
            ),
            executableResolver: StaticExecutableResolver(url: URL(fileURLWithPath: "/tmp/openvaf")),
            processRunner: runner
        )

        let availability = await compiler.availability()

        #expect(availability == .unavailable(.invalidConfiguration(
            field: "terminationGrace",
            message: "Duration must not be negative"
        )))
    }

    @Test("Availability rejects invalid explicit environment without launching")
    func availabilityRejectsInvalidExplicitEnvironmentWithoutLaunching() async throws {
        let runner = RecordingProcessRunner { _ in
            Issue.record("Runner should not be called when environment is invalid")
            return OpenVAFProcessResult(
                exitCode: 0,
                standardOutput: "",
                standardError: "",
                startedAt: Date(),
                finishedAt: Date()
            )
        }
        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["": "value"]),
            executableResolver: StaticExecutableResolver(url: URL(fileURLWithPath: "/tmp/openvaf")),
            processRunner: runner
        )

        let availability = await compiler.availability()

        #expect(availability == .unavailable(.invalidConfiguration(
            field: "processEnvironment",
            message: "Environment variable names must not be empty"
        )))
    }

    @Test("Availability rejects empty executable paths without launching")
    func availabilityRejectsEmptyExecutablePathsWithoutLaunching() async throws {
        let runner = RecordingProcessRunner { _ in
            Issue.record("Runner should not be called when executable path is invalid")
            return OpenVAFProcessResult(
                exitCode: 0,
                standardOutput: "",
                standardError: "",
                startedAt: Date(),
                finishedAt: Date()
            )
        }
        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(
                executable: .path(""),
                processEnvironment: ["PATH": "/missing"]
            ),
            executableResolver: StaticExecutableResolver(url: URL(fileURLWithPath: "/tmp/openvaf")),
            processRunner: runner
        )

        let availability = await compiler.availability()

        #expect(availability == .unavailable(.invalidConfiguration(
            field: "executable.path",
            message: "Executable path must not be empty"
        )))
    }

    @Test("Availability maps unexpected resolver errors without trapping")
    func availabilityMapsUnexpectedResolverErrorsWithoutTrapping() async throws {
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
            executableResolver: StaticExecutableResolver(error: .fileSystemFailure(
                operation: "resolve executable",
                path: "/missing/openvaf",
                message: "metadata unavailable"
            )),
            processRunner: runner
        )

        let availability = await compiler.availability()

        switch availability {
        case .unavailable(.launchFailed(let executablePath, let message)):
            #expect(executablePath == "<unknown>")
            #expect(message.contains("resolve executable"))
            #expect(message.contains("metadata unavailable"))
        case .available, .unavailable:
            Issue.record("Expected launch failed availability, got \(availability)")
        }
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
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try writeExecutableMarker("stable", to: executableURL)
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
        #expect(artifact.inputFiles.count == 1)
        if let inputFile = artifact.inputFiles.first {
            #expect(inputFile.role == .primarySource)
            #expect(inputFile.logicalPath == "resistor.va")
            #expect(inputFile.sourceURL == sourceURL)
            #expect(inputFile.stagedRelativePath == "resistor.va")
            #expect(inputFile.stagedURL == artifact.stagedSourceURL)
            #expect(inputFile.sha256 == artifact.sourceSHA256)
        }
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

    @Test("Compile runs through Verilog-A OSDI protocol")
    func compileRunsThroughVerilogAOSDIProtocol() async throws {
        let sandbox = try TemporaryDirectory(name: "compile-osdi-protocol")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("resistor.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module resistor; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

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

            let outputURL = command.workingDirectory.appendingPathComponent("resistor.osdi")
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

        let artifact = try await compileThroughOSDIProtocol(
            compiler,
            sourceURL: sourceURL,
            outputDirectory: outputDirectory
        )

        #expect(compiler.implementation == .openVAF)
        #expect(artifact.outputURL.lastPathComponent == "resistor.osdi")
        #expect(FileManager.default.fileExists(atPath: artifact.outputURL.path))
    }

    @Test("Compile rejects non-file source URLs before launching")
    func compileRejectsNonFileSourceURLsBeforeLaunching() async throws {
        let sandbox = try TemporaryDirectory(name: "non-file-source-url")
        defer { sandbox.remove() }

        let sourceURL = try #require(URL(string: "https://example.com/model.va"))
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when the source URL is not a file URL")
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        await #expect(throws: OpenVAFError.fileSystemFailure(
            operation: "validate source",
            path: sourceURL.absoluteString,
            message: "Source URL must be a file URL"
        )) {
            try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    @Test("Compile rejects non-file output directory URLs before launching")
    func compileRejectsNonFileOutputDirectoryURLsBeforeLaunching() async throws {
        let sandbox = try TemporaryDirectory(name: "non-file-output-directory-url")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("model.va")
        let outputDirectory = try #require(URL(string: "https://example.com/build/openvaf"))
        try "module model; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when the output directory URL is not a file URL")
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        await #expect(throws: OpenVAFError.fileSystemFailure(
            operation: "validate output directory",
            path: outputDirectory.absoluteString,
            message: "Output directory URL must be a file URL"
        )) {
            try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        }
    }

    @Test("Compile rejects existing output files before launching")
    func compileRejectsExistingOutputFilesBeforeLaunching() async throws {
        let sandbox = try TemporaryDirectory(name: "output-directory-file")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("model.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module model; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "not a directory\n".write(to: outputDirectory, atomically: true, encoding: .utf8)

        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when the output directory path is a file")
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        await #expect(throws: OpenVAFError.fileSystemFailure(
            operation: "validate output directory",
            path: outputDirectory.path,
            message: "Output directory must be a directory"
        )) {
            try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        }
        let output = try String(contentsOf: outputDirectory, encoding: .utf8)
        #expect(output == "not a directory\n")
    }

    @Test("Compile rejects existing output files before reading source")
    func compileRejectsExistingOutputFilesBeforeReadingSource() async throws {
        let sandbox = try TemporaryDirectory(name: "output-directory-file-before-source")
        defer { sandbox.remove() }

        let missingSourceURL = sandbox.url.appendingPathComponent("missing.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "not a directory\n".write(to: outputDirectory, atomically: true, encoding: .utf8)
        let compiler = CommandLineOpenVAFCompiler(configuration: OpenVAFConfiguration(
            processEnvironment: ["PATH": sandbox.url.path]
        ))

        await #expect(throws: OpenVAFError.fileSystemFailure(
            operation: "validate output directory",
            path: outputDirectory.path,
            message: "Output directory must be a directory"
        )) {
            try await compiler.compile(sourceAt: missingSourceURL, to: outputDirectory)
        }
        let output = try String(contentsOf: outputDirectory, encoding: .utf8)
        #expect(output == "not a directory\n")
    }

    @Test("Compile rejects non-file include root URLs before launching")
    func compileRejectsNonFileIncludeRootURLsBeforeLaunching() async throws {
        let sandbox = try TemporaryDirectory(name: "non-file-include-root-url")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("model.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        let includeRootDirectory = try #require(URL(string: "https://example.com/project"))
        try "module model; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when the include root URL is not a file URL")
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        await #expect(throws: OpenVAFError.fileSystemFailure(
            operation: "validate include root",
            path: includeRootDirectory.absoluteString,
            message: "Include root URL must be a file URL"
        )) {
            try await compiler.compile(OpenVAFCompilationRequest(
                sourceURL: sourceURL,
                outputDirectory: outputDirectory,
                includeRootDirectory: includeRootDirectory
            ))
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    @Test("Compile rejects non-local file source URL hosts before reading source")
    func compileRejectsNonLocalFileSourceURLHostsBeforeReadingSource() async throws {
        let sandbox = try TemporaryDirectory(name: "file-source-url-host")
        defer { sandbox.remove() }

        let sourceURL = try #require(URL(string: "file://example.com\(sandbox.url.path)/model.va"))
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when the source file URL host is not local")
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        await #expect(throws: OpenVAFError.fileSystemFailure(
            operation: "validate source",
            path: sourceURL.absoluteString,
            message: "File URL host must be empty or localhost"
        )) {
            try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    @Test("Compile rejects non-local file output directory URL hosts before staging")
    func compileRejectsNonLocalFileOutputDirectoryURLHostsBeforeStaging() async throws {
        let sandbox = try TemporaryDirectory(name: "file-output-url-host")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("model.va")
        let outputDirectory = try #require(URL(string: "file://example.com\(sandbox.url.path)/out"))
        try "module model; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when the output directory file URL host is not local")
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        await #expect(throws: OpenVAFError.fileSystemFailure(
            operation: "validate output directory",
            path: outputDirectory.absoluteString,
            message: "File URL host must be empty or localhost"
        )) {
            try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        }
        #expect(!FileManager.default.fileExists(atPath: sandbox.url.appendingPathComponent("out").path))
    }

    @Test("Compile rejects non-local file include root URL hosts before reading source")
    func compileRejectsNonLocalFileIncludeRootURLHostsBeforeReadingSource() async throws {
        let sandbox = try TemporaryDirectory(name: "file-include-root-url-host")
        defer { sandbox.remove() }

        let missingSourceURL = sandbox.url.appendingPathComponent("missing.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        let includeRootDirectory = try #require(URL(string: "file://example.com\(sandbox.url.path)/project"))
        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when the include root file URL host is not local")
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        await #expect(throws: OpenVAFError.fileSystemFailure(
            operation: "validate include root",
            path: includeRootDirectory.absoluteString,
            message: "File URL host must be empty or localhost"
        )) {
            try await compiler.compile(OpenVAFCompilationRequest(
                sourceURL: missingSourceURL,
                outputDirectory: outputDirectory,
                includeRootDirectory: includeRootDirectory
            ))
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    @Test("Compile rejects empty file source URL paths before reading source")
    func compileRejectsEmptyFileSourceURLPathsBeforeReadingSource() async throws {
        let sandbox = try TemporaryDirectory(name: "empty-file-source-url-path")
        defer { sandbox.remove() }

        let sourceURL = try #require(URL(string: "file://localhost"))
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when the source file URL path is empty")
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        await #expect(throws: OpenVAFError.fileSystemFailure(
            operation: "validate source",
            path: sourceURL.absoluteString,
            message: "File URL path must not be empty"
        )) {
            try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    @Test("Compile rejects empty file output directory URL paths before staging")
    func compileRejectsEmptyFileOutputDirectoryURLPathsBeforeStaging() async throws {
        let sandbox = try TemporaryDirectory(name: "empty-file-output-url-path")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("model.va")
        let outputDirectory = try #require(URL(string: "file://localhost"))
        try "module model; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when the output directory file URL path is empty")
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        await #expect(throws: OpenVAFError.fileSystemFailure(
            operation: "validate output directory",
            path: outputDirectory.absoluteString,
            message: "File URL path must not be empty"
        )) {
            try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        }
        #expect(!FileManager.default.fileExists(atPath: sandbox.url.appendingPathComponent("out").path))
    }

    @Test("Compile rejects empty file include root URL paths before reading source")
    func compileRejectsEmptyFileIncludeRootURLPathsBeforeReadingSource() async throws {
        let sandbox = try TemporaryDirectory(name: "empty-file-include-root-url-path")
        defer { sandbox.remove() }

        let missingSourceURL = sandbox.url.appendingPathComponent("missing.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        let includeRootDirectory = try #require(URL(string: "file://localhost"))
        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when the include root file URL path is empty")
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        await #expect(throws: OpenVAFError.fileSystemFailure(
            operation: "validate include root",
            path: includeRootDirectory.absoluteString,
            message: "File URL path must not be empty"
        )) {
            try await compiler.compile(OpenVAFCompilationRequest(
                sourceURL: missingSourceURL,
                outputDirectory: outputDirectory,
                includeRootDirectory: includeRootDirectory
            ))
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    @Test("Compile rejects source paths containing NUL before reading source")
    func compileRejectsSourcePathsContainingNULBeforeReadingSource() async throws {
        let sandbox = try TemporaryDirectory(name: "source-path-nul")
        defer { sandbox.remove() }

        let sourceURL = try #require(URL(string: sandbox.url
            .appendingPathComponent("model.va")
            .absoluteString
            .replacingOccurrences(of: "model.va", with: "model%00.va")))
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when the source path contains NUL")
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        await #expect(throws: OpenVAFError.fileSystemFailure(
            operation: "validate source",
            path: sourceURL.path(percentEncoded: true),
            message: "Source path must not contain NUL"
        )) {
            try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    @Test("Compile rejects output directory paths containing NUL before staging")
    func compileRejectsOutputDirectoryPathsContainingNULBeforeStaging() async throws {
        let sandbox = try TemporaryDirectory(name: "output-directory-path-nul")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("model.va")
        let outputDirectory = try #require(URL(string: sandbox.url
            .appendingPathComponent("out")
            .absoluteString + "%00"))
        try "module model; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when the output directory path contains NUL")
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        await #expect(throws: OpenVAFError.fileSystemFailure(
            operation: "validate output directory",
            path: outputDirectory.path(percentEncoded: true),
            message: "Output directory path must not contain NUL"
        )) {
            try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path(percentEncoded: true)))
    }

    @Test("Compile rejects include root paths containing NUL before reading source")
    func compileRejectsIncludeRootPathsContainingNULBeforeReadingSource() async throws {
        let sandbox = try TemporaryDirectory(name: "include-root-path-nul")
        defer { sandbox.remove() }

        let missingSourceURL = sandbox.url.appendingPathComponent("missing.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        let includeRootDirectory = try #require(URL(string: sandbox.url
            .appendingPathComponent("project")
            .absoluteString + "%00"))
        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when the include root path contains NUL")
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        await #expect(throws: OpenVAFError.fileSystemFailure(
            operation: "validate include root",
            path: includeRootDirectory.path(percentEncoded: true),
            message: "Include root path must not contain NUL"
        )) {
            try await compiler.compile(OpenVAFCompilationRequest(
                sourceURL: missingSourceURL,
                outputDirectory: outputDirectory,
                includeRootDirectory: includeRootDirectory
            ))
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    @Test("Compile fingerprints explicit environment without delimiter collisions")
    func compileFingerprintsExplicitEnvironmentWithoutDelimiterCollisions() async throws {
        let sandbox = try TemporaryDirectory(name: "environment-fingerprint")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("env.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module env; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let executableURL = sandbox.url.appendingPathComponent("openvaf")
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

            let outputURL = command.workingDirectory.appendingPathComponent("env.osdi")
            try Data("osdi".utf8).write(to: outputURL)
            return OpenVAFProcessResult(
                exitCode: 0,
                standardOutput: "",
                standardError: "",
                startedAt: Date(),
                finishedAt: Date()
            )
        }

        func compile(environment: [String: String]) async throws -> OpenVAFCompilationArtifact {
            let compiler = CommandLineOpenVAFCompiler(
                configuration: OpenVAFConfiguration(processEnvironment: environment),
                executableResolver: StaticExecutableResolver(url: executableURL),
                processRunner: runner
            )
            return try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        }

        let first = try await compile(environment: [
            "A": "B\nC=D",
            "PATH": sandbox.url.path,
        ])
        let second = try await compile(environment: [
            "A": "B",
            "C": "D",
            "PATH": sandbox.url.path,
        ])

        #expect(first.command.environment.keys == ["A", "PATH"])
        #expect(second.command.environment.keys == ["A", "C", "PATH"])
        #expect(first.command.environment.valueSHA256 != second.command.environment.valueSHA256)
    }

    @Test("Compile records only relevant inherited environment metadata")
    func compileRecordsOnlyRelevantInheritedEnvironmentMetadata() async throws {
        let sandbox = try TemporaryDirectory(name: "inherited-environment-record")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("env.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module env; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let executableURL = sandbox.url.appendingPathComponent("openvaf")
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

            let outputURL = command.workingDirectory.appendingPathComponent("env.osdi")
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
            configuration: OpenVAFConfiguration(),
            executableResolver: StaticExecutableResolver(url: executableURL),
            processRunner: runner
        )

        let artifact = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        let allowedKeys = Set(["OPENVAF_BIN", "PATH", "DYLD_LIBRARY_PATH", "LD_LIBRARY_PATH"])

        #expect(artifact.command.environment.source == .inherited)
        #expect(Set(artifact.command.environment.keys).isSubset(of: allowedKeys))
        #expect(artifact.command.environment.keys == artifact.command.environment.keys.sorted())
        #expect(!artifact.command.environment.keys.contains("HOME"))
        #expect(!artifact.command.environment.keys.contains("GITHUB_TOKEN"))
        #expect(isSHA256Hex(artifact.command.environment.valueSHA256))
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

    @Test("Compile stages symlink source contents")
    func compileStagesSymlinkSourceContents() async throws {
        let sandbox = try TemporaryDirectory(name: "symlink-source")
        defer { sandbox.remove() }

        let targetSourceURL = sandbox.url.appendingPathComponent("target.va")
        let sourceURL = sandbox.url.appendingPathComponent("linked.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module linked; endmodule\n".write(to: targetSourceURL, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: sourceURL, withDestinationURL: targetSourceURL)

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

            let stagedSourceURL = command.workingDirectory.appendingPathComponent("linked.va")
            let values = try stagedSourceURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            #expect(values.isRegularFile == true)
            #expect(values.isSymbolicLink != true)
            let stagedSource = try String(contentsOf: stagedSourceURL, encoding: .utf8)
            #expect(stagedSource == "module linked; endmodule\n")

            let outputURL = command.workingDirectory.appendingPathComponent("linked.osdi")
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

        let artifact = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)

        #expect(artifact.sourceURL == sourceURL)
        #expect(artifact.stagedSourceURL.lastPathComponent == "linked.va")
        #expect(artifact.outputURL.lastPathComponent == "linked.osdi")
    }

    @Test("Compile normalizes encoded parent markers without resolving symlink source names")
    func compileNormalizesEncodedParentMarkersWithoutResolvingSymlinkSourceNames() async throws {
        let sandbox = try TemporaryDirectory(name: "encoded-parent-symlink-source")
        defer { sandbox.remove() }

        let sourceDirectory = sandbox.url.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

        let targetSourceURL = sandbox.url.appendingPathComponent("target.va")
        let linkedSourceURL = sandbox.url.appendingPathComponent("linked.va")
        let sourceURL = try #require(URL(string: sourceDirectory
            .appendingPathComponent("placeholder")
            .absoluteString
            .replacingOccurrences(of: "placeholder", with: "%2e%2e/linked.va")))
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module linked; endmodule\n".write(to: targetSourceURL, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: linkedSourceURL, withDestinationURL: targetSourceURL)

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

            #expect(command.arguments == ["linked.va"])
            let stagedSourceURL = command.workingDirectory.appendingPathComponent("linked.va")
            let stagedSource = try String(contentsOf: stagedSourceURL, encoding: .utf8)
            #expect(stagedSource == "module linked; endmodule\n")

            let outputURL = command.workingDirectory.appendingPathComponent("linked.osdi")
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

        let artifact = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)

        #expect(artifact.sourceURL == sourceURL)
        #expect(artifact.stagedSourceURL.lastPathComponent == "linked.va")
        #expect(artifact.outputURL.lastPathComponent == "linked.osdi")
    }

    @Test("Compile stages local include files beside the source")
    func compileStagesLocalIncludeFilesBesideTheSource() async throws {
        let sandbox = try TemporaryDirectory(name: "local-include")
        defer { sandbox.remove() }

        let sourceDirectory = sandbox.url.appendingPathComponent("src")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

        let sourceURL = sourceDirectory.appendingPathComponent("model.va")
        let includeURL = sourceDirectory.appendingPathComponent("params.inc")
        try """
`include "params.inc"
module model; endmodule
""".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "`define MODEL_GAIN 1\n".write(to: includeURL, atomically: true, encoding: .utf8)

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

            #expect(command.arguments == ["model.va"])
            let stagedIncludeURL = command.workingDirectory.appendingPathComponent("params.inc")
            let stagedInclude = try String(contentsOf: stagedIncludeURL, encoding: .utf8)
            #expect(stagedInclude == "`define MODEL_GAIN 1\n")

            let outputURL = command.workingDirectory.appendingPathComponent("model.osdi")
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

        let artifact = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)

        #expect(artifact.stagedSourceURL == artifact.command.workingDirectory.appendingPathComponent("model.va"))
        #expect(artifact.outputURL == artifact.command.workingDirectory.appendingPathComponent("model.osdi"))
        #expect(artifact.inputFiles.map(\.role) == [.primarySource, .include])

        let primaryInput = try #require(artifact.inputFiles.first)
        #expect(primaryInput.logicalPath == "model.va")
        #expect(primaryInput.sourceURL == sourceURL)
        #expect(primaryInput.stagedRelativePath == "model.va")
        #expect(primaryInput.stagedURL == artifact.stagedSourceURL)
        #expect(primaryInput.sha256 == artifact.sourceSHA256)

        let includeInput = try #require(artifact.inputFiles.dropFirst().first)
        #expect(includeInput.logicalPath == "params.inc")
        #expect(includeInput.sourceURL == includeURL.standardized)
        #expect(includeInput.stagedRelativePath == "params.inc")
        #expect(includeInput.stagedURL == artifact.command.workingDirectory.appendingPathComponent("params.inc"))
        #expect(includeInput.sha256 == "c40920d60a3a1af7ffbcacc7ec5bd8e0ed36c987b7c51ca579869d2acad5d7aa")
    }

    @Test("Compile stages first include when source starts with UTF-8 byte order mark")
    func compileStagesFirstIncludeWhenSourceStartsWithUTF8ByteOrderMark() async throws {
        let sandbox = try TemporaryDirectory(name: "local-include-bom")
        defer { sandbox.remove() }

        let sourceDirectory = sandbox.url.appendingPathComponent("src")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

        let sourceURL = sourceDirectory.appendingPathComponent("model.va")
        let includeURL = sourceDirectory.appendingPathComponent("params.inc")
        var sourceData = Data([0xEF, 0xBB, 0xBF])
        sourceData.append(Data("`include \"params.inc\"\nmodule model; endmodule\n".utf8))
        try sourceData.write(to: sourceURL)
        try "`define MODEL_GAIN 1\n".write(to: includeURL, atomically: true, encoding: .utf8)

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

            let stagedIncludeURL = command.workingDirectory.appendingPathComponent("params.inc")
            let stagedInclude = try String(contentsOf: stagedIncludeURL, encoding: .utf8)
            #expect(stagedInclude == "`define MODEL_GAIN 1\n")

            let outputURL = command.workingDirectory.appendingPathComponent("model.osdi")
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

        let artifact = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)

        #expect(artifact.stagedSourceURL == artifact.command.workingDirectory.appendingPathComponent("model.va"))
        #expect(artifact.outputURL == artifact.command.workingDirectory.appendingPathComponent("model.osdi"))
    }

    @Test("Compile ignores inactive conditional includes while staging")
    func compileIgnoresInactiveConditionalIncludesWhileStaging() async throws {
        let sandbox = try TemporaryDirectory(name: "inactive-conditional-include")
        defer { sandbox.remove() }

        let sourceDirectory = sandbox.url.appendingPathComponent("src")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

        let sourceURL = sourceDirectory.appendingPathComponent("model.va")
        let includeURL = sourceDirectory.appendingPathComponent("active.inc")
        let inactiveIncludeURL = sandbox.url.appendingPathComponent("inactive.inc")
        try """
`ifdef DISABLED
`include "\(inactiveIncludeURL.path)"
`else
`include "active.inc"
`endif
module model; endmodule
""".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "`define MODEL_GAIN 1\n".write(to: includeURL, atomically: true, encoding: .utf8)

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

            let stagedActiveIncludeURL = command.workingDirectory.appendingPathComponent("active.inc")
            #expect(FileManager.default.fileExists(atPath: stagedActiveIncludeURL.path))

            let stagedInactiveIncludeURL = command.workingDirectory
                .appendingPathComponent(inactiveIncludeURL.lastPathComponent)
            #expect(!FileManager.default.fileExists(atPath: stagedInactiveIncludeURL.path))

            let outputURL = command.workingDirectory.appendingPathComponent("model.osdi")
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

        let artifact = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)

        #expect(artifact.outputURL == artifact.command.workingDirectory.appendingPathComponent("model.osdi"))
    }

    @Test("Compile stages includes discovered from the staged source snapshot")
    func compileStagesIncludesDiscoveredFromStagedSourceSnapshot() async throws {
        let sandbox = try TemporaryDirectory(name: "staged-source-include-snapshot")
        defer { sandbox.remove() }

        let sourceDirectory = sandbox.url.appendingPathComponent("src")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        let executableURL = sandbox.url.appendingPathComponent("openvaf")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try writeExecutableMarker("stable", to: executableURL)

        let sourceURL = sourceDirectory.appendingPathComponent("model.va")
        let includeURL = sourceDirectory.appendingPathComponent("params.inc")
        try "module model; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "`define MODEL_GAIN 1\n".write(to: includeURL, atomically: true, encoding: .utf8)

        let replacementSource = """
`include "params.inc"
module model; endmodule
"""
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

            let stagedSourceURL = command.workingDirectory.appendingPathComponent("model.va")
            let stagedSource = try String(contentsOf: stagedSourceURL, encoding: .utf8)
            #expect(stagedSource == replacementSource)

            let stagedIncludeURL = command.workingDirectory.appendingPathComponent("params.inc")
            let stagedInclude = try String(contentsOf: stagedIncludeURL, encoding: .utf8)
            #expect(stagedInclude == "`define MODEL_GAIN 1\n")

            let outputURL = command.workingDirectory.appendingPathComponent("model.osdi")
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
            executableResolver: OverwritingFileExecutableResolver(
                executableURL: executableURL,
                fileURL: sourceURL,
                contents: replacementSource
            ),
            processRunner: runner
        )

        let artifact = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)

        #expect(artifact.outputURL == artifact.command.workingDirectory.appendingPathComponent("model.osdi"))
    }

    @Test("Compile stages nested includes discovered from staged include snapshots")
    func compileStagesNestedIncludesDiscoveredFromStagedIncludeSnapshots() async throws {
        let sandbox = try TemporaryDirectory(name: "staged-nested-include-snapshot")
        defer { sandbox.remove() }

        let sourceDirectory = sandbox.url.appendingPathComponent("src")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        let executableURL = sandbox.url.appendingPathComponent("openvaf")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try writeExecutableMarker("stable", to: executableURL)

        let sourceURL = sourceDirectory.appendingPathComponent("model.va")
        let includeURL = sourceDirectory.appendingPathComponent("params.inc")
        let nestedIncludeURL = sourceDirectory.appendingPathComponent("nested.inc")
        try """
`include "params.inc"
module model; endmodule
""".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "`define MODEL_GAIN 1\n".write(to: includeURL, atomically: true, encoding: .utf8)
        try "`define MODEL_OFFSET 2\n".write(to: nestedIncludeURL, atomically: true, encoding: .utf8)

        let replacementInclude = """
`include "nested.inc"
`define MODEL_GAIN 1
"""
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

            let stagedIncludeURL = command.workingDirectory.appendingPathComponent("params.inc")
            let stagedInclude = try String(contentsOf: stagedIncludeURL, encoding: .utf8)
            #expect(stagedInclude == replacementInclude)

            let stagedNestedIncludeURL = command.workingDirectory.appendingPathComponent("nested.inc")
            let stagedNestedInclude = try String(contentsOf: stagedNestedIncludeURL, encoding: .utf8)
            #expect(stagedNestedInclude == "`define MODEL_OFFSET 2\n")

            let outputURL = command.workingDirectory.appendingPathComponent("model.osdi")
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
            executableResolver: OverwritingFileExecutableResolver(
                executableURL: executableURL,
                fileURL: includeURL,
                contents: replacementInclude
            ),
            processRunner: runner
        )

        let artifact = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)

        #expect(artifact.outputURL == artifact.command.workingDirectory.appendingPathComponent("model.osdi"))
    }

    @Test("Compile stages quoted includes that contain comment markers in the path")
    func compileStagesQuotedIncludesThatContainCommentMarkersInThePath() async throws {
        let sandbox = try TemporaryDirectory(name: "local-include-comment-marker")
        defer { sandbox.remove() }

        let sourceDirectory = sandbox.url.appendingPathComponent("src")
        let includeDirectory = sourceDirectory.appendingPathComponent("include")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: includeDirectory, withIntermediateDirectories: true)

        let sourceURL = sourceDirectory.appendingPathComponent("model.va")
        let includeURL = includeDirectory.appendingPathComponent("defs.inc")
        try """
`include "include//defs.inc"
module model; endmodule
""".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "`define MODEL_GAIN 1\n".write(to: includeURL, atomically: true, encoding: .utf8)

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

            let stagedIncludeURL = command.workingDirectory.appendingPathComponent("include/defs.inc")
            let stagedInclude = try String(contentsOf: stagedIncludeURL, encoding: .utf8)
            #expect(stagedInclude == "`define MODEL_GAIN 1\n")

            let outputURL = command.workingDirectory.appendingPathComponent("model.osdi")
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

        let artifact = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)

        #expect(artifact.outputURL == artifact.command.workingDirectory.appendingPathComponent("model.osdi"))
    }

    @Test("Compile preserves parent-relative include layout")
    func compilePreservesParentRelativeIncludeLayout() async throws {
        let sandbox = try TemporaryDirectory(name: "parent-relative-include")
        defer { sandbox.remove() }

        let projectDirectory = sandbox.url.appendingPathComponent("project")
        let sourceDirectory = projectDirectory.appendingPathComponent("models")
        let includeDirectory = projectDirectory.appendingPathComponent("include")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: includeDirectory, withIntermediateDirectories: true)

        let sourceURL = sourceDirectory.appendingPathComponent("model.va")
        let includeURL = includeDirectory.appendingPathComponent("defs.inc")
        try """
`include "../include/defs.inc"
module model; endmodule
""".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "`define MODEL_OFFSET 2\n".write(to: includeURL, atomically: true, encoding: .utf8)

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

            #expect(command.arguments == ["renamed.va"])
            #expect(command.workingDirectory.lastPathComponent == "models")
            let stagedProjectDirectory = command.workingDirectory.deletingLastPathComponent()
            let stagedIncludeURL = stagedProjectDirectory.appendingPathComponent("include/defs.inc")
            let stagedInclude = try String(contentsOf: stagedIncludeURL, encoding: .utf8)
            #expect(stagedInclude == "`define MODEL_OFFSET 2\n")

            let outputURL = command.workingDirectory.appendingPathComponent("renamed.osdi")
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
            outputFileName: "renamed.osdi",
            includeRootDirectory: projectDirectory
        ))

        #expect(artifact.stagedSourceURL.lastPathComponent == "renamed.va")
        #expect(artifact.stagedSourceURL.deletingLastPathComponent().lastPathComponent == "models")
        #expect(artifact.outputURL.lastPathComponent == "renamed.osdi")
    }

    @Test("Compile accepts a symlink include root when source uses the resolved project path")
    func compileAcceptsSymlinkIncludeRootWithResolvedSourcePath() async throws {
        let sandbox = try TemporaryDirectory(name: "symlink-include-root-resolved-source")
        defer { sandbox.remove() }

        let projectDirectory = sandbox.url.appendingPathComponent("project")
        let linkedProjectDirectory = sandbox.url.appendingPathComponent("linked-project")
        let sourceDirectory = projectDirectory.appendingPathComponent("models")
        let includeDirectory = projectDirectory.appendingPathComponent("include")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: includeDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: linkedProjectDirectory,
            withDestinationURL: projectDirectory
        )

        let sourceURL = sourceDirectory.appendingPathComponent("model.va")
        let includeURL = includeDirectory.appendingPathComponent("defs.inc")
        try """
`include "../include/defs.inc"
module model; endmodule
""".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "`define MODEL_OFFSET 2\n".write(to: includeURL, atomically: true, encoding: .utf8)

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

            #expect(command.arguments == ["model.va"])
            #expect(command.workingDirectory.lastPathComponent == "models")
            let stagedProjectDirectory = command.workingDirectory.deletingLastPathComponent()
            let stagedIncludeURL = stagedProjectDirectory.appendingPathComponent("include/defs.inc")
            let stagedInclude = try String(contentsOf: stagedIncludeURL, encoding: .utf8)
            #expect(stagedInclude == "`define MODEL_OFFSET 2\n")

            let outputURL = command.workingDirectory.appendingPathComponent("model.osdi")
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
            includeRootDirectory: linkedProjectDirectory
        ))

        #expect(artifact.stagedSourceURL.deletingLastPathComponent().lastPathComponent == "models")
        #expect(artifact.outputURL.lastPathComponent == "model.osdi")
    }

    @Test("Compile rejects local include files outside the include root")
    func compileRejectsLocalIncludeFilesOutsideTheIncludeRoot() async throws {
        let sandbox = try TemporaryDirectory(name: "outside-include-root")
        defer { sandbox.remove() }

        let projectDirectory = sandbox.url.appendingPathComponent("project")
        let sourceDirectory = projectDirectory.appendingPathComponent("models")
        let includeDirectory = projectDirectory.appendingPathComponent("include")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: includeDirectory, withIntermediateDirectories: true)

        let sourceURL = sourceDirectory.appendingPathComponent("model.va")
        let includeURL = includeDirectory.appendingPathComponent("defs.inc")
        try """
`include "../include/defs.inc"
module model; endmodule
""".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "`define MODEL_OFFSET 2\n".write(to: includeURL, atomically: true, encoding: .utf8)

        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when include is outside the include root")
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        await #expect(throws: OpenVAFError.fileSystemFailure(
            operation: "read include",
            path: includeURL.path,
            message: "Include is outside include root"
        )) {
            try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    @Test("Compile rejects absolute include paths before launching")
    func compileRejectsAbsoluteIncludePathsBeforeLaunching() async throws {
        let sandbox = try TemporaryDirectory(name: "absolute-include")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("model.va")
        let includeURL = sandbox.url.appendingPathComponent("defs.inc")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try """
`include "\(includeURL.path)"
module model; endmodule
""".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "`define MODEL_OFFSET 2\n".write(to: includeURL, atomically: true, encoding: .utf8)

        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when an absolute include path is present")
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        await #expect(throws: OpenVAFError.fileSystemFailure(
            operation: "read include",
            path: includeURL.path,
            message: "Absolute include paths are not supported"
        )) {
            try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    @Test("Compile stages local include symlink contents inside the include root")
    func compileStagesLocalIncludeSymlinkContentsInsideTheIncludeRoot() async throws {
        let sandbox = try TemporaryDirectory(name: "inside-include-root-symlink")
        defer { sandbox.remove() }

        let projectDirectory = sandbox.url.appendingPathComponent("project")
        let sourceDirectory = projectDirectory.appendingPathComponent("models")
        let includeDirectory = projectDirectory.appendingPathComponent("include")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: includeDirectory, withIntermediateDirectories: true)

        let sourceURL = sourceDirectory.appendingPathComponent("model.va")
        let realIncludeURL = includeDirectory.appendingPathComponent("real-defs.inc")
        let symlinkIncludeURL = includeDirectory.appendingPathComponent("defs.inc")
        try """
`include "../include/defs.inc"
module model; endmodule
""".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "`define MODEL_OFFSET 2\n".write(to: realIncludeURL, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: symlinkIncludeURL,
            withDestinationURL: realIncludeURL
        )

        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { command in
                if command.arguments == ["--version"] {
                    return OpenVAFProcessResult(
                        exitCode: 0,
                        standardOutput: "OpenVAF 1.2.3\n",
                        standardError: "",
                        startedAt: Date(),
                        finishedAt: Date()
                    )
                }

                let stagedProjectDirectory = command.workingDirectory.deletingLastPathComponent()
                let stagedIncludeURL = stagedProjectDirectory.appendingPathComponent("include/defs.inc")
                let values = try stagedIncludeURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                #expect(values.isRegularFile == true)
                #expect(values.isSymbolicLink != true)
                let stagedInclude = try String(contentsOf: stagedIncludeURL, encoding: .utf8)
                #expect(stagedInclude == "`define MODEL_OFFSET 2\n")

                let outputURL = command.workingDirectory.appendingPathComponent("model.osdi")
                try Data("osdi".utf8).write(to: outputURL)
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        let artifact = try await compiler.compile(OpenVAFCompilationRequest(
            sourceURL: sourceURL,
            outputDirectory: outputDirectory,
            includeRootDirectory: projectDirectory
        ))

        #expect(artifact.stagedSourceURL.deletingLastPathComponent().lastPathComponent == "models")
        #expect(artifact.outputURL.lastPathComponent == "model.osdi")
    }

    @Test("Compile scans resolved include files once through symlink cycles")
    func compileScansResolvedIncludeFilesOnceThroughSymlinkCycles() async throws {
        let sandbox = try TemporaryDirectory(name: "include-symlink-cycle")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("model.va")
        let loopURL = sandbox.url.appendingPathComponent("loop")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try """
`include "loop/model.va"
module model; endmodule
""".write(to: sourceURL, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: loopURL, withDestinationURL: sandbox.url)

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

            let stagedLoopSourceURL = command.workingDirectory.appendingPathComponent("loop/model.va")
            let values = try stagedLoopSourceURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            #expect(values.isRegularFile == true)
            #expect(values.isSymbolicLink != true)

            let outputURL = command.workingDirectory.appendingPathComponent("model.osdi")
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

        let artifact = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        let commands = await runner.recordedCommands()

        #expect(artifact.outputURL.lastPathComponent == "model.osdi")
        #expect(commands.filter { $0.arguments == ["model.va"] }.count == 1)
    }

    @Test("Compile scans same resolved include through distinct logical directories")
    func compileScansSameResolvedIncludeThroughDistinctLogicalDirectories() async throws {
        let sandbox = try TemporaryDirectory(name: "include-symlink-aliases")
        defer { sandbox.remove() }

        let sharedDirectory = sandbox.url.appendingPathComponent("shared")
        let aliasAURL = sandbox.url.appendingPathComponent("a")
        let aliasBURL = sandbox.url.appendingPathComponent("b")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: aliasAURL, withDestinationURL: sharedDirectory)
        try FileManager.default.createSymbolicLink(at: aliasBURL, withDestinationURL: sharedDirectory)

        let sourceURL = sandbox.url.appendingPathComponent("top.va")
        let sharedSourceURL = sharedDirectory.appendingPathComponent("model.va")
        let sharedDefsURL = sharedDirectory.appendingPathComponent("defs.inc")
        try """
`include "a/model.va"
`include "b/model.va"
module top; endmodule
""".write(to: sourceURL, atomically: true, encoding: .utf8)
        try """
`include "defs.inc"
module model; endmodule
""".write(to: sharedSourceURL, atomically: true, encoding: .utf8)
        try "`define MODEL_GAIN 1\n".write(to: sharedDefsURL, atomically: true, encoding: .utf8)

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

            let stagedAliasADefsURL = command.workingDirectory.appendingPathComponent("a/defs.inc")
            let stagedAliasBDefsURL = command.workingDirectory.appendingPathComponent("b/defs.inc")
            #expect(FileManager.default.fileExists(atPath: stagedAliasADefsURL.path))
            #expect(FileManager.default.fileExists(atPath: stagedAliasBDefsURL.path))

            let outputURL = command.workingDirectory.appendingPathComponent("top.osdi")
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

        let artifact = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)

        #expect(artifact.outputURL.lastPathComponent == "top.osdi")
    }

    @Test("Compile rejects local include symlinks that resolve outside the include root")
    func compileRejectsLocalIncludeSymlinksOutsideTheIncludeRoot() async throws {
        let sandbox = try TemporaryDirectory(name: "outside-include-root-symlink")
        defer { sandbox.remove() }

        let projectDirectory = sandbox.url.appendingPathComponent("project")
        let sourceDirectory = projectDirectory.appendingPathComponent("models")
        let includeDirectory = projectDirectory.appendingPathComponent("include")
        let outsideDirectory = sandbox.url.appendingPathComponent("outside")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: includeDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)

        let sourceURL = sourceDirectory.appendingPathComponent("model.va")
        let outsideIncludeURL = outsideDirectory.appendingPathComponent("defs.inc")
        let symlinkIncludeURL = includeDirectory.appendingPathComponent("defs.inc")
        try """
`include "../include/defs.inc"
module model; endmodule
""".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "`define MODEL_OFFSET 2\n".write(to: outsideIncludeURL, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: symlinkIncludeURL,
            withDestinationURL: outsideIncludeURL
        )

        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when include symlink escapes the include root")
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        await #expect(throws: OpenVAFError.fileSystemFailure(
            operation: "read include",
            path: symlinkIncludeURL.path,
            message: "Include is outside include root"
        )) {
            try await compiler.compile(OpenVAFCompilationRequest(
                sourceURL: sourceURL,
                outputDirectory: outputDirectory,
                includeRootDirectory: projectDirectory
            ))
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    @Test("Compile rejects include symlinks swapped outside the include root before staging")
    func compileRejectsIncludeSymlinksSwappedOutsideTheIncludeRootBeforeStaging() async throws {
        let sandbox = try TemporaryDirectory(name: "include-symlink-swap-before-stage")
        defer { sandbox.remove() }

        let projectDirectory = sandbox.url.appendingPathComponent("project")
        let sourceDirectory = projectDirectory.appendingPathComponent("models")
        let includeDirectory = projectDirectory.appendingPathComponent("include")
        let outsideDirectory = sandbox.url.appendingPathComponent("outside")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: includeDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)

        let sourceURL = sourceDirectory.appendingPathComponent("model.va")
        let validIncludeURL = includeDirectory.appendingPathComponent("valid-defs.inc")
        let outsideIncludeURL = outsideDirectory.appendingPathComponent("secret.inc")
        let symlinkIncludeURL = includeDirectory.appendingPathComponent("defs.inc")
        let executableURL = sandbox.url.appendingPathComponent("openvaf")
        try """
`include "../include/defs.inc"
module model; endmodule
""".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "`define MODEL_OFFSET 2\n".write(to: validIncludeURL, atomically: true, encoding: .utf8)
        try "`define SECRET 1\n".write(to: outsideIncludeURL, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: symlinkIncludeURL,
            withDestinationURL: validIncludeURL
        )
        try writeExecutableMarker("stable", to: executableURL)

        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: SwappingIncludeExecutableResolver(
                executableURL: executableURL,
                symlinkURL: symlinkIncludeURL,
                replacementTargetURL: outsideIncludeURL
            ),
            processRunner: RecordingProcessRunner { command in
                if command.arguments == ["--version"] {
                    return OpenVAFProcessResult(
                        exitCode: 0,
                        standardOutput: "OpenVAF 1.2.3\n",
                        standardError: "",
                        startedAt: Date(),
                        finishedAt: Date()
                    )
                }

                Issue.record("Runner should not be called when an include symlink escapes before staging")
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        await #expect(throws: OpenVAFError.fileSystemFailure(
            operation: "read include",
            path: symlinkIncludeURL.path,
            message: "Include is outside include root"
        )) {
            try await compiler.compile(OpenVAFCompilationRequest(
                sourceURL: sourceURL,
                outputDirectory: outputDirectory,
                includeRootDirectory: projectDirectory
            ))
        }
        #expect(openVAFWorkingDirectories(in: outputDirectory).isEmpty)
    }

    @Test("Compile rejects output file names that collide with staged includes")
    func compileRejectsOutputFileNamesThatCollideWithStagedIncludes() async throws {
        let sandbox = try TemporaryDirectory(name: "staged-source-include-collision")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("model.va")
        let includeURL = sandbox.url.appendingPathComponent("defs.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try """
`include "defs.va"
module model; endmodule
""".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "module defs; endmodule\n".write(to: includeURL, atomically: true, encoding: .utf8)

        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when output file name collides with a staged include")
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
            "defs.osdi",
            message: "Output file name would collide with a staged include"
        )) {
            try await compiler.compile(OpenVAFCompilationRequest(
                sourceURL: sourceURL,
                outputDirectory: outputDirectory,
                outputFileName: "defs.osdi"
            ))
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    @Test("Compile rejects output paths that collide with staged includes")
    func compileRejectsOutputPathsThatCollideWithStagedIncludes() async throws {
        let sandbox = try TemporaryDirectory(name: "staged-output-include-collision")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("model.va")
        let includeURL = sandbox.url.appendingPathComponent("model.osdi")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try """
`include "model.osdi"
module model; endmodule
""".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "not generated output\n".write(to: includeURL, atomically: true, encoding: .utf8)

        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when output file name collides with a staged include")
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
            "model.osdi",
            message: "Output file name would collide with a staged include"
        )) {
            try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    @Test("Compile hashes source larger than digest chunk")
    func compileHashesSourceLargerThanDigestChunk() async throws {
        let sandbox = try TemporaryDirectory(name: "large-source-hash")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("large.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try Data(repeating: 0x61, count: 131_072).write(to: sourceURL)

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

            let outputURL = command.workingDirectory.appendingPathComponent("large.osdi")
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

        let artifact = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)

        #expect(artifact.sourceSHA256 == "b44ffb72fcc259676bd80495fef1b44b808ca8f1ffe1b1706a4d7911b0e31f11")
        #expect(FileManager.default.fileExists(atPath: artifact.outputURL.path))
    }

    @Test("Compile rejects non-regular source files")
    func compileRejectsNonRegularSourceFiles() async throws {
        let sandbox = try TemporaryDirectory(name: "non-regular-source")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("pipe.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try createFIFO(at: sourceURL)

        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when source is not regular")
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        await #expect(throws: OpenVAFError.fileSystemFailure(
            operation: "read source",
            path: sourceURL.path,
            message: "Source must be a regular file"
        )) {
            try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
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
                #expect(failure.sourceSHA256 == "241514cca3430f01b8e7bcf403cb1b7c79675d0b59b6c01f694e544708d57607")
                #expect(failure.inputFiles.count == 1)
                if let inputFile = failure.inputFiles.first {
                    #expect(inputFile.role == .primarySource)
                    #expect(inputFile.logicalPath == "bad.va")
                    #expect(inputFile.sourceURL == sourceURL)
                    #expect(inputFile.stagedRelativePath == "bad.va")
                    #expect(inputFile.stagedURL == failure.stagedSourceURL)
                    #expect(inputFile.sha256 == failure.sourceSHA256)
                }
                #expect(failure.stagedSourceURL.lastPathComponent == "bad.va")
                #expect(failure.outputURL.lastPathComponent == "bad.osdi")
                #expect(failure.command.arguments == ["bad.va"])
            default:
                Issue.record("Expected compile failure, got \(error)")
            }
        }
        #expect(openVAFWorkingDirectories(in: sandbox.url.appendingPathComponent("out")).isEmpty)
    }

    @Test("Compile failures preserve requested source URL after normalization")
    func compileFailuresPreserveRequestedSourceURLAfterNormalization() async throws {
        let sandbox = try TemporaryDirectory(name: "failure-request-source-url")
        defer { sandbox.remove() }

        let sourceDirectory = sandbox.url.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

        let targetSourceURL = sandbox.url.appendingPathComponent("target.va")
        let linkedSourceURL = sandbox.url.appendingPathComponent("linked.va")
        let sourceURL = try #require(URL(string: sourceDirectory
            .appendingPathComponent("placeholder")
            .absoluteString
            .replacingOccurrences(of: "placeholder", with: "%2e%2e/linked.va")))
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module linked; endmodule\n".write(to: targetSourceURL, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: linkedSourceURL, withDestinationURL: targetSourceURL)

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
            _ = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
            Issue.record("Expected compile failure")
        } catch let error {
            switch error {
            case .compilationFailed(let failure):
                #expect(failure.sourceURL == sourceURL)
                #expect(failure.stagedSourceURL.lastPathComponent == "linked.va")
                #expect(failure.outputURL.lastPathComponent == "linked.osdi")
                #expect(failure.command.arguments == ["linked.va"])
            default:
                Issue.record("Expected compile failure, got \(error)")
            }
        }
        #expect(openVAFWorkingDirectories(in: outputDirectory).isEmpty)
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

    @Test("Compile preserves primary failure when cleanup cannot remove working directory")
    func compilePreservesPrimaryFailureWhenCleanupCannotRemoveWorkingDirectory() async throws {
        let sandbox = try TemporaryDirectory(name: "cleanup-failure-primary-error")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("cleanup.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module cleanup; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        defer { restoreWritablePermissions(at: outputDirectory) }

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

            try FileManager.default.setAttributes(
                [.posixPermissions: 0o555],
                ofItemAtPath: outputDirectory.path
            )
            return OpenVAFProcessResult(
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
            _ = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
            Issue.record("Expected compilation failure")
        } catch let error {
            switch error {
            case .compilationFailed(let failure):
                #expect(failure.standardError == "syntax error")
                #expect(failure.command.workingDirectory.path.hasPrefix(outputDirectory.path))
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

    @Test("Compile does not treat staged source as OSDI output")
    func compileDoesNotTreatStagedSourceAsOSDIOutput() async throws {
        let sandbox = try TemporaryDirectory(name: "source-output-collision")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("colliding.osdi")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module colliding; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

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

            return OpenVAFProcessResult(
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
            _ = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
            Issue.record("Expected missing output error")
        } catch let error {
            switch error {
            case .outputMissing(let failure):
                #expect(failure.stagedSourceURL.lastPathComponent == "colliding.va")
                #expect(failure.outputURL.lastPathComponent == "colliding.osdi")
                #expect(failure.stagedSourceURL != failure.outputURL)
                #expect(failure.exitCode == 0)
            default:
                Issue.record("Expected missing output error, got \(error)")
            }
        }
        #expect(openVAFWorkingDirectories(in: outputDirectory).isEmpty)
    }

    @Test("Compile fails when OSDI output is a directory")
    func compileFailsWhenOutputIsDirectory() async throws {
        let sandbox = try TemporaryDirectory(name: "output-directory")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("directory.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module directory; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

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

            let outputURL = command.workingDirectory.appendingPathComponent("directory.osdi")
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
            return OpenVAFProcessResult(
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
            _ = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
            Issue.record("Expected invalid output error")
        } catch let error {
            switch error {
            case .outputMissing(let failure):
                #expect(failure.outputURL.lastPathComponent == "directory.osdi")
                #expect(failure.exitCode == 0)
            default:
                Issue.record("Expected missing output error, got \(error)")
            }
        }
        #expect(openVAFWorkingDirectories(in: outputDirectory).isEmpty)
    }

    @Test("Compile fails when OSDI output is a symlink")
    func compileFailsWhenOutputIsSymlink() async throws {
        let sandbox = try TemporaryDirectory(name: "output-symlink")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("symlink.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        let externalOutputURL = sandbox.url.appendingPathComponent("external.osdi")
        try "module symlink; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        try Data("external-osdi".utf8).write(to: externalOutputURL)

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

            let outputURL = command.workingDirectory.appendingPathComponent("symlink.osdi")
            try FileManager.default.createSymbolicLink(
                at: outputURL,
                withDestinationURL: externalOutputURL
            )
            return OpenVAFProcessResult(
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
            _ = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
            Issue.record("Expected symlink output error")
        } catch let error {
            switch error {
            case .outputMissing(let failure):
                #expect(failure.outputURL.lastPathComponent == "symlink.osdi")
                #expect(failure.exitCode == 0)
            default:
                Issue.record("Expected missing output error, got \(error)")
            }
        }
        #expect(openVAFWorkingDirectories(in: outputDirectory).isEmpty)
        #expect(FileManager.default.fileExists(atPath: externalOutputURL.path))
    }

    @Test("Compile fails when OSDI output is a hard link")
    func compileFailsWhenOutputIsHardLink() async throws {
        let sandbox = try TemporaryDirectory(name: "output-hard-link")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("hard_link.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        let externalOutputURL = sandbox.url.appendingPathComponent("external.osdi")
        try "module hard_link; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        try Data("external-osdi".utf8).write(to: externalOutputURL)

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

            let outputURL = command.workingDirectory.appendingPathComponent("hard_link.osdi")
            try FileManager.default.linkItem(at: externalOutputURL, to: outputURL)
            return OpenVAFProcessResult(
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
            _ = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
            Issue.record("Expected hard-link output error")
        } catch let error {
            switch error {
            case .outputMissing(let failure):
                #expect(failure.outputURL.lastPathComponent == "hard_link.osdi")
                #expect(failure.exitCode == 0)
            default:
                Issue.record("Expected missing output error, got \(error)")
            }
        }
        #expect(openVAFWorkingDirectories(in: outputDirectory).isEmpty)
        #expect(FileManager.default.fileExists(atPath: externalOutputURL.path))
    }

    @Test("Compile fails when OSDI output is empty")
    func compileFailsWhenOutputIsEmpty() async throws {
        let sandbox = try TemporaryDirectory(name: "output-empty")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("empty.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module empty; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

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

            let outputURL = command.workingDirectory.appendingPathComponent("empty.osdi")
            try Data().write(to: outputURL)
            return OpenVAFProcessResult(
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
            _ = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
            Issue.record("Expected invalid output error")
        } catch let error {
            switch error {
            case .outputMissing(let failure):
                #expect(failure.outputURL.lastPathComponent == "empty.osdi")
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

    @Test("Compile rejects output file names containing NUL")
    func compileRejectsOutputFileNamesContainingNUL() async throws {
        let sandbox = try TemporaryDirectory(name: "invalid-output-nul")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("model.va")
        try "module model; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(processEnvironment: ["PATH": sandbox.url.path]),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when output file name contains NUL")
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
            "model\0.osdi",
            message: "File name must not contain NUL"
        )) {
            try await compiler.compile(OpenVAFCompilationRequest(
                sourceURL: sourceURL,
                outputDirectory: sandbox.url.appendingPathComponent("out"),
                outputFileName: "model\0.osdi"
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

    @Test("Compile does not create working directory when executable name is invalid")
    func compileDoesNotCreateWorkingDirectoryWhenExecutableNameIsInvalid() async throws {
        let sandbox = try TemporaryDirectory(name: "invalid-executable-name")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("model.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module model; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let compiler = CommandLineOpenVAFCompiler(configuration: OpenVAFConfiguration(
            executable: .name("../openvaf"),
            processEnvironment: ["PATH": sandbox.url.path]
        ))

        await #expect(throws: OpenVAFError.invalidExecutableName(
            "../openvaf",
            message: "Name must not contain path components"
        )) {
            try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    @Test("Compile rejects invalid executable name before reading source")
    func compileRejectsInvalidExecutableNameBeforeReadingSource() async throws {
        let sandbox = try TemporaryDirectory(name: "invalid-executable-name-before-source")
        defer { sandbox.remove() }

        let missingSourceURL = sandbox.url.appendingPathComponent("missing.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        let compiler = CommandLineOpenVAFCompiler(configuration: OpenVAFConfiguration(
            executable: .name("../openvaf"),
            processEnvironment: ["PATH": sandbox.url.path]
        ))

        await #expect(throws: OpenVAFError.invalidExecutableName(
            "../openvaf",
            message: "Name must not contain path components"
        )) {
            try await compiler.compile(sourceAt: missingSourceURL, to: outputDirectory)
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    @Test("Compile rejects invalid executable fallback name before reading source")
    func compileRejectsInvalidExecutableFallbackNameBeforeReadingSource() async throws {
        let sandbox = try TemporaryDirectory(name: "invalid-executable-fallback-before-source")
        defer { sandbox.remove() }

        let missingSourceURL = sandbox.url.appendingPathComponent("missing.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        let compiler = CommandLineOpenVAFCompiler(configuration: OpenVAFConfiguration(
            executable: .environment(variable: "OPENVAF_BIN", fallbackName: "sub/openvaf"),
            processEnvironment: ["PATH": sandbox.url.path]
        ))

        await #expect(throws: OpenVAFError.invalidExecutableName(
            "sub/openvaf",
            message: "Name must not contain path components"
        )) {
            try await compiler.compile(sourceAt: missingSourceURL, to: outputDirectory)
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    @Test("Compile rejects empty executable paths before reading source")
    func compileRejectsEmptyExecutablePathsBeforeReadingSource() async throws {
        let sandbox = try TemporaryDirectory(name: "empty-executable-path-before-source")
        defer { sandbox.remove() }

        let missingSourceURL = sandbox.url.appendingPathComponent("missing.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        let compiler = CommandLineOpenVAFCompiler(configuration: OpenVAFConfiguration(
            executable: .path(""),
            processEnvironment: ["PATH": sandbox.url.path]
        ))

        await #expect(throws: OpenVAFError.invalidConfiguration(
            field: "executable.path",
            message: "Executable path must not be empty"
        )) {
            try await compiler.compile(sourceAt: missingSourceURL, to: outputDirectory)
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    @Test("Compile rejects invalid configuration before staging")
    func compileRejectsInvalidConfigurationBeforeStaging() async throws {
        let sandbox = try TemporaryDirectory(name: "invalid-compile-configuration")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("model.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module model; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(
                compileTimeout: .zero,
                processEnvironment: ["PATH": sandbox.url.path]
            ),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when configuration is invalid")
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        await #expect(throws: OpenVAFError.invalidConfiguration(
            field: "compileTimeout",
            message: "Duration must be greater than zero"
        )) {
            try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    @Test("Compile rejects negative post-exit output drain grace before staging")
    func compileRejectsNegativePostExitOutputDrainGraceBeforeStaging() async throws {
        let sandbox = try TemporaryDirectory(name: "invalid-post-exit-output-drain-grace")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("model.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module model; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(
                terminationGrace: .milliseconds(10),
                postExitOutputDrainGrace: .seconds(-1),
                processEnvironment: ["PATH": sandbox.url.path]
            ),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when post-exit output drain grace is invalid")
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        await #expect(throws: OpenVAFError.invalidConfiguration(
            field: "postExitOutputDrainGrace",
            message: "Duration must not be negative"
        )) {
            try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    @Test("Compile rejects invalid environment variable configuration")
    func compileRejectsInvalidEnvironmentVariableConfiguration() async throws {
        let sandbox = try TemporaryDirectory(name: "invalid-environment-variable-configuration")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("model.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module model; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(
                executable: .environment(variable: "", fallbackName: "openvaf"),
                processEnvironment: ["PATH": sandbox.url.path]
            ),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when configuration is invalid")
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        await #expect(throws: OpenVAFError.invalidConfiguration(
            field: "executable.variable",
            message: "Environment variable name must not be empty"
        )) {
            try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    @Test("Compile rejects NUL in compiler arguments before staging")
    func compileRejectsNULInCompilerArgumentsBeforeStaging() async throws {
        let sandbox = try TemporaryDirectory(name: "invalid-compiler-argument")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("model.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module model; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(
                processEnvironment: ["PATH": sandbox.url.path],
                compilerArguments: ["--flag\0value"]
            ),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when compiler arguments are invalid")
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        await #expect(throws: OpenVAFError.invalidConfiguration(
            field: "compilerArguments[0]",
            message: "Argument must not contain NUL"
        )) {
            try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        }
        #expect(!FileManager.default.fileExists(atPath: outputDirectory.path))
    }

    @Test("Compile rejects compiler arguments that redirect OSDI output before staging")
    func compileRejectsOutputRedirectingCompilerArgumentsBeforeStaging() async throws {
        let sandbox = try TemporaryDirectory(name: "output-redirect-compiler-argument")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("model.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module model; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let compiler = CommandLineOpenVAFCompiler(
            configuration: OpenVAFConfiguration(
                processEnvironment: ["PATH": sandbox.url.path],
                compilerArguments: ["--output=../escaped.osdi"]
            ),
            executableResolver: StaticExecutableResolver(url: sandbox.url.appendingPathComponent("openvaf")),
            processRunner: RecordingProcessRunner { _ in
                Issue.record("Runner should not be called when compiler arguments redirect output")
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )

        await #expect(throws: OpenVAFError.invalidConfiguration(
            field: "compilerArguments[0]",
            message: "Output path arguments must be supplied through OpenVAFCompilationRequest.outputFileName"
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
        try writeExecutableMarker("stable", to: executableURL)
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

    @Test("Compile refreshes cached OpenVAF version after executable changes")
    func compileRefreshesCachedOpenVAFVersionAfterExecutableChanges() async throws {
        let sandbox = try TemporaryDirectory(name: "version-cache-refresh")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("refresh.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module refresh; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let executableURL = sandbox.url.appendingPathComponent("openvaf")
        try writeExecutableMarker("first", to: executableURL)

        let runner = RecordingProcessRunner { command in
            if command.arguments == ["--version"] {
                let executableData = try Data(contentsOf: command.executableURL)
                let executableText = String(decoding: executableData, as: UTF8.self)
                let version = executableText.contains("second") ? "2.0.0" : "1.0.0"
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "OpenVAF \(version)\n",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }

            let outputURL = command.workingDirectory.appendingPathComponent("refresh.osdi")
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
        try writeExecutableMarker("second", to: executableURL)
        let second = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        let commands = await runner.recordedCommands()

        #expect(first.openVAFVersion == "1.0.0")
        #expect(second.openVAFVersion == "2.0.0")
        #expect(commands.filter { $0.arguments == ["--version"] }.count == 2)
    }

    @Test("Compile refreshes OpenVAF version observed during executable replacement")
    func compileRefreshesOpenVAFVersionObservedDuringExecutableReplacement() async throws {
        let sandbox = try TemporaryDirectory(name: "version-cache-replacement-race")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("race.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module race; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let executableURL = sandbox.url.appendingPathComponent("openvaf")
        try writeExecutableMarker("first", to: executableURL)

        let runner = RecordingProcessRunner { command in
            if command.arguments == ["--version"] {
                let executableData = try Data(contentsOf: command.executableURL)
                let executableText = String(decoding: executableData, as: UTF8.self)
                if executableText.contains("first") {
                    try writeExecutableMarker("second", to: command.executableURL)
                    return OpenVAFProcessResult(
                        exitCode: 0,
                        standardOutput: "OpenVAF 1.0.0\n",
                        standardError: "",
                        startedAt: Date(),
                        finishedAt: Date()
                    )
                }

                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "OpenVAF 2.0.0\n",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }

            let outputURL = command.workingDirectory.appendingPathComponent("race.osdi")
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

        #expect(first.openVAFVersion == "2.0.0")
        #expect(second.openVAFVersion == "2.0.0")
        #expect(commands.filter { $0.arguments == ["--version"] }.count == 2)
    }

    @Test("Compile omits OpenVAF version when executable keeps changing during version checks")
    func compileOmitsOpenVAFVersionWhenExecutableKeepsChangingDuringVersionChecks() async throws {
        let sandbox = try TemporaryDirectory(name: "version-cache-unstable")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("unstable.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module unstable; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let executableURL = sandbox.url.appendingPathComponent("openvaf")
        try writeExecutableMarker("first", to: executableURL)

        let runner = RecordingProcessRunner { command in
            if command.arguments == ["--version"] {
                let executableData = try Data(contentsOf: command.executableURL)
                let executableText = String(decoding: executableData, as: UTF8.self)
                if executableText.contains("first") {
                    try writeExecutableMarker("second", to: command.executableURL)
                    return OpenVAFProcessResult(
                        exitCode: 0,
                        standardOutput: "OpenVAF 1.0.0\n",
                        standardError: "",
                        startedAt: Date(),
                        finishedAt: Date()
                    )
                }

                try writeExecutableMarker("third", to: command.executableURL)
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "OpenVAF 2.0.0\n",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }

            let outputURL = command.workingDirectory.appendingPathComponent("unstable.osdi")
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

        let artifact = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        let commands = await runner.recordedCommands()

        #expect(artifact.openVAFVersion == nil)
        #expect(artifact.exitCode == 0)
        #expect(commands.filter { $0.arguments == ["--version"] }.count == 2)
        #expect(commands.filter { $0.arguments != ["--version"] }.count == 1)
    }

    @Test("Compile omits OpenVAF version when executable changes during compilation")
    func compileOmitsOpenVAFVersionWhenExecutableChangesDuringCompilation() async throws {
        let sandbox = try TemporaryDirectory(name: "version-artifact-replacement-race")
        defer { sandbox.remove() }

        let sourceURL = sandbox.url.appendingPathComponent("compile_race.va")
        let outputDirectory = sandbox.url.appendingPathComponent("out")
        try "module compile_race; endmodule\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let executableURL = sandbox.url.appendingPathComponent("openvaf")
        try writeExecutableMarker("first", to: executableURL)

        let runner = RecordingProcessRunner { command in
            if command.arguments == ["--version"] {
                return OpenVAFProcessResult(
                    exitCode: 0,
                    standardOutput: "OpenVAF 1.0.0\n",
                    standardError: "",
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }

            try writeExecutableMarker("second", to: command.executableURL)
            let outputURL = command.workingDirectory.appendingPathComponent("compile_race.osdi")
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

        let artifact = try await compiler.compile(sourceAt: sourceURL, to: outputDirectory)
        let commands = await runner.recordedCommands()

        #expect(artifact.openVAFVersion == nil)
        #expect(commands.filter { $0.arguments == ["--version"] }.count == 1)
    }

    @Test("Compile resolves and runs fake OpenVAF through Foundation process runner")
    func compileResolvesAndRunsFakeOpenVAFThroughFoundationProcessRunner() async throws {
        let sandbox = try TemporaryDirectory(name: "fake-openvaf")
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

private struct OverwritingFileExecutableResolver: OpenVAFExecutableResolving {
    let executableURL: URL
    let fileURL: URL
    let contents: String

    func resolve(
        _ executable: OpenVAFExecutable,
        environment: [String: String]
    ) throws(OpenVAFError) -> URL {
        do {
            try Data(contents.utf8).write(to: fileURL)
        } catch {
            throw .fileSystemFailure(
                operation: "overwrite file",
                path: fileURL.path,
                message: error.localizedDescription
            )
        }
        return executableURL
    }
}

private struct SwappingIncludeExecutableResolver: OpenVAFExecutableResolving {
    let executableURL: URL
    let symlinkURL: URL
    let replacementTargetURL: URL

    func resolve(
        _ executable: OpenVAFExecutable,
        environment: [String: String]
    ) throws(OpenVAFError) -> URL {
        do {
            if FileManager.default.fileExists(atPath: symlinkURL.path) {
                try FileManager.default.removeItem(at: symlinkURL)
            }
            try FileManager.default.createSymbolicLink(
                at: symlinkURL,
                withDestinationURL: replacementTargetURL
            )
        } catch {
            throw .fileSystemFailure(
                operation: "swap include",
                path: symlinkURL.path,
                message: error.localizedDescription
            )
        }
        return executableURL
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

private func compileThroughOSDIProtocol<Compiler: VerilogAOSDICompiling>(
    _ compiler: Compiler,
    sourceURL: URL,
    outputDirectory: URL
) async throws -> Compiler.Artifact {
    try await compiler.compileOSDI(
        sourceAt: sourceURL,
        to: outputDirectory
    )
}

private func restoreWritablePermissions(at url: URL) {
    do {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: url.path
            )
        }
    } catch {
        Issue.record("Failed to restore writable permissions for \(url.path): \(error)")
    }
}

private func createFIFO(at url: URL) throws {
    guard mkfifo(url.path, 0o644) == 0 else {
        let code = POSIXErrorCode(rawValue: errno) ?? .EIO
        throw POSIXError(code)
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

private func writeExecutableMarker(_ marker: String, to url: URL) throws {
    let script = """
#!/bin/sh
printf '%s\\n' '\(marker)'
"""
    try Data(script.utf8).write(to: url)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: url.path
    )
}

private func isSHA256Hex(_ value: String) -> Bool {
    guard value.count == 64 else { return false }
    return value.allSatisfy { character in
        character.isNumber || ("a"..."f").contains(character)
    }
}

#endif
