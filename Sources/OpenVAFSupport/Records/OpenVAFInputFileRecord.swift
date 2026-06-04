import Foundation

/// Role of a staged input file used by an OpenVAF compilation.
public enum OpenVAFInputFileRole: Sendable, Equatable {
    case primarySource
    case include
}

/// Fingerprint of a file snapshot that participated in an OpenVAF compilation.
public struct OpenVAFInputFileRecord: Sendable, Equatable {
    public let role: OpenVAFInputFileRole
    public let logicalPath: String
    public let sourceURL: URL
    public let stagedRelativePath: String
    public let stagedURL: URL
    public let sha256: String

    public init(
        role: OpenVAFInputFileRole,
        logicalPath: String,
        sourceURL: URL,
        stagedRelativePath: String,
        stagedURL: URL,
        sha256: String
    ) {
        self.role = role
        self.logicalPath = logicalPath
        self.sourceURL = sourceURL
        self.stagedRelativePath = stagedRelativePath
        self.stagedURL = stagedURL
        self.sha256 = sha256
    }
}
