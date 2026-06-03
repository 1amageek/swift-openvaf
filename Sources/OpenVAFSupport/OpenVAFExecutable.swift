import Foundation

/// Describes how the OpenVAF executable should be discovered.
public enum OpenVAFExecutable: Sendable, Equatable {
    case environment(variable: String, fallbackName: String)
    case path(String)
    case name(String)
}
