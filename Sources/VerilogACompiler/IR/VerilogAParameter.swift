import Foundation

#if VerilogACompiler

/// Parsed Verilog-A parameter with source ranges for deferred interpretation.
public struct VerilogAParameter: Sendable, Equatable {
    public let typeRange: VerilogASourceRange?
    public let nameRange: VerilogASourceRange
    public let valueRange: VerilogASourceRange?
    public let sourceRange: VerilogASourceRange

    public init(
        typeRange: VerilogASourceRange?,
        nameRange: VerilogASourceRange,
        valueRange: VerilogASourceRange?,
        sourceRange: VerilogASourceRange
    ) {
        self.typeRange = typeRange
        self.nameRange = nameRange
        self.valueRange = valueRange
        self.sourceRange = sourceRange
    }
}

#endif
