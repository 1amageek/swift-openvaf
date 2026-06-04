import Foundation

/// Redacted environment metadata for reproducing an OpenVAF invocation.
public struct OpenVAFEnvironmentRecord: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        case inherited
        case explicit
    }

    public let source: Source
    public let keys: [String]
    public let valueSHA256: String

    public init(
        source: Source,
        keys: [String],
        valueSHA256: String
    ) {
        self.source = source
        self.keys = keys.sorted()
        self.valueSHA256 = valueSHA256
    }
}
