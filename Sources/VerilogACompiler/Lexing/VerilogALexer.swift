import Foundation

#if VerilogACompiler

/// Streaming lexer for Verilog-A source bytes.
public struct VerilogALexer: Sendable {
    private let buffer: VerilogASourceBuffer
    private var offset = 0
    private var diagnostics: [VerilogADiagnostic] = []

    public init(buffer: VerilogASourceBuffer) {
        self.buffer = buffer
    }

    public mutating func lexAll() -> (tokens: [VerilogAToken], diagnostics: [VerilogADiagnostic]) {
        var tokens: [VerilogAToken] = []
        skipUTF8ByteOrderMarkAtStartOfFile()

        while let byte = currentByte {
            if isWhitespace(byte) {
                advance()
                continue
            }

            if byte == asciiSlash, peekByte() == asciiSlash {
                skipLineComment()
                continue
            }

            if byte == asciiSlash, peekByte() == asciiAsterisk {
                skipBlockComment()
                continue
            }

            if isIdentifierStart(byte) {
                tokens.append(lexIdentifier())
                continue
            }

            if byte == asciiBackslash {
                tokens.append(lexEscapedIdentifier())
                continue
            }

            if isDigit(byte) || (byte == asciiDot && peekByte().map(isDigit) == true) {
                tokens.append(lexNumber())
                continue
            }

            if byte == asciiDoubleQuote {
                tokens.append(lexStringLiteral())
                continue
            }

            tokens.append(lexSymbolOrUnknown())
        }

        tokens.append(VerilogAToken(
            kind: .endOfFile,
            range: VerilogASourceRange(lowerBound: buffer.count, upperBound: buffer.count)
        ))
        return (tokens, diagnostics)
    }

    private mutating func skipUTF8ByteOrderMarkAtStartOfFile() {
        if offset == 0,
           currentByte == utf8ByteOrderMark0,
           peekByte() == utf8ByteOrderMark1,
           buffer.byte(at: offset + 2) == utf8ByteOrderMark2 {
            offset += 3
        }
    }

    private var currentByte: UInt8? {
        buffer.byte(at: offset)
    }

    private mutating func advance() {
        offset += 1
    }

    private func peekByte() -> UInt8? {
        buffer.byte(at: offset + 1)
    }

    private mutating func skipLineComment() {
        while let byte = currentByte {
            advance()
            if byte == asciiLineFeed || byte == asciiCarriageReturn {
                break
            }
        }
    }

    private mutating func skipBlockComment() {
        let start = offset
        offset += 2
        while let byte = currentByte {
            if byte == asciiAsterisk, peekByte() == asciiSlash {
                offset += 2
                return
            }
            advance()
        }
        diagnostics.append(VerilogADiagnostic(
            severity: .error,
            message: "Unterminated block comment",
            range: VerilogASourceRange(lowerBound: start, upperBound: buffer.count)
        ))
    }

    private mutating func lexIdentifier() -> VerilogAToken {
        let start = offset
        while let byte = currentByte, isIdentifierPart(byte) {
            advance()
        }

        let range = VerilogASourceRange(lowerBound: start, upperBound: offset)
        if let keyword = VerilogAKeyword.match(in: buffer, range: range) {
            return VerilogAToken(kind: .keyword(keyword), range: range)
        }
        return VerilogAToken(kind: .identifier, range: range)
    }

    private mutating func lexEscapedIdentifier() -> VerilogAToken {
        let start = offset
        advance()
        while let byte = currentByte, !isWhitespace(byte) {
            advance()
        }
        return VerilogAToken(
            kind: .identifier,
            range: VerilogASourceRange(lowerBound: start, upperBound: offset)
        )
    }

    private mutating func lexNumber() -> VerilogAToken {
        let start = offset
        var didConsumeExponentMarker = false
        while let byte = currentByte {
            if isDigit(byte) || byte == asciiDot || byte == asciiUnderscore {
                advance()
            } else if (byte == asciiLowerE || byte == asciiUpperE), !didConsumeExponentMarker {
                didConsumeExponentMarker = true
                advance()
                if currentByte == asciiPlus || currentByte == asciiMinus {
                    advance()
                }
            } else {
                break
            }
        }
        return VerilogAToken(
            kind: .number,
            range: VerilogASourceRange(lowerBound: start, upperBound: offset)
        )
    }

    private mutating func lexStringLiteral() -> VerilogAToken {
        let start = offset
        advance()
        var isEscaped = false

        while let byte = currentByte {
            advance()
            if isEscaped {
                isEscaped = false
            } else if byte == asciiBackslash {
                isEscaped = true
            } else if byte == asciiDoubleQuote {
                return VerilogAToken(
                    kind: .stringLiteral,
                    range: VerilogASourceRange(lowerBound: start, upperBound: offset)
                )
            } else if byte == asciiLineFeed || byte == asciiCarriageReturn {
                diagnostics.append(VerilogADiagnostic(
                    severity: .error,
                    message: "Unterminated string literal",
                    range: VerilogASourceRange(lowerBound: start, upperBound: offset)
                ))
                return VerilogAToken(
                    kind: .stringLiteral,
                    range: VerilogASourceRange(lowerBound: start, upperBound: offset)
                )
            }
        }

        diagnostics.append(VerilogADiagnostic(
            severity: .error,
            message: "Unterminated string literal",
            range: VerilogASourceRange(lowerBound: start, upperBound: buffer.count)
        ))
        return VerilogAToken(
            kind: .stringLiteral,
            range: VerilogASourceRange(lowerBound: start, upperBound: buffer.count)
        )
    }

    private mutating func lexSymbolOrUnknown() -> VerilogAToken {
        let start = offset
        let byte = currentByte ?? 0
        advance()
        let range = VerilogASourceRange(lowerBound: start, upperBound: offset)
        if let symbol = VerilogASymbol(rawValue: byte) {
            return VerilogAToken(kind: .symbol(symbol), range: range)
        }
        return VerilogAToken(kind: .unknown(byte), range: range)
    }

    private func isWhitespace(_ byte: UInt8) -> Bool {
        byte == asciiSpace
            || byte == asciiTab
            || byte == asciiLineFeed
            || byte == asciiCarriageReturn
    }

    private func isIdentifierStart(_ byte: UInt8) -> Bool {
        isASCIIAlpha(byte) || byte == asciiUnderscore || byte == asciiDollar
    }

    private func isIdentifierPart(_ byte: UInt8) -> Bool {
        isIdentifierStart(byte) || isDigit(byte)
    }

    private func isASCIIAlpha(_ byte: UInt8) -> Bool {
        (byte >= asciiUpperA && byte <= asciiUpperZ)
            || (byte >= asciiLowerA && byte <= asciiLowerZ)
    }

    private func isDigit(_ byte: UInt8) -> Bool {
        byte >= asciiZero && byte <= asciiNine
    }
}

private let asciiTab: UInt8 = 9
private let asciiLineFeed: UInt8 = 10
private let asciiCarriageReturn: UInt8 = 13
private let asciiSpace: UInt8 = 32
private let asciiDoubleQuote: UInt8 = 34
private let asciiDollar: UInt8 = 36
private let asciiAsterisk: UInt8 = 42
private let asciiPlus: UInt8 = 43
private let asciiMinus: UInt8 = 45
private let asciiDot: UInt8 = 46
private let asciiSlash: UInt8 = 47
private let asciiZero: UInt8 = 48
private let asciiNine: UInt8 = 57
private let asciiUpperA: UInt8 = 65
private let asciiUpperE: UInt8 = 69
private let asciiUpperZ: UInt8 = 90
private let asciiBackslash: UInt8 = 92
private let asciiUnderscore: UInt8 = 95
private let asciiLowerA: UInt8 = 97
private let asciiLowerE: UInt8 = 101
private let asciiLowerZ: UInt8 = 122
private let utf8ByteOrderMark0: UInt8 = 0xEF
private let utf8ByteOrderMark1: UInt8 = 0xBB
private let utf8ByteOrderMark2: UInt8 = 0xBF

#endif
