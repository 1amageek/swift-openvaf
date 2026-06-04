import Foundation

#if VerilogACompiler

/// Parsed Verilog-A declaration with names stored as source ranges.
public struct VerilogADeclaration: Sendable, Equatable {
    public let kind: VerilogADeclarationKind
    public let nameRanges: [VerilogASourceRange]
    public let sourceRange: VerilogASourceRange

    public init(
        kind: VerilogADeclarationKind,
        nameRanges: [VerilogASourceRange],
        sourceRange: VerilogASourceRange
    ) {
        self.kind = kind
        self.nameRanges = nameRanges
        self.sourceRange = sourceRange
    }
}

#endif
