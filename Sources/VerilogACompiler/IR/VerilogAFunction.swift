import Foundation

#if VerilogACompiler

/// Parsed Verilog-A analog function with source ranges into the original buffer.
public struct VerilogAFunction: Sendable, Equatable {
    public let returnTypeRange: VerilogASourceRange?
    public let nameRange: VerilogASourceRange
    public let declarations: [VerilogADeclaration]
    public let sourceRange: VerilogASourceRange

    public init(
        returnTypeRange: VerilogASourceRange?,
        nameRange: VerilogASourceRange,
        declarations: [VerilogADeclaration],
        sourceRange: VerilogASourceRange
    ) {
        self.returnTypeRange = returnTypeRange
        self.nameRange = nameRange
        self.declarations = declarations
        self.sourceRange = sourceRange
    }

    public func name(in buffer: VerilogASourceBuffer) -> String {
        buffer.string(in: nameRange)
    }
}

#endif
