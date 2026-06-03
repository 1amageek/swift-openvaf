import Foundation
import Darwin
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

private func isSHA256Hex(_ value: String) -> Bool {
    guard value.count == 64 else { return false }
    return value.allSatisfy { character in
        character.isNumber || ("a"..."f").contains(character)
    }
}
