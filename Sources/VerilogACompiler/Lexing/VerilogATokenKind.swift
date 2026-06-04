import Foundation

#if VerilogACompiler

/// Token kind emitted by the package Verilog-A lexer.
public enum VerilogATokenKind: Sendable, Equatable {
    case identifier
    case number
    case stringLiteral
    case keyword(VerilogAKeyword)
    case symbol(VerilogASymbol)
    case unknown(UInt8)
    case endOfFile
}

#endif
