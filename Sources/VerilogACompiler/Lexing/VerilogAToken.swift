import Foundation

#if VerilogACompiler

/// Verilog-A token carrying only a source byte range.
public struct VerilogAToken: Sendable, Equatable {
    public let kind: VerilogATokenKind
    public let range: VerilogASourceRange

    public init(kind: VerilogATokenKind, range: VerilogASourceRange) {
        self.kind = kind
        self.range = range
    }
}

#endif
