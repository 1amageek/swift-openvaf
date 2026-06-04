import Foundation

/// Identifies the implementation family behind a Verilog-A compiler capability.
public enum VerilogACompilerImplementation: Sendable, Equatable {
    case inProcess
    case openVAF
}
