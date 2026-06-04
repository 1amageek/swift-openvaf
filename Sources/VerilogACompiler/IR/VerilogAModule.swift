import Foundation

#if VerilogACompiler

/// Parsed Verilog-A module IR with source ranges into the original buffer.
public struct VerilogAModule: Sendable, Equatable {
    public let nameRange: VerilogASourceRange
    public let portNameRanges: [VerilogASourceRange]
    public let declarations: [VerilogADeclaration]
    public let parameters: [VerilogAParameter]
    public let functions: [VerilogAFunction]
    public let analogBlockRanges: [VerilogASourceRange]
    public let sourceRange: VerilogASourceRange

    public init(
        nameRange: VerilogASourceRange,
        portNameRanges: [VerilogASourceRange],
        declarations: [VerilogADeclaration],
        parameters: [VerilogAParameter],
        functions: [VerilogAFunction],
        analogBlockRanges: [VerilogASourceRange],
        sourceRange: VerilogASourceRange
    ) {
        self.nameRange = nameRange
        self.portNameRanges = portNameRanges
        self.declarations = declarations
        self.parameters = parameters
        self.functions = functions
        self.analogBlockRanges = analogBlockRanges
        self.sourceRange = sourceRange
    }

    public func name(in buffer: VerilogASourceBuffer) -> String {
        buffer.string(in: nameRange)
    }

    public func portNames(in buffer: VerilogASourceBuffer) -> [String] {
        portNameRanges.map { buffer.string(in: $0) }
    }
}

#endif
