import Foundation

#if VerilogACompiler

/// Extracts declaration names from one comma-separated Verilog-A declarator.
package enum VerilogADeclaratorNameExtractor {
    package static func nameRange(in tokens: [VerilogAToken]) -> VerilogASourceRange? {
        var candidate: VerilogASourceRange?
        var parenthesisDepth = 0
        var bracketDepth = 0
        var braceDepth = 0

        for token in tokens {
            switch token.kind {
            case .symbol(.equals) where parenthesisDepth == 0 && bracketDepth == 0 && braceDepth == 0:
                return candidate
            case .symbol(.leftParenthesis):
                parenthesisDepth += 1
            case .symbol(.rightParenthesis):
                parenthesisDepth = max(0, parenthesisDepth - 1)
            case .symbol(.leftBracket):
                bracketDepth += 1
            case .symbol(.rightBracket):
                bracketDepth = max(0, bracketDepth - 1)
            case .symbol(.leftBrace):
                braceDepth += 1
            case .symbol(.rightBrace):
                braceDepth = max(0, braceDepth - 1)
            case .identifier where parenthesisDepth == 0 && bracketDepth == 0 && braceDepth == 0:
                candidate = token.range
            default:
                break
            }
        }

        return candidate
    }
}

#endif
