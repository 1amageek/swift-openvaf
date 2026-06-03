import Foundation
import CryptoKit

/// OpenVAF compiler implementation backed by the OpenVAF command line tool.
public struct CommandLineOpenVAFCompiler: OpenVAFCompiler {
    private static let maximumInstallationQueryAttempts = 2

    private let configuration: OpenVAFConfiguration
    private let executableResolver: any OpenVAFExecutableResolving
    private let processRunner: any OpenVAFProcessRunning
    private let installationCache: OpenVAFInstallationCache

    public init(configuration: OpenVAFConfiguration = OpenVAFConfiguration()) {
        self.init(
            configuration: configuration,
            executableResolver: PATHOpenVAFExecutableResolver(),
            processRunner: FoundationOpenVAFProcessRunner(),
            installationCache: OpenVAFInstallationCache()
        )
    }

    package init(
        configuration: OpenVAFConfiguration,
        executableResolver: any OpenVAFExecutableResolving,
        processRunner: any OpenVAFProcessRunning,
        installationCache: OpenVAFInstallationCache = OpenVAFInstallationCache()
    ) {
        self.configuration = configuration
        self.executableResolver = executableResolver
        self.processRunner = processRunner
        self.installationCache = installationCache
    }

    public func availability() async -> OpenVAFAvailability {
        do {
            try validateConfiguration(for: .availability)
        } catch {
            return .unavailable(unavailableReason(from: error))
        }

        let environment = effectiveEnvironment()
        let executableURL: URL

        do {
            executableURL = try executableResolver.resolve(configuration.executable, environment: environment)
        } catch {
            return .unavailable(unavailableReason(from: error))
        }

        let command = OpenVAFProcessCommand(
            executableURL: executableURL,
            arguments: ["--version"],
            environment: environment,
            workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            timeout: configuration.availabilityTimeout,
            terminationGrace: configuration.terminationGrace
        )

        return await queryAvailability(command: command)
    }

    private enum InstallationQueryResult {
        case available(InstallationMetadata)
        case unavailable(OpenVAFUnavailableReason)
        case unstable
    }

    private func queryAvailability(command: OpenVAFProcessCommand) async -> OpenVAFAvailability {
        for _ in 0..<Self.maximumInstallationQueryAttempts {
            let cacheSnapshot = installationCache.snapshot(for: command.executableURL)
            switch await queryInstallation(command: command, cacheSnapshot: cacheSnapshot) {
            case .available(let metadata):
                return .available(metadata.installation)
            case .unavailable(let reason):
                return .unavailable(reason)
            case .unstable:
                continue
            }
        }

        return .unavailable(.launchFailed(
            executablePath: command.executableURL.path,
            message: "Executable changed during version check"
        ))
    }

    private func queryInstallation(
        command: OpenVAFProcessCommand,
        cacheSnapshot: OpenVAFInstallationCache.Snapshot?
    ) async -> InstallationQueryResult {
        do {
            let result = try await processRunner.run(command)
            let output = [result.standardOutput, result.standardError]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            guard result.exitCode == 0 else {
                return .unavailable(.versionCheckFailed(
                    exitCode: result.exitCode,
                    standardOutput: result.standardOutput,
                    standardError: result.standardError
                ))
            }

            let installation = OpenVAFInstallation(
                executableURL: command.executableURL,
                version: Self.parseVersion(from: output),
                rawVersionOutput: output
            )
            if let cacheSnapshot {
                guard installationCache.isStable(cacheSnapshot, for: command.executableURL) else {
                    return .unstable
                }
                installationCache.store(installation, forStable: cacheSnapshot)
            }
            return .available(InstallationMetadata(
                installation: installation,
                cacheSnapshot: cacheSnapshot
            ))
        } catch let error as OpenVAFProcessError {
            return .unavailable(unavailableReason(from: error))
        } catch {
            return .unavailable(.launchFailed(
                executablePath: command.executableURL.path,
                message: error.localizedDescription
            ))
        }
    }

    public func compile(_ request: OpenVAFCompilationRequest) async throws(OpenVAFError) -> OpenVAFCompilationArtifact {
        try validateConfiguration(for: .compile)

        let environment = effectiveEnvironment()
        let source = try validate(request)
        let executableURL = try executableResolver.resolve(configuration.executable, environment: environment)
        let prepared = try stage(source)
        let installationMetadata = await availableInstallation(matching: executableURL, environment: environment)
        let arguments = configuration.compilerArguments + [prepared.stagedSourceURL.lastPathComponent]
        let commandRecord = OpenVAFCommandRecord(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectory: prepared.commandWorkingDirectory,
            environment: environmentRecord(from: environment)
        )

        let command = OpenVAFProcessCommand(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            workingDirectory: prepared.commandWorkingDirectory,
            timeout: configuration.compileTimeout,
            terminationGrace: configuration.terminationGrace
        )

        do {
            let result = try await processRunner.run(command)

            guard result.exitCode == 0 else {
                throw OpenVAFError.compilationFailed(compilationFailure(
                    prepared: prepared,
                    command: commandRecord,
                    installationMetadata: installationMetadata,
                    exitCode: result.exitCode,
                    standardOutput: result.standardOutput,
                    standardError: result.standardError,
                    startedAt: result.startedAt,
                    finishedAt: result.finishedAt
                ))
            }

            guard isValidOutputFile(at: prepared.outputURL) else {
                throw OpenVAFError.outputMissing(compilationFailure(
                    prepared: prepared,
                    command: commandRecord,
                    installationMetadata: installationMetadata,
                    exitCode: result.exitCode,
                    standardOutput: result.standardOutput,
                    standardError: result.standardError,
                    startedAt: result.startedAt,
                    finishedAt: result.finishedAt
                ))
            }

            return OpenVAFCompilationArtifact(
                sourceURL: prepared.requestedSourceURL,
                sourceSHA256: prepared.sourceSHA256,
                stagedSourceURL: prepared.stagedSourceURL,
                outputURL: prepared.outputURL,
                command: commandRecord,
                openVAFVersion: openVAFVersion(from: installationMetadata),
                exitCode: result.exitCode,
                standardOutput: result.standardOutput,
                standardError: result.standardError,
                startedAt: result.startedAt,
                finishedAt: result.finishedAt
            )
        } catch let error as OpenVAFProcessError {
            cleanupFailedWorkingDirectory(prepared.stagingRootDirectory)
            throw compileError(
                from: error,
                prepared: prepared,
                command: commandRecord,
                installationMetadata: installationMetadata
            )
        } catch let error as OpenVAFError {
            cleanupFailedWorkingDirectory(prepared.stagingRootDirectory)
            throw error
        } catch {
            cleanupFailedWorkingDirectory(prepared.stagingRootDirectory)
            throw .launchFailed(executablePath: executableURL.path, message: error.localizedDescription)
        }
    }

    private struct PreparedSource {
        let requestedSourceURL: URL
        let sourceURL: URL
        let stagingRootDirectory: URL
        let commandWorkingDirectory: URL
        let stagedSourceURL: URL
        let outputURL: URL
        let sourceSHA256: String
    }

    private struct ValidatedSource {
        let requestedSourceURL: URL
        let sourceURL: URL
        let stagedSourceFileName: String
        let outputDirectory: URL
        let outputFileName: String
        let includeRootDirectory: URL
    }

    private struct PendingIncludeScan {
        let logicalURL: URL
        let stagedURL: URL
        let resolvedURL: URL
        let ancestorResolvedPaths: Set<String>
    }

    private struct IncludeScanContext: Hashable {
        let resolvedPath: String
        let logicalDirectoryPath: String
    }

    private struct InstallationMetadata {
        let installation: OpenVAFInstallation
        let cacheSnapshot: OpenVAFInstallationCache.Snapshot?
    }

    private enum ConfigurationUse {
        case availability
        case compile
    }

    private func validateConfiguration(for use: ConfigurationUse) throws(OpenVAFError) {
        try validateExecutableConfiguration(configuration.executable)
        if let processEnvironment = configuration.processEnvironment {
            try validateProcessEnvironment(processEnvironment)
        }
        try validatePositiveDuration(
            configuration.availabilityTimeout,
            field: "availabilityTimeout"
        )
        try validateNonNegativeDuration(
            configuration.terminationGrace,
            field: "terminationGrace"
        )

        if use == .compile {
            try validatePositiveDuration(
                configuration.compileTimeout,
                field: "compileTimeout"
            )
            try validateCompilerArguments(configuration.compilerArguments)
        }
    }

    private func validateExecutableConfiguration(_ executable: OpenVAFExecutable) throws(OpenVAFError) {
        switch executable {
        case .environment(let variable, let fallbackName):
            guard !variable.isEmpty else {
                throw .invalidConfiguration(
                    field: "executable.variable",
                    message: "Environment variable name must not be empty"
                )
            }

            guard !variable.contains("=") else {
                throw .invalidConfiguration(
                    field: "executable.variable",
                    message: "Environment variable name must not contain '='"
                )
            }

            guard !containsNUL(variable) else {
                throw .invalidConfiguration(
                    field: "executable.variable",
                    message: "Environment variable name must not contain NUL"
                )
            }

            guard !containsNUL(fallbackName) else {
                throw .invalidConfiguration(
                    field: "executable.fallbackName",
                    message: "Executable fallback name must not contain NUL"
                )
            }

            try OpenVAFExecutableNameValidator.validate(fallbackName)
        case .path(let path):
            try OpenVAFExecutablePathValidator.validate(path)
        case .name(let name):
            guard !containsNUL(name) else {
                throw .invalidConfiguration(
                    field: "executable.name",
                    message: "Executable name must not contain NUL"
                )
            }

            try OpenVAFExecutableNameValidator.validate(name)
        }
    }

    private func validateProcessEnvironment(_ environment: [String: String]) throws(OpenVAFError) {
        for (key, value) in environment {
            guard !key.isEmpty else {
                throw .invalidConfiguration(
                    field: "processEnvironment",
                    message: "Environment variable names must not be empty"
                )
            }

            guard !key.contains("=") else {
                throw .invalidConfiguration(
                    field: "processEnvironment",
                    message: "Environment variable names must not contain '='"
                )
            }

            guard !containsNUL(key) else {
                throw .invalidConfiguration(
                    field: "processEnvironment",
                    message: "Environment variable names must not contain NUL"
                )
            }

            guard !containsNUL(value) else {
                throw .invalidConfiguration(
                    field: "processEnvironment.\(key)",
                    message: "Environment variable values must not contain NUL"
                )
            }
        }
    }

    private func validateCompilerArguments(_ arguments: [String]) throws(OpenVAFError) {
        for (index, argument) in arguments.enumerated() {
            guard !containsNUL(argument) else {
                throw .invalidConfiguration(
                    field: "compilerArguments[\(index)]",
                    message: "Argument must not contain NUL"
                )
            }
        }
    }

    private func containsNUL(_ value: String) -> Bool {
        value.contains("\0")
    }

    private func validatedRequestFileURL(
        _ url: URL,
        operation: String,
        nonFileMessage: String,
        nulMessage: String
    ) throws(OpenVAFError) -> URL {
        guard url.isFileURL else {
            throw .fileSystemFailure(
                operation: operation,
                path: url.absoluteString,
                message: nonFileMessage
            )
        }

        if let host = url.host(),
           !host.isEmpty,
           host.lowercased() != "localhost" {
            throw .fileSystemFailure(
                operation: operation,
                path: url.absoluteString,
                message: "File URL host must be empty or localhost"
            )
        }

        let decodedPath = url.path(percentEncoded: false)
        guard !containsNUL(decodedPath) else {
            throw .fileSystemFailure(
                operation: operation,
                path: url.path(percentEncoded: true),
                message: nulMessage
            )
        }

        let path = url.path
        guard !path.isEmpty else {
            throw .fileSystemFailure(
                operation: operation,
                path: url.absoluteString,
                message: "File URL path must not be empty"
            )
        }

        return URL(fileURLWithPath: path).standardized
    }

    private func validatePositiveDuration(
        _ duration: Duration,
        field: String
    ) throws(OpenVAFError) {
        guard duration > .zero else {
            throw .invalidConfiguration(
                field: field,
                message: "Duration must be greater than zero"
            )
        }
    }

    private func validateNonNegativeDuration(
        _ duration: Duration,
        field: String
    ) throws(OpenVAFError) {
        guard duration >= .zero else {
            throw .invalidConfiguration(
                field: field,
                message: "Duration must not be negative"
            )
        }
    }

    private func validate(_ request: OpenVAFCompilationRequest) throws(OpenVAFError) -> ValidatedSource {
        let fileManager = FileManager.default
        let requestedSourceURL = request.sourceURL
        let sourceURL = try validatedRequestFileURL(
            requestedSourceURL,
            operation: "validate source",
            nonFileMessage: "Source URL must be a file URL",
            nulMessage: "Source path must not contain NUL"
        )
        let outputDirectory = try validatedRequestFileURL(
            request.outputDirectory,
            operation: "validate output directory",
            nonFileMessage: "Output directory URL must be a file URL",
            nulMessage: "Output directory path must not contain NUL"
        )
        try validateOutputDirectory(outputDirectory)

        let requestedIncludeRootDirectory: URL?
        if let includeRootDirectory = request.includeRootDirectory {
            requestedIncludeRootDirectory = try validatedRequestFileURL(
                includeRootDirectory,
                operation: "validate include root",
                nonFileMessage: "Include root URL must be a file URL",
                nulMessage: "Include root path must not contain NUL"
            )
        } else {
            requestedIncludeRootDirectory = nil
        }

        let outputFileName = try validatedOutputFileName(
            request.outputFileName,
            sourceURL: sourceURL
        )

        let sourceFileName = sourceURL.lastPathComponent
        guard !sourceFileName.isEmpty,
              sourceFileName != ".",
              sourceFileName != ".." else {
            throw .fileSystemFailure(
                operation: "validate source",
                path: sourceURL.path,
                message: "Source URL must identify a file"
            )
        }

        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw .fileSystemFailure(
                operation: "read source",
                path: sourceURL.path,
                message: "File does not exist"
            )
        }

        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw .fileSystemFailure(
                operation: "read source",
                path: sourceURL.path,
                message: "Source must be a regular file"
            )
        }

        guard fileManager.isReadableFile(atPath: sourceURL.path) else {
            throw .fileSystemFailure(
                operation: "read source",
                path: sourceURL.path,
                message: "File is not readable"
            )
        }

        guard isRegularFile(at: sourceURL) else {
            throw .fileSystemFailure(
                operation: "read source",
                path: sourceURL.path,
                message: "Source must be a regular file"
            )
        }

        let includeRootDirectory = try validatedIncludeRootDirectory(
            requestedIncludeRootDirectory ?? sourceURL.deletingLastPathComponent(),
            sourceDirectory: sourceURL.deletingLastPathComponent()
        )
        let stagedFileName = stagedSourceFileName(
            outputFileName: outputFileName,
            sourceURL: sourceURL
        )

        return ValidatedSource(
            requestedSourceURL: requestedSourceURL,
            sourceURL: sourceURL,
            stagedSourceFileName: stagedFileName,
            outputDirectory: outputDirectory,
            outputFileName: outputFileName,
            includeRootDirectory: includeRootDirectory
        )
    }

    private func stage(_ source: ValidatedSource) throws(OpenVAFError) -> PreparedSource {
        let fileManager = FileManager.default
        let sourceRootDirectory = source.includeRootDirectory
        let stagingRootDirectory = source.outputDirectory.appendingPathComponent("openvaf-\(UUID().uuidString)")
        let outputDirectoryExisted = fileManager.fileExists(atPath: source.outputDirectory.path)
        let sourceRelativeDirectory = try relativePath(
            from: sourceRootDirectory,
            to: source.sourceURL.deletingLastPathComponent()
        )
        let commandWorkingDirectory = appendingRelativePath(
            sourceRelativeDirectory,
            to: stagingRootDirectory
        )
        let stagedSourceURL = commandWorkingDirectory.appendingPathComponent(source.stagedSourceFileName)
        let outputURL = commandWorkingDirectory.appendingPathComponent(source.outputFileName)

        do {
            try fileManager.createDirectory(at: commandWorkingDirectory, withIntermediateDirectories: true)
        } catch {
            throw .fileSystemFailure(
                operation: "create working directory",
                path: commandWorkingDirectory.path,
                message: error.localizedDescription
            )
        }

        let sourceCopyURL: URL
        do {
            sourceCopyURL = try validatedSourceCopyURL(source.sourceURL)
        } catch {
            cleanupFailedStaging(
                stagingRootDirectory: stagingRootDirectory,
                outputDirectory: source.outputDirectory,
                outputDirectoryExisted: outputDirectoryExisted
            )
            throw error
        }

        do {
            try fileManager.copyItem(at: sourceCopyURL, to: stagedSourceURL)
        } catch {
            cleanupFailedStaging(
                stagingRootDirectory: stagingRootDirectory,
                outputDirectory: source.outputDirectory,
                outputDirectoryExisted: outputDirectoryExisted
            )
            throw .fileSystemFailure(
                operation: "stage source",
                path: stagedSourceURL.path,
                message: error.localizedDescription
            )
        }

        do {
            try stageIncludesDiscoveredFromStagedFiles(
                sourceLogicalURL: source.sourceURL,
                sourceResolvedURL: sourceCopyURL,
                sourceRootDirectory: sourceRootDirectory,
                stagingRootDirectory: stagingRootDirectory,
                stagedSourceURL: stagedSourceURL,
                outputURL: outputURL,
                outputFileName: source.outputFileName
            )
        } catch {
            cleanupFailedStaging(
                stagingRootDirectory: stagingRootDirectory,
                outputDirectory: source.outputDirectory,
                outputDirectoryExisted: outputDirectoryExisted
            )
            throw error
        }

        let sourceSHA256: String
        do {
            sourceSHA256 = try sha256HexDigest(of: stagedSourceURL)
        } catch {
            cleanupFailedStaging(
                stagingRootDirectory: stagingRootDirectory,
                outputDirectory: source.outputDirectory,
                outputDirectoryExisted: outputDirectoryExisted
            )
            throw error
        }

        return PreparedSource(
            requestedSourceURL: source.requestedSourceURL,
            sourceURL: source.sourceURL,
            stagingRootDirectory: stagingRootDirectory,
            commandWorkingDirectory: commandWorkingDirectory,
            stagedSourceURL: stagedSourceURL,
            outputURL: outputURL,
            sourceSHA256: sourceSHA256
        )
    }

    private func validatedIncludeRootDirectory(
        _ includeRootDirectory: URL,
        sourceDirectory: URL
    ) throws(OpenVAFError) -> URL {
        let standardizedRoot = includeRootDirectory.standardized
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: standardizedRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw .fileSystemFailure(
                operation: "validate include root",
                path: standardizedRoot.path,
                message: "Include root must be an existing directory"
            )
        }

        let standardizedSourceDirectory = sourceDirectory.standardized
        let resolvedRoot = standardizedRoot.resolvingSymlinksInPath().standardized
        let resolvedSourceDirectory = standardizedSourceDirectory.resolvingSymlinksInPath().standardized
        let sourceIsInsideResolvedRoot = isPath(resolvedSourceDirectory, inside: resolvedRoot)

        if isPath(standardizedSourceDirectory, inside: standardizedRoot),
           sourceIsInsideResolvedRoot {
            return standardizedRoot
        }

        if isPath(standardizedSourceDirectory, inside: resolvedRoot),
           sourceIsInsideResolvedRoot {
            return resolvedRoot
        }

        throw .fileSystemFailure(
            operation: "validate include root",
            path: standardizedRoot.path,
            message: "Include root must contain the source directory"
        )
    }

    private func stageIncludesDiscoveredFromStagedFiles(
        sourceLogicalURL: URL,
        sourceResolvedURL: URL,
        sourceRootDirectory: URL,
        stagingRootDirectory: URL,
        stagedSourceURL: URL,
        outputURL: URL,
        outputFileName: String
    ) throws(OpenVAFError) {
        var pending = [PendingIncludeScan(
            logicalURL: sourceLogicalURL,
            stagedURL: stagedSourceURL,
            resolvedURL: sourceResolvedURL,
            ancestorResolvedPaths: []
        )]
        var scannedContexts: Set<IncludeScanContext> = []
        var stagedIncludes: Set<String> = []

        while let pendingScan = pending.popLast() {
            let currentURL = pendingScan.logicalURL
            let currentKey = pendingScan.resolvedURL.standardized.path
            guard !pendingScan.ancestorResolvedPaths.contains(currentKey) else { continue }

            let scanContext = IncludeScanContext(
                resolvedPath: currentKey,
                logicalDirectoryPath: currentURL.deletingLastPathComponent().standardized.path
            )
            guard scannedContexts.insert(scanContext).inserted else { continue }

            var descendantResolvedPaths = pendingScan.ancestorResolvedPaths
            descendantResolvedPaths.insert(currentKey)

            let includePaths = try VerilogAIncludeScanner.includePaths(
                in: pendingScan.stagedURL
            )
            for includePath in includePaths {
                guard let includeURL = try localIncludeURL(
                    includePath,
                    relativeTo: currentURL,
                    includeRootDirectory: sourceRootDirectory
                ) else {
                    continue
                }

                let includeKey = includeURL.standardized.path
                guard stagedIncludes.insert(includeKey).inserted else { continue }

                let relativeIncludePath = try relativePath(from: sourceRootDirectory, to: includeURL)
                let stagedIncludeURL = appendingRelativePath(relativeIncludePath, to: stagingRootDirectory)
                try validateStagedIncludeURL(
                    stagedIncludeURL,
                    stagedSourceURL: stagedSourceURL,
                    outputURL: outputURL,
                    outputFileName: outputFileName
                )

                let copySourceURL = try validatedIncludeCopySourceURL(
                    includeURL,
                    includeRootDirectory: sourceRootDirectory
                )
                do {
                    try FileManager.default.createDirectory(
                        at: stagedIncludeURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try FileManager.default.copyItem(
                        at: copySourceURL,
                        to: stagedIncludeURL
                    )
                } catch {
                    throw .fileSystemFailure(
                        operation: "stage include",
                        path: stagedIncludeURL.path,
                        message: error.localizedDescription
                    )
                }

                let includeScanKey = copySourceURL.standardized.path
                if !descendantResolvedPaths.contains(includeScanKey) {
                    pending.append(PendingIncludeScan(
                        logicalURL: includeURL,
                        stagedURL: stagedIncludeURL,
                        resolvedURL: copySourceURL,
                        ancestorResolvedPaths: descendantResolvedPaths
                    ))
                }
            }
        }
    }

    private func localIncludeURL(
        _ includePath: String,
        relativeTo includingURL: URL,
        includeRootDirectory: URL
    ) throws(OpenVAFError) -> URL? {
        guard !containsNUL(includePath) else {
            throw .fileSystemFailure(
                operation: "read include",
                path: includePath,
                message: "Include path must not contain NUL"
            )
        }

        guard !includePath.hasPrefix("/") else {
            throw .fileSystemFailure(
                operation: "read include",
                path: includePath,
                message: "Absolute include paths are not supported"
            )
        }

        let includeURL = includingURL
            .deletingLastPathComponent()
            .appendingPathComponent(includePath)
            .standardized

        guard FileManager.default.fileExists(atPath: includeURL.path) else {
            return nil
        }

        _ = try validatedIncludeCopySourceURL(
            includeURL,
            includeRootDirectory: includeRootDirectory
        )
        return includeURL
    }

    private func validatedSourceCopyURL(_ sourceURL: URL) throws(OpenVAFError) -> URL {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw .fileSystemFailure(
                operation: "stage source",
                path: sourceURL.path,
                message: "Source must be a regular file"
            )
        }

        guard FileManager.default.isReadableFile(atPath: sourceURL.path) else {
            throw .fileSystemFailure(
                operation: "stage source",
                path: sourceURL.path,
                message: "File is not readable"
            )
        }

        let resolvedURL = sourceURL.resolvingSymlinksInPath()
        do {
            let values = try resolvedURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                throw OpenVAFError.fileSystemFailure(
                    operation: "stage source",
                    path: sourceURL.path,
                    message: "Source must be a regular file"
                )
            }
        } catch let error as OpenVAFError {
            throw error
        } catch {
            throw .fileSystemFailure(
                operation: "stage source",
                path: sourceURL.path,
                message: error.localizedDescription
            )
        }

        return resolvedURL
    }

    private func validatedIncludeCopySourceURL(
        _ includeURL: URL,
        includeRootDirectory: URL
    ) throws(OpenVAFError) -> URL {
        let resolvedIncludeURL = includeURL.resolvingSymlinksInPath()
        let resolvedIncludeRootDirectory = includeRootDirectory.resolvingSymlinksInPath()

        guard isPath(includeURL, inside: includeRootDirectory),
              isPath(resolvedIncludeURL, inside: resolvedIncludeRootDirectory) else {
            throw .fileSystemFailure(
                operation: "read include",
                path: includeURL.path,
                message: "Include is outside include root"
            )
        }

        try validateIncludeFile(at: includeURL, resolvedURL: resolvedIncludeURL)
        return resolvedIncludeURL
    }

    private func validateIncludeFile(at includeURL: URL, resolvedURL: URL) throws(OpenVAFError) {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: includeURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw .fileSystemFailure(
                operation: "read include",
                path: includeURL.path,
                message: "Include must be a regular file"
            )
        }

        guard FileManager.default.isReadableFile(atPath: includeURL.path) else {
            throw .fileSystemFailure(
                operation: "read include",
                path: includeURL.path,
                message: "Include file is not readable"
            )
        }

        do {
            let values = try resolvedURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                throw OpenVAFError.fileSystemFailure(
                    operation: "read include",
                    path: includeURL.path,
                    message: "Include must be a regular file"
                )
            }
        } catch let error as OpenVAFError {
            throw error
        } catch {
            throw .fileSystemFailure(
                operation: "read include",
                path: includeURL.path,
                message: error.localizedDescription
            )
        }
    }

    private func relativePath(from rootURL: URL, to targetURL: URL) throws(OpenVAFError) -> String {
        let rootComponents = rootURL.standardized.pathComponents
        let targetComponents = targetURL.standardized.pathComponents

        guard targetComponents.count >= rootComponents.count,
              zip(rootComponents, targetComponents).allSatisfy({ $0 == $1 }) else {
            throw .fileSystemFailure(
                operation: "stage source",
                path: targetURL.path,
                message: "Path is outside staging root"
            )
        }

        return targetComponents
            .dropFirst(rootComponents.count)
            .joined(separator: "/")
    }

    private func appendingRelativePath(_ relativePath: String, to baseURL: URL) -> URL {
        guard !relativePath.isEmpty else { return baseURL }
        return baseURL.appendingPathComponent(relativePath)
    }

    private func isPath(_ candidateURL: URL, inside rootURL: URL) -> Bool {
        let candidateComponents = candidateURL.standardized.pathComponents
        let rootComponents = rootURL.standardized.pathComponents
        guard candidateComponents.count >= rootComponents.count else { return false }
        return zip(rootComponents, candidateComponents).allSatisfy { $0 == $1 }
    }

    private func validateStagedIncludeURL(
        _ stagedIncludeURL: URL,
        stagedSourceURL: URL,
        outputURL: URL,
        outputFileName: String
    ) throws(OpenVAFError) {
        guard stagedIncludeURL != stagedSourceURL,
              stagedIncludeURL != outputURL else {
            throw .invalidOutputFileName(
                outputFileName,
                message: "Output file name would collide with a staged include"
            )
        }
    }

    private func validateOutputDirectory(_ outputDirectory: URL) throws(OpenVAFError) {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: outputDirectory.path, isDirectory: &isDirectory) else {
            return
        }

        guard isDirectory.boolValue else {
            throw .fileSystemFailure(
                operation: "validate output directory",
                path: outputDirectory.path,
                message: "Output directory must be a directory"
            )
        }
    }

    private func validatedOutputFileName(
        _ requestedFileName: String?,
        sourceURL: URL
    ) throws(OpenVAFError) -> String {
        let fileName = requestedFileName
            ?? sourceURL.deletingPathExtension().lastPathComponent + ".osdi"

        guard !fileName.isEmpty else {
            throw .invalidOutputFileName(fileName, message: "File name must not be empty")
        }

        guard !containsNUL(fileName) else {
            throw .invalidOutputFileName(fileName, message: "File name must not contain NUL")
        }

        guard fileName == URL(fileURLWithPath: fileName).lastPathComponent else {
            throw .invalidOutputFileName(fileName, message: "File name must not contain path components")
        }

        guard fileName != "." && fileName != ".." else {
            throw .invalidOutputFileName(fileName, message: "File name must not be a relative path marker")
        }

        guard URL(fileURLWithPath: fileName).pathExtension == "osdi" else {
            throw .invalidOutputFileName(fileName, message: "File name must use the .osdi extension")
        }

        return fileName
    }

    private func stagedSourceFileName(outputFileName: String, sourceURL: URL) -> String {
        let outputBaseName = URL(fileURLWithPath: outputFileName)
            .deletingPathExtension()
            .lastPathComponent
        let sourceExtension = stagedSourceExtension(for: sourceURL)

        guard !sourceExtension.isEmpty else {
            return outputBaseName
        }

        return "\(outputBaseName).\(sourceExtension)"
    }

    private func stagedSourceExtension(for sourceURL: URL) -> String {
        let sourceExtension = sourceURL.pathExtension
        guard sourceExtension.lowercased() != "osdi" else {
            return "va"
        }
        return sourceExtension
    }

    private func sha256HexDigest(of sourceURL: URL) throws(OpenVAFError) -> String {
        guard let stream = InputStream(url: sourceURL) else {
            throw .fileSystemFailure(
                operation: "hash source",
                path: sourceURL.path,
                message: "Unable to open input stream"
            )
        }
        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let byteCount = buffer.withUnsafeMutableBufferPointer { pointer in
                guard let baseAddress = pointer.baseAddress else { return 0 }
                return stream.read(baseAddress, maxLength: pointer.count)
            }

            if byteCount > 0 {
                buffer.withUnsafeBufferPointer { pointer in
                    guard let baseAddress = pointer.baseAddress else { return }
                    let rawBuffer = UnsafeRawBufferPointer(start: baseAddress, count: byteCount)
                    hasher.update(bufferPointer: rawBuffer)
                }
                continue
            }

            if byteCount == 0 {
                break
            }

            throw .fileSystemFailure(
                operation: "hash source",
                path: sourceURL.path,
                message: stream.streamError?.localizedDescription ?? "Input stream read failed"
            )
        }

        return sha256HexDigest(of: hasher.finalize())
    }

    private func sha256HexDigest(of environment: [String: String]) -> String {
        var hasher = SHA256()
        for key in environment.keys.sorted() {
            updateSHA256(&hasher, withLengthPrefixed: key)
            updateSHA256(&hasher, withLengthPrefixed: environment[key] ?? "")
        }
        return sha256HexDigest(of: hasher.finalize())
    }

    private func updateSHA256(_ hasher: inout SHA256, withLengthPrefixed value: String) {
        let data = Data(value.utf8)
        var byteCount = UInt64(data.count).bigEndian
        withUnsafeBytes(of: &byteCount) { buffer in
            hasher.update(bufferPointer: buffer)
        }
        hasher.update(data: data)
    }

    private func sha256HexDigest<Digest: Sequence>(of digest: Digest) -> String where Digest.Element == UInt8 {
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func effectiveEnvironment() -> [String: String] {
        configuration.processEnvironment ?? ProcessInfo.processInfo.environment
    }

    private func environmentRecord(from environment: [String: String]) -> OpenVAFEnvironmentRecord {
        let recordedEnvironment = recordedEnvironment(from: environment)
        return OpenVAFEnvironmentRecord(
            source: configuration.processEnvironment == nil ? .inherited : .explicit,
            keys: Array(recordedEnvironment.keys),
            valueSHA256: sha256HexDigest(of: recordedEnvironment)
        )
    }

    private func recordedEnvironment(from environment: [String: String]) -> [String: String] {
        guard configuration.processEnvironment == nil else {
            return environment
        }

        let inheritedKeys = [
            "OPENVAF_BIN",
            "PATH",
            "DYLD_LIBRARY_PATH",
            "LD_LIBRARY_PATH",
        ]
        return environment.filter { key, _ in
            inheritedKeys.contains(key)
        }
    }

    private func availableInstallation(
        matching executableURL: URL,
        environment: [String: String]
    ) async -> InstallationMetadata? {
        let command = OpenVAFProcessCommand(
            executableURL: executableURL,
            arguments: ["--version"],
            environment: environment,
            workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            timeout: configuration.availabilityTimeout,
            terminationGrace: configuration.terminationGrace
        )

        for _ in 0..<Self.maximumInstallationQueryAttempts {
            let cacheSnapshot = installationCache.snapshot(for: executableURL)
            if let cacheSnapshot,
               let installation = installationCache.installation(for: cacheSnapshot) {
                return InstallationMetadata(installation: installation, cacheSnapshot: cacheSnapshot)
            }

            switch await queryInstallation(command: command, cacheSnapshot: cacheSnapshot) {
            case .available(let metadata)
                where metadata.installation.executableURL.standardizedFileURL == executableURL.standardizedFileURL:
                return metadata
            case .available, .unavailable:
                return nil
            case .unstable:
                continue
            }
        }

        return nil
    }

    private func cleanupFailedWorkingDirectory(_ url: URL) {
        guard !configuration.keepsFailedWorkingDirectories else { return }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            // Preserve the primary compile failure. Cleanup failure is secondary.
        }
    }

    private func cleanupFailedStaging(
        stagingRootDirectory: URL,
        outputDirectory: URL,
        outputDirectoryExisted: Bool
    ) {
        cleanupFailedWorkingDirectory(stagingRootDirectory)
        guard !configuration.keepsFailedWorkingDirectories,
              !outputDirectoryExisted else {
            return
        }

        do {
            if FileManager.default.fileExists(atPath: outputDirectory.path) {
                let contents = try FileManager.default.contentsOfDirectory(
                    at: outputDirectory,
                    includingPropertiesForKeys: nil
                )
                guard contents.isEmpty else { return }
                try FileManager.default.removeItem(at: outputDirectory)
            }
        } catch {
            // Preserve the primary staging failure. Cleanup failure is secondary.
        }
    }

    private func isRegularFile(at url: URL) -> Bool {
        do {
            let resolvedURL = url.resolvingSymlinksInPath()
            let values = try resolvedURL.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true
        } catch {
            return false
        }
    }

    private func isValidOutputFile(at url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }

        do {
            let outputValues = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard outputValues.isSymbolicLink != true else {
                return false
            }

            let resolvedURL = url.resolvingSymlinksInPath()
            let values = try resolvedURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .linkCountKey,
            ])
            guard values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  values.linkCount == 1 else {
                return false
            }
            return fileSize > 0
        } catch {
            return false
        }
    }

    private func compilationFailure(
        prepared: PreparedSource,
        command: OpenVAFCommandRecord,
        installationMetadata: InstallationMetadata?,
        exitCode: Int32?,
        standardOutput: String,
        standardError: String,
        startedAt: Date?,
        finishedAt: Date?
    ) -> OpenVAFCompilationFailure {
        OpenVAFCompilationFailure(
            sourceURL: prepared.requestedSourceURL,
            sourceSHA256: prepared.sourceSHA256,
            stagedSourceURL: prepared.stagedSourceURL,
            outputURL: prepared.outputURL,
            command: command,
            openVAFVersion: openVAFVersion(from: installationMetadata),
            exitCode: exitCode,
            standardOutput: standardOutput,
            standardError: standardError,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
    }

    private func compileError(
        from error: OpenVAFProcessError,
        prepared: PreparedSource,
        command: OpenVAFCommandRecord,
        installationMetadata: InstallationMetadata?
    ) -> OpenVAFError {
        switch error {
        case .launchFailed(let executablePath, let message):
            return .launchFailed(executablePath: executablePath, message: message)
        case .timedOut(_, let timeout, let standardOutput, let standardError, let startedAt, let finishedAt):
            return .compilationTimedOut(
                compilationFailure(
                    prepared: prepared,
                    command: command,
                    installationMetadata: installationMetadata,
                    exitCode: nil,
                    standardOutput: standardOutput,
                    standardError: standardError,
                    startedAt: startedAt,
                    finishedAt: finishedAt
                ),
                timeout: timeout,
            )
        case .cancelled(_, let standardOutput, let standardError, let startedAt, let finishedAt):
            return .compilationCancelled(compilationFailure(
                prepared: prepared,
                command: command,
                installationMetadata: installationMetadata,
                exitCode: nil,
                standardOutput: standardOutput,
                standardError: standardError,
                startedAt: startedAt,
                finishedAt: finishedAt
            ))
        }
    }

    private func openVAFVersion(from metadata: InstallationMetadata?) -> String? {
        guard let metadata else { return nil }
        guard let cacheSnapshot = metadata.cacheSnapshot else { return nil }
        guard installationCache.isStable(cacheSnapshot, for: metadata.installation.executableURL) else {
            return nil
        }
        return metadata.installation.version
    }

    private func unavailableReason(from error: OpenVAFError) -> OpenVAFUnavailableReason {
        switch error {
        case .invalidConfiguration(let field, let message):
            return .invalidConfiguration(field: field, message: message)
        case .executableNotFound(let name, let searchedPaths):
            return .executableNotFound(name: name, searchedPaths: searchedPaths)
        case .invalidExecutableName(let name, let message):
            return .invalidExecutableName(name, message: message)
        case .notExecutable(let path):
            return .notExecutable(path: path)
        case .launchFailed(let executablePath, let message):
            return .launchFailed(executablePath: executablePath, message: message)
        case .timedOut(let executablePath, let timeout, let standardOutput, let standardError):
            return .timedOut(
                executablePath: executablePath,
                timeout: timeout,
                standardOutput: standardOutput,
                standardError: standardError
            )
        case .cancelled(let executablePath, let standardOutput, let standardError):
            return .cancelled(
                executablePath: executablePath,
                standardOutput: standardOutput,
                standardError: standardError
            )
        case .invalidOutputFileName,
                .fileSystemFailure,
                .compilationTimedOut,
                .compilationCancelled,
                .compilationFailed,
                .outputMissing:
            return .launchFailed(executablePath: "<unknown>", message: error.localizedDescription)
        }
    }

    private func unavailableReason(from error: OpenVAFProcessError) -> OpenVAFUnavailableReason {
        switch error {
        case .launchFailed(let executablePath, let message):
            return .launchFailed(executablePath: executablePath, message: message)
        case .timedOut(let executablePath, let timeout, let standardOutput, let standardError, _, _):
            return .timedOut(
                executablePath: executablePath,
                timeout: timeout,
                standardOutput: standardOutput,
                standardError: standardError
            )
        case .cancelled(let executablePath, let standardOutput, let standardError, _, _):
            return .cancelled(
                executablePath: executablePath,
                standardOutput: standardOutput,
                standardError: standardError
            )
        }
    }

    private static func parseVersion(from output: String) -> String? {
        let pattern = #"(?i)\bopenvaf\b[^\n\r0-9]*([0-9]+(?:\.[0-9]+){1,3}(?:[-+][A-Za-z0-9._-]+)?)"#
        for version in regexCaptures(in: output, pattern: pattern) {
            if isPlausibleVersion(version) {
                return version
            }
        }

        let fallbackPattern = #"(?<![0-9.])([0-9]+(?:\.[0-9]+){1,3}(?:[-+][A-Za-z0-9._-]+)?)(?![0-9.])"#
        for version in regexCaptures(in: output, pattern: fallbackPattern) {
            if isPlausibleVersion(version) {
                return version
            }
        }

        return nil
    }

    private static func isPlausibleVersion(_ version: String) -> Bool {
        guard let major = version.split(separator: ".").first,
              let majorValue = Int(major) else {
            return false
        }
        return majorValue < 1000
    }

    private static func regexCaptures(in text: String, pattern: String) -> [String] {
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern)
        } catch {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[range])
        }
    }
}
