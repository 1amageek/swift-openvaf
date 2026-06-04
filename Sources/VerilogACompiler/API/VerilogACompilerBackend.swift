import Foundation

/// Common marker for Verilog-A compiler capabilities.
public protocol VerilogACompilerBackend: Sendable {
    var implementation: VerilogACompilerImplementation { get }
}
