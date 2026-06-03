import Foundation
import CryptoKit

/// OpenVAF compiler implementation backed by the OpenVAF command line tool.
public struct CommandLineOpenVAFCompiler: OpenVAFCompiler {
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

        return await queryInstallation(command: command)
    }

    private func queryInstallation(command: OpenVAFProcessCommand) async -> OpenVAFAvailability {
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
            installationCache.store(installation)
            return .available(installation)
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
        let installation = await availableInstallation(matching: executableURL, environment: environment)
        let prepared = try stage(source)
        let arguments = configuration.compilerArguments + [prepared.stagedSourceURL.lastPathComponent]
        let commandRecord = OpenVAFCommandRecord(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectory: prepared.workingDirectory,
            environment: environmentRecord(from: environment)
        )

        let command = OpenVAFProcessCommand(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            workingDirectory: prepared.workingDirectory,
            timeout: configuration.compileTimeout,
            terminationGrace: configuration.terminationGrace
        )

        do {
            let result = try await processRunner.run(command)

            guard result.exitCode == 0 else {
                throw OpenVAFError.compilationFailed(compilationFailure(
                    prepared: prepared,
                    command: commandRecord,
                    installation: installation,
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
                    installation: installation,
                    exitCode: result.exitCode,
                    standardOutput: result.standardOutput,
                    standardError: result.standardError,
                    startedAt: result.startedAt,
                    finishedAt: result.finishedAt
                ))
            }

            return OpenVAFCompilationArtifact(
                sourceURL: prepared.sourceURL,
                sourceSHA256: prepared.sourceSHA256,
                stagedSourceURL: prepared.stagedSourceURL,
                outputURL: prepared.outputURL,
                command: commandRecord,
                openVAFVersion: installation?.version,
                exitCode: result.exitCode,
                standardOutput: result.standardOutput,
                standardError: result.standardError,
                startedAt: result.startedAt,
                finishedAt: result.finishedAt
            )
        } catch let error as OpenVAFProcessError {
            cleanupFailedWorkingDirectory(prepared.workingDirectory)
            throw compileError(
                from: error,
                prepared: prepared,
                command: commandRecord,
                installation: installation
            )
        } catch let error as OpenVAFError {
            cleanupFailedWorkingDirectory(prepared.workingDirectory)
            throw error
        } catch {
            cleanupFailedWorkingDirectory(prepared.workingDirectory)
            throw .launchFailed(executablePath: executableURL.path, message: error.localizedDescription)
        }
    }

    private struct PreparedSource {
        let sourceURL: URL
        let workingDirectory: URL
        let stagedSourceURL: URL
        let outputURL: URL
        let sourceSHA256: String
    }

    private struct ValidatedSource {
        let sourceURL: URL
        let stagedSourceFileName: String
        let outputDirectory: URL
        let outputFileName: String
    }

    private enum ConfigurationUse {
        case availability
        case compile
    }

    private func validateConfiguration(for use: ConfigurationUse) throws(OpenVAFError) {
        try validateExecutableConfiguration(configuration.executable)
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
        }
    }

    private func validateExecutableConfiguration(_ executable: OpenVAFExecutable) throws(OpenVAFError) {
        switch executable {
        case .environment(let variable, _):
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
        case .path, .name:
            return
        }
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
        let outputDirectory = request.outputDirectory
        let sourceURL = request.sourceURL
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

        return ValidatedSource(
            sourceURL: sourceURL,
            stagedSourceFileName: stagedSourceFileName(
                outputFileName: outputFileName,
                sourceURL: sourceURL
            ),
            outputDirectory: outputDirectory,
            outputFileName: outputFileName
        )
    }

    private func stage(_ source: ValidatedSource) throws(OpenVAFError) -> PreparedSource {
        let fileManager = FileManager.default
        let workingDirectory = source.outputDirectory.appendingPathComponent("openvaf-\(UUID().uuidString)")
        let stagedSourceURL = workingDirectory.appendingPathComponent(source.stagedSourceFileName)
        let outputURL = workingDirectory.appendingPathComponent(source.outputFileName)

        do {
            try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        } catch {
            throw .fileSystemFailure(
                operation: "create working directory",
                path: workingDirectory.path,
                message: error.localizedDescription
            )
        }

        do {
            try fileManager.copyItem(
                at: source.sourceURL.resolvingSymlinksInPath(),
                to: stagedSourceURL
            )
        } catch {
            cleanupFailedWorkingDirectory(workingDirectory)
            throw .fileSystemFailure(
                operation: "stage source",
                path: stagedSourceURL.path,
                message: error.localizedDescription
            )
        }

        let sourceSHA256: String
        do {
            sourceSHA256 = try sha256HexDigest(of: stagedSourceURL)
        } catch {
            cleanupFailedWorkingDirectory(workingDirectory)
            throw error
        }

        return PreparedSource(
            sourceURL: source.sourceURL,
            workingDirectory: workingDirectory,
            stagedSourceURL: stagedSourceURL,
            outputURL: outputURL,
            sourceSHA256: sourceSHA256
        )
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
        let sourceExtension = sourceURL.pathExtension

        guard !sourceExtension.isEmpty else {
            return outputBaseName
        }

        return "\(outputBaseName).\(sourceExtension)"
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
        let payload = environment.keys.sorted().map { key in
            "\(key)=\(environment[key] ?? "")"
        }.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return sha256HexDigest(of: digest)
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
    ) async -> OpenVAFInstallation? {
        if let installation = installationCache.installation(for: executableURL) {
            return installation
        }

        let command = OpenVAFProcessCommand(
            executableURL: executableURL,
            arguments: ["--version"],
            environment: environment,
            workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            timeout: configuration.availabilityTimeout,
            terminationGrace: configuration.terminationGrace
        )
        let availability = await queryInstallation(command: command)
        switch availability {
        case .available(let installation)
            where installation.executableURL.standardizedFileURL == executableURL.standardizedFileURL:
            return installation
        case .available, .unavailable:
            return nil
        }
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
            let resolvedURL = url.resolvingSymlinksInPath()
            let values = try resolvedURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true,
                  let fileSize = values.fileSize else {
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
        installation: OpenVAFInstallation?,
        exitCode: Int32?,
        standardOutput: String,
        standardError: String,
        startedAt: Date?,
        finishedAt: Date?
    ) -> OpenVAFCompilationFailure {
        OpenVAFCompilationFailure(
            sourceURL: prepared.sourceURL,
            sourceSHA256: prepared.sourceSHA256,
            stagedSourceURL: prepared.stagedSourceURL,
            outputURL: prepared.outputURL,
            command: command,
            openVAFVersion: installation?.version,
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
        installation: OpenVAFInstallation?
    ) -> OpenVAFError {
        switch error {
        case .launchFailed(let executablePath, let message):
            return .launchFailed(executablePath: executablePath, message: message)
        case .timedOut(_, let timeout, let standardOutput, let standardError, let startedAt, let finishedAt):
            return .compilationTimedOut(
                compilationFailure(
                    prepared: prepared,
                    command: command,
                    installation: installation,
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
                installation: installation,
                exitCode: nil,
                standardOutput: standardOutput,
                standardError: standardError,
                startedAt: startedAt,
                finishedAt: finishedAt
            ))
        }
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
        if let version = firstRegexCapture(in: output, pattern: pattern) {
            return version
        }

        let fallbackPattern = #"(?<![0-9.])([0-9]+(?:\.[0-9]+){1,3}(?:[-+][A-Za-z0-9._-]+)?)(?![0-9.])"#
        for version in regexCaptures(in: output, pattern: fallbackPattern) {
            guard let major = version.split(separator: ".").first,
                  let majorValue = Int(major),
                  majorValue < 1000 else {
                continue
            }
            return version
        }

        return nil
    }

    private static func firstRegexCapture(in text: String, pattern: String) -> String? {
        regexCaptures(in: text, pattern: pattern).first
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
