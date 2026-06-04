import Foundation

#if VerilogACompiler

/// Diagnostic produced by the Verilog-A compiler frontend.
public struct VerilogADiagnostic: Sendable, Equatable {
    public enum Severity: Sendable, Equatable {
        case error
        case warning
    }

    public let severity: Severity
    public let message: String
    public let range: VerilogASourceRange

    public init(
        severity: Severity,
        message: String,
        range: VerilogASourceRange
    ) {
        self.severity = severity
        self.message = message
        self.range = range
    }
}

#endif
