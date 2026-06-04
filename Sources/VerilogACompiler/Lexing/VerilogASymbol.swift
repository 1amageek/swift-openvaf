import Foundation

#if VerilogACompiler

/// Single-byte symbols recognized by the Verilog-A compiler frontend.
public enum VerilogASymbol: UInt8, Sendable, Equatable {
    case leftParenthesis = 40
    case rightParenthesis = 41
    case comma = 44
    case semicolon = 59
    case equals = 61
    case leftBracket = 91
    case rightBracket = 93
    case leftBrace = 123
    case rightBrace = 125
    case plus = 43
    case minus = 45
    case slash = 47
    case asterisk = 42
    case dot = 46
    case colon = 58
    case lessThan = 60
    case greaterThan = 62
    case backtick = 96
}

#endif
