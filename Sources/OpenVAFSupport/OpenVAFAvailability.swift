import Foundation

/// Availability result for the configured OpenVAF executable.
public enum OpenVAFAvailability: Sendable, Equatable {
    case available(OpenVAFInstallation)
    case unavailable(OpenVAFUnavailableReason)

    public var isAvailable: Bool {
        switch self {
        case .available:
            return true
        case .unavailable:
            return false
        }
    }
}

/// Resolved OpenVAF installation metadata.
public struct OpenVAFInstallation: Sendable, Equatable {
    public let executableURL: URL
    public let version: String?
    public let rawVersionOutput: String

    public init(
        executableURL: URL,
        version: String?,
        rawVersionOutput: String
    ) {
        self.executableURL = executableURL
        self.version = version
        self.rawVersionOutput = rawVersionOutput
    }
}

/// Structured reason why OpenVAF cannot currently be used.
public enum OpenVAFUnavailableReason: Sendable, Equatable {
    case executableNotFound(name: String, searchedPaths: [String])
    case notExecutable(path: String)
    case versionCheckFailed(exitCode: Int32, standardOutput: String, standardError: String)
    case launchFailed(executablePath: String, message: String)
    case timedOut(executablePath: String, timeout: Duration, standardOutput: String, standardError: String)
    case cancelled(executablePath: String, standardOutput: String, standardError: String)
}
