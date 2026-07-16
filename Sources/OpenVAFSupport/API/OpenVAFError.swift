import Foundation

/// Typed errors emitted by OpenVAFSupport.
public enum OpenVAFError: Error, Sendable, Equatable {
    case invalidConfiguration(field: String, message: String)
    case executableNotFound(name: String, searchedPaths: [String])
    case invalidExecutableName(String, message: String)
    case notExecutable(path: String)
    case invalidOutputFileName(String, message: String)
    case fileSystemFailure(operation: String, path: String, message: String)
    case launchFailed(executablePath: String, message: String)
    case timedOut(executablePath: String, timeout: Duration, standardOutput: String, standardError: String)
    case cancelled(executablePath: String, standardOutput: String, standardError: String)
    case compilationTimedOut(OpenVAFCompilationFailure, timeout: Duration)
    case compilationCancelled(OpenVAFCompilationFailure)
    case compilationLaunchFailed(OpenVAFCompilationFailure)
    case compilationFailed(OpenVAFCompilationFailure)
    case outputMissing(OpenVAFCompilationFailure)
}

extension OpenVAFError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let field, let message):
            return "Invalid OpenVAF configuration for \(field): \(message)"
        case .executableNotFound(let name, let searchedPaths):
            return "OpenVAF executable '\(name)' was not found on PATH: \(searchedPaths.joined(separator: ":"))"
        case .invalidExecutableName(let name, let message):
            return "Invalid OpenVAF executable name '\(name)': \(message)"
        case .notExecutable(let path):
            return "OpenVAF is not executable at \(path)"
        case .invalidOutputFileName(let fileName, let message):
            return "Invalid OpenVAF output file name '\(fileName)': \(message)"
        case .fileSystemFailure(let operation, let path, let message):
            return "OpenVAF file operation failed: \(operation) at \(path): \(message)"
        case .launchFailed(let executablePath, let message):
            return "OpenVAF failed to launch at \(executablePath): \(message)"
        case .timedOut(let executablePath, let timeout, _, _):
            return "OpenVAF timed out after \(timeout) at \(executablePath)"
        case .cancelled(let executablePath, _, _):
            return "OpenVAF was cancelled at \(executablePath)"
        case .compilationTimedOut(let failure, let timeout):
            return "OpenVAF compilation timed out after \(timeout): \(failure.diagnostics.first?.summary ?? "No diagnostic")"
        case .compilationCancelled(let failure):
            return "OpenVAF compilation was cancelled: \(failure.diagnostics.first?.summary ?? "No diagnostic")"
        case .compilationLaunchFailed(let failure):
            return "OpenVAF compilation could not launch: \(failure.diagnostics.first?.summary ?? "No diagnostic")"
        case .compilationFailed(let failure):
            return "OpenVAF failed with exit code \(failure.exitCode ?? -1): \(failure.diagnostics.first?.summary ?? "No diagnostic")"
        case .outputMissing(let failure):
            return "OpenVAF did not produce the expected output: \(failure.diagnostics.first?.summary ?? "No diagnostic")"
        }
    }
}
