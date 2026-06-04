import Foundation

#if VerilogACompiler

/// Recursive-descent parser for the Verilog-A compiler frontend.
public struct VerilogAParser: Sendable {
    private let buffer: VerilogASourceBuffer
    private let tokens: [VerilogAToken]
    private var index = 0
    private var diagnostics: [VerilogADiagnostic]

    public init(buffer: VerilogASourceBuffer) {
        var lexer = VerilogALexer(buffer: buffer)
        let lexed = lexer.lexAll()
        var preprocessor = VerilogAPreprocessor(buffer: buffer, tokens: lexed.tokens)
        let preprocessed = preprocessor.process()
        self.buffer = buffer
        self.tokens = preprocessed.tokens
        self.diagnostics = lexed.diagnostics + preprocessed.diagnostics
    }

    public mutating func parse() -> VerilogAParseResult {
        var modules: [VerilogAModule] = []

        while !isAtEnd {
            if isLineStartMacroInvocation {
                skipLineStartMacroInvocation()
                continue
            }

            skipAttributes()
            if isAtEnd {
                break
            }

            if current.kind == .keyword(.module) {
                if let module = parseModule() {
                    modules.append(module)
                }
            } else {
                advance()
            }
        }

        return VerilogAParseResult(
            source: buffer,
            modules: modules,
            diagnostics: diagnostics
        )
    }

    private mutating func parseModule() -> VerilogAModule? {
        let moduleToken = current
        advance()

        guard current.kind == .identifier else {
            diagnostics.append(VerilogADiagnostic(
                severity: .error,
                message: "Expected module name",
                range: current.range
            ))
            skipToNextModuleBoundary()
            return nil
        }

        let nameRange = current.range
        advance()
        let moduleHeader = parseOptionalPortList()
        skipAttributes()
        consumeSemicolon(message: "Expected ';' after module header")

        var declarations = moduleHeader.inlineDeclarations
        var parameters: [VerilogAParameter] = []
        var functions: [VerilogAFunction] = []
        var analogBlockRanges: [VerilogASourceRange] = []

        while !isAtEnd,
              current.kind != .keyword(.endmodule),
              current.kind != .keyword(.module) {
            if isLineStartMacroInvocation {
                skipLineStartMacroInvocation()
                continue
            }

            skipAttributes()
            if isAtEnd || current.kind == .keyword(.endmodule) || current.kind == .keyword(.module) {
                break
            }

            if current.kind == .keyword(.parameter) {
                parameters.append(contentsOf: parseParameters())
            } else if let declarationKind = declarationKind(for: current.kind) {
                if let declaration = parseDeclaration(kind: declarationKind) {
                    declarations.append(declaration)
                }
            } else if current.kind == .keyword(.analog) {
                if tokenAfter(index).kind == .keyword(.function) {
                    if let function = parseAnalogFunction() {
                        functions.append(function)
                    }
                } else {
                    analogBlockRanges.append(parseAnalogBlockRange())
                }
            } else {
                advance()
            }
        }

        let endRange: VerilogASourceRange
        if current.kind == .keyword(.endmodule) {
            endRange = current.range
            advance()
        } else {
            endRange = current.kind == .keyword(.module)
                ? current.range
                : VerilogASourceRange(lowerBound: buffer.count, upperBound: buffer.count)
            diagnostics.append(VerilogADiagnostic(
                severity: .error,
                message: "Expected 'endmodule'",
                range: endRange
            ))
        }

        return VerilogAModule(
            nameRange: nameRange,
            portNameRanges: moduleHeader.portNameRanges,
            declarations: declarations,
            parameters: parameters,
            functions: functions,
            analogBlockRanges: analogBlockRanges,
            sourceRange: VerilogASourceRange.joining(moduleToken.range, endRange)
        )
    }

    private mutating func parseOptionalPortList() -> (
        portNameRanges: [VerilogASourceRange],
        inlineDeclarations: [VerilogADeclaration]
    ) {
        guard current.kind == .symbol(.leftParenthesis) else {
            return ([], [])
        }
        advance()

        let declarators = parseCommaSeparatedDeclarators(until: .symbol(.rightParenthesis))

        if current.kind == .symbol(.rightParenthesis) {
            advance()
        } else {
            diagnostics.append(VerilogADiagnostic(
                severity: .error,
                message: "Expected ')' after module port list",
                range: current.range
            ))
        }

        return (
            declarators.compactMap { VerilogADeclaratorNameExtractor.nameRange(in: $0) },
            parseInlinePortDeclarations(from: declarators)
        )
    }

    private mutating func parseParameters() -> [VerilogAParameter] {
        let parameterKeywordRange = current.range
        advance()

        skipAttributes()

        let typeRange: VerilogASourceRange?
        if isTypeKeyword(current.kind) {
            typeRange = current.range
            advance()
        } else {
            typeRange = nil
        }

        skipAttributes()

        let declarators = parseCommaSeparatedDeclarators(until: .symbol(.semicolon))
        let endRange = current.range
        consumeSemicolon(message: "Expected ';' after parameter declaration")

        var didReportMissingParameterName = false
        var parameters: [VerilogAParameter] = []

        for declarator in declarators {
            guard let nameRange = VerilogADeclaratorNameExtractor.nameRange(in: declarator) else {
                if !didReportMissingParameterName {
                    let diagnosticRange = declarator.first?.range ?? endRange
                    diagnostics.append(VerilogADiagnostic(
                        severity: .error,
                        message: "Expected parameter name",
                        range: diagnosticRange
                    ))
                    didReportMissingParameterName = true
                }
                continue
            }

            let valueRange = parameterValueRange(in: declarator)
            if valueRange == nil,
               let equalsRange = parameterInitializerEqualsRange(in: declarator) {
                diagnostics.append(VerilogADiagnostic(
                    severity: .error,
                    message: "Expected parameter default value",
                    range: equalsRange
                ))
            }

            let declaratorStartRange = parameters.isEmpty
                ? parameterKeywordRange
                : declarator.first?.range ?? nameRange
            let declaratorEndRange = declarator.last?.range ?? valueRange ?? nameRange
            parameters.append(VerilogAParameter(
                typeRange: typeRange,
                nameRange: nameRange,
                valueRange: valueRange,
                sourceRange: VerilogASourceRange.joining(declaratorStartRange, declaratorEndRange)
            ))
        }

        if parameters.isEmpty, !didReportMissingParameterName {
            diagnostics.append(VerilogADiagnostic(
                severity: .error,
                message: "Expected parameter name",
                range: endRange
            ))
        }

        return parameters
    }

    private func parameterInitializerEqualsRange(in tokens: [VerilogAToken]) -> VerilogASourceRange? {
        var parenthesisDepth = 0
        var bracketDepth = 0
        var braceDepth = 0

        for token in tokens {
            if parenthesisDepth == 0,
               bracketDepth == 0,
               braceDepth == 0,
               token.kind == .symbol(.equals) {
                return token.range
            }

            updateDelimiterDepth(
                tokenKind: token.kind,
                parenthesisDepth: &parenthesisDepth,
                bracketDepth: &bracketDepth,
                braceDepth: &braceDepth
            )
        }

        return nil
    }

    private func parameterValueRange(in tokens: [VerilogAToken]) -> VerilogASourceRange? {
        var parenthesisDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        var valueStart: Int?
        var valueEnd: Int?
        var isReadingValue = false

        for token in tokens {
            if !isReadingValue {
                if parenthesisDepth == 0,
                   bracketDepth == 0,
                   braceDepth == 0,
                   token.kind == .symbol(.equals) {
                    isReadingValue = true
                    continue
                }

                updateDelimiterDepth(
                    tokenKind: token.kind,
                    parenthesisDepth: &parenthesisDepth,
                    bracketDepth: &bracketDepth,
                    braceDepth: &braceDepth
                )
                continue
            }

            if parenthesisDepth == 0,
               bracketDepth == 0,
               braceDepth == 0,
               isParameterConstraintKeyword(token.kind) {
                break
            }

            updateDelimiterDepth(
                tokenKind: token.kind,
                parenthesisDepth: &parenthesisDepth,
                bracketDepth: &bracketDepth,
                braceDepth: &braceDepth
            )

            if valueStart == nil {
                valueStart = token.range.lowerBound
            }
            valueEnd = token.range.upperBound
        }

        guard let valueStart, let valueEnd else {
            return nil
        }

        return trimmedRange(lowerBound: valueStart, upperBound: valueEnd)
    }

    private func isParameterConstraintKeyword(_ tokenKind: VerilogATokenKind) -> Bool {
        switch tokenKind {
        case .keyword(.from), .keyword(.exclude):
            return true
        default:
            return false
        }
    }

    private func trimmedRange(
        lowerBound: Int,
        upperBound: Int
    ) -> VerilogASourceRange? {
        var lowerBound = lowerBound
        var upperBound = upperBound

        while lowerBound < upperBound,
              let byte = buffer.byte(at: lowerBound),
              isASCIIWhitespace(byte) {
            lowerBound += 1
        }

        while upperBound > lowerBound,
              let byte = buffer.byte(at: upperBound - 1),
              isASCIIWhitespace(byte) {
            upperBound -= 1
        }

        guard lowerBound < upperBound else { return nil }
        return VerilogASourceRange(
            lowerBound: lowerBound,
            upperBound: upperBound
        )
    }

    private mutating func parseDeclaration(kind: VerilogADeclarationKind) -> VerilogADeclaration? {
        let startRange = current.range
        advance()

        let nameRanges = parseCommaSeparatedDeclaratorNames(until: .symbol(.semicolon))

        let endRange = current.range
        consumeSemicolon(message: "Expected ';' after declaration")
        guard !nameRanges.isEmpty else {
            diagnostics.append(VerilogADiagnostic(
                severity: .error,
                message: "Expected declaration name",
                range: endRange
            ))
            return nil
        }

        return VerilogADeclaration(
            kind: kind,
            nameRanges: nameRanges,
            sourceRange: VerilogASourceRange.joining(startRange, endRange)
        )
    }

    private mutating func parseAnalogBlockRange() -> VerilogASourceRange {
        let startRange = current.range
        advance()

        if current.kind == .keyword(.initial) {
            advance()
        }

        if current.kind != .keyword(.beginBlock) {
            if current.kind == .keyword(.caseKeyword) {
                return parseCaseAnalogRange(startRange: startRange)
            }

            return parseAnalogStatementRange(startRange: startRange)
        }

        return parseBeginEndRange(startRange: startRange)
    }

    private mutating func parseAnalogFunction() -> VerilogAFunction? {
        let startRange = current.range
        advance()

        guard current.kind == .keyword(.function) else {
            diagnostics.append(VerilogADiagnostic(
                severity: .error,
                message: "Expected 'function' after 'analog'",
                range: current.range
            ))
            skipToSemicolon()
            return nil
        }
        advance()

        let returnTypeRange: VerilogASourceRange?
        if isTypeKeyword(current.kind) {
            returnTypeRange = current.range
            advance()
        } else {
            returnTypeRange = nil
        }

        guard current.kind == .identifier else {
            diagnostics.append(VerilogADiagnostic(
                severity: .error,
                message: "Expected function name",
                range: current.range
            ))
            skipToSemicolon()
            return nil
        }

        let nameRange = current.range
        advance()
        consumeSemicolon(message: "Expected ';' after function header")

        var declarations: [VerilogADeclaration] = []
        var endRange = current.range

        while !isAtEnd,
              current.kind != .keyword(.endfunction),
              !isModuleRecoveryBoundary(current.kind) {
            if isLineStartMacroInvocation {
                skipLineStartMacroInvocation()
                continue
            }

            skipAttributes()
            if isAtEnd || current.kind == .keyword(.endfunction) || isModuleRecoveryBoundary(current.kind) {
                break
            }

            endRange = current.range
            if let declarationKind = declarationKind(for: current.kind) {
                if let declaration = parseDeclaration(kind: declarationKind) {
                    declarations.append(declaration)
                }
            } else {
                advance()
            }
        }

        if current.kind == .keyword(.endfunction) {
            endRange = current.range
            advance()
        } else {
            diagnostics.append(VerilogADiagnostic(
                severity: .error,
                message: "Expected 'endfunction'",
                range: endRange
            ))
        }

        return VerilogAFunction(
            returnTypeRange: returnTypeRange,
            nameRange: nameRange,
            declarations: declarations,
            sourceRange: VerilogASourceRange.joining(startRange, endRange)
        )
    }

    private mutating func parseBeginEndRange(startRange: VerilogASourceRange) -> VerilogASourceRange {
        var depth = 0
        var endRange = current.range
        while !isAtEnd {
            if isLineStartMacroInvocation {
                endRange = current.range
                skipLineStartMacroInvocation()
                continue
            }

            if isModuleRecoveryBoundary(current.kind) {
                diagnostics.append(VerilogADiagnostic(
                    severity: .error,
                    message: "Expected 'end' for analog block",
                    range: current.range
                ))
                return VerilogASourceRange.joining(startRange, endRange)
            }

            if current.kind == .keyword(.beginBlock) {
                depth += 1
                endRange = current.range
                advance()
            } else if current.kind == .keyword(.endBlock) {
                depth -= 1
                endRange = current.range
                advance()
                if depth == 0 {
                    return VerilogASourceRange.joining(startRange, endRange)
                }
            } else {
                endRange = current.range
                advance()
            }
        }

        diagnostics.append(VerilogADiagnostic(
            severity: .error,
            message: "Expected 'end' for analog block",
            range: endRange
        ))
        return VerilogASourceRange.joining(startRange, endRange)
    }

    private mutating func parseAnalogStatementRange(startRange: VerilogASourceRange) -> VerilogASourceRange {
        var parenthesisDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        var beginDepth = 0
        var caseDepth = 0
        var endRange = current.range

        while !isAtEnd {
            if isLineStartMacroInvocation {
                endRange = current.range
                skipLineStartMacroInvocation()
                continue
            }

            if isModuleRecoveryBoundary(current.kind) {
                diagnostics.append(VerilogADiagnostic(
                    severity: .error,
                    message: "Expected complete analog statement",
                    range: current.range
                ))
                return VerilogASourceRange.joining(startRange, endRange)
            }

            if current.kind == .keyword(.beginBlock) {
                beginDepth += 1
                endRange = current.range
                advance()
                continue
            }

            if current.kind == .keyword(.endBlock) {
                if beginDepth > 0 {
                    beginDepth -= 1
                }
                endRange = current.range
                advance()

                if beginDepth == 0,
                   caseDepth == 0,
                   parenthesisDepth == 0,
                   bracketDepth == 0,
                   braceDepth == 0,
                   !isCurrentAnalogElseContinuation {
                    return VerilogASourceRange.joining(startRange, endRange)
                }
                continue
            }

            if current.kind == .keyword(.caseKeyword) {
                caseDepth += 1
                endRange = current.range
                advance()
                continue
            }

            if current.kind == .keyword(.endcase) {
                if caseDepth > 0 {
                    caseDepth -= 1
                }
                endRange = current.range
                advance()

                if beginDepth == 0,
                   caseDepth == 0,
                   parenthesisDepth == 0,
                   bracketDepth == 0,
                   braceDepth == 0,
                   !isCurrentAnalogElseContinuation {
                    return VerilogASourceRange.joining(startRange, endRange)
                }
                continue
            }

            if current.kind == .symbol(.semicolon),
               beginDepth == 0,
               caseDepth == 0,
               parenthesisDepth == 0,
               bracketDepth == 0,
               braceDepth == 0 {
                endRange = current.range
                advance()

                if !isCurrentAnalogElseContinuation {
                    return VerilogASourceRange.joining(startRange, endRange)
                }
                continue
            }

            updateDelimiterDepth(
                tokenKind: current.kind,
                parenthesisDepth: &parenthesisDepth,
                bracketDepth: &bracketDepth,
                braceDepth: &braceDepth
            )
            endRange = current.range
            advance()
        }

        diagnostics.append(VerilogADiagnostic(
            severity: .error,
            message: "Expected complete analog statement",
            range: endRange
        ))
        return VerilogASourceRange.joining(startRange, endRange)
    }

    private var isCurrentAnalogElseContinuation: Bool {
        switch current.kind {
        case .identifier, .keyword:
            return buffer.matchesASCII(parserElseBytes, in: current.range)
        default:
            return false
        }
    }

    private mutating func parseCaseAnalogRange(startRange: VerilogASourceRange) -> VerilogASourceRange {
        var caseDepth = 0
        var beginDepth = 0
        var endRange = current.range

        while !isAtEnd {
            if isLineStartMacroInvocation {
                endRange = current.range
                skipLineStartMacroInvocation()
                continue
            }

            if isModuleRecoveryBoundary(current.kind) {
                diagnostics.append(VerilogADiagnostic(
                    severity: .error,
                    message: "Expected 'endcase' for analog case statement",
                    range: current.range
                ))
                return VerilogASourceRange.joining(startRange, endRange)
            }

            if current.kind == .keyword(.caseKeyword) {
                caseDepth += 1
                endRange = current.range
                advance()
            } else if current.kind == .keyword(.endcase) {
                caseDepth -= 1
                endRange = current.range
                advance()
                if caseDepth == 0 && beginDepth == 0 {
                    return VerilogASourceRange.joining(startRange, endRange)
                }
            } else if current.kind == .keyword(.beginBlock) {
                beginDepth += 1
                endRange = current.range
                advance()
            } else if current.kind == .keyword(.endBlock) {
                beginDepth = max(0, beginDepth - 1)
                endRange = current.range
                advance()
            } else {
                endRange = current.range
                advance()
            }
        }

        diagnostics.append(VerilogADiagnostic(
            severity: .error,
            message: "Expected 'endcase' for analog case statement",
            range: endRange
        ))
        return VerilogASourceRange.joining(startRange, endRange)
    }

    private func declarationKind(for tokenKind: VerilogATokenKind) -> VerilogADeclarationKind? {
        switch tokenKind {
        case .keyword(.inoutKeyword):
            return .inoutPort
        case .keyword(.input):
            return .input
        case .keyword(.output):
            return .output
        case .keyword(.electrical):
            return .electrical
        case .keyword(.ground), .keyword(.gnd):
            return .ground
        case .keyword(.branch):
            return .branch
        case .keyword(.thermal):
            return .thermal
        case .keyword(.real):
            return .real
        case .keyword(.integer), .keyword(.intKeyword):
            return .integer
        case .keyword(.string):
            return .string
        default:
            return nil
        }
    }

    private func isTypeKeyword(_ tokenKind: VerilogATokenKind) -> Bool {
        switch tokenKind {
        case .keyword(.real), .keyword(.integer), .keyword(.intKeyword), .keyword(.string):
            return true
        default:
            return false
        }
    }

    private func isModuleRecoveryBoundary(_ tokenKind: VerilogATokenKind) -> Bool {
        switch tokenKind {
        case .keyword(.endmodule), .keyword(.module):
            return true
        default:
            return false
        }
    }

    private func isASCIIWhitespace(_ byte: UInt8) -> Bool {
        byte == 9 || byte == 10 || byte == 13 || byte == 32
    }

    private var current: VerilogAToken {
        tokens[index]
    }

    private var isAtEnd: Bool {
        current.kind == .endOfFile
    }

    private mutating func advance() {
        if index < tokens.count - 1 {
            index += 1
        }
    }

    private mutating func consumeSemicolon(message: String) {
        if current.kind == .symbol(.semicolon) {
            advance()
        } else {
            diagnostics.append(VerilogADiagnostic(
                severity: .error,
                message: message,
                range: current.range
            ))
        }
    }

    private mutating func skipToSemicolon() {
        while !isAtEnd, current.kind != .symbol(.semicolon) {
            advance()
        }
    }

    private mutating func skipToNextModuleBoundary() {
        while !isAtEnd,
              current.kind != .keyword(.endmodule),
              current.kind != .keyword(.module) {
            advance()
        }
        if current.kind == .keyword(.endmodule) {
            advance()
        }
    }

    private var isLineStartMacroInvocation: Bool {
        current.kind == .symbol(.backtick)
            && isAtTokenLineStart(index)
    }

    private mutating func skipLineStartMacroInvocation() {
        let fallbackEnd = continuedLineEndOffset(startingAt: current.range.lowerBound)
        advance()

        guard isMacroNameToken(current.kind), current.range.lowerBound < fallbackEnd else {
            skipTokens(until: fallbackEnd)
            return
        }

        advance()

        if current.kind == .symbol(.leftParenthesis),
           current.range.lowerBound < fallbackEnd {
            skipBalancedMacroInvocationParentheses()
        }
    }

    private mutating func skipBalancedMacroInvocationParentheses() {
        guard let closingUpperBound = balancedMacroInvocationClosingUpperBound(startingAt: index) else {
            skipTokens(until: continuedLineEndOffset(startingAt: current.range.lowerBound))
            return
        }

        skipTokens(until: closingUpperBound)
        skipTokens(until: physicalLineEndOffset(startingAt: closingUpperBound))
    }

    private func balancedMacroInvocationClosingUpperBound(startingAt startIndex: Int) -> Int? {
        var parenthesisDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        var scanIndex = startIndex

        while scanIndex < tokens.count {
            let token = tokens[scanIndex]
            if token.kind == .endOfFile {
                return nil
            }
            updateDelimiterDepth(
                tokenKind: token.kind,
                parenthesisDepth: &parenthesisDepth,
                bracketDepth: &bracketDepth,
                braceDepth: &braceDepth
            )

            if parenthesisDepth == 0, bracketDepth == 0, braceDepth == 0 {
                return token.range.upperBound
            }

            scanIndex += 1
        }

        return nil
    }

    private mutating func skipTokens(until endOffset: Int) {
        while !isAtEnd, current.range.lowerBound < endOffset {
            advance()
        }
    }

    private func isMacroNameToken(_ tokenKind: VerilogATokenKind) -> Bool {
        switch tokenKind {
        case .identifier, .keyword:
            return true
        default:
            return false
        }
    }

    private func isAtTokenLineStart(_ tokenIndex: Int) -> Bool {
        if tokenIndex == 0 {
            return true
        }

        return containsLineBreak(
            lowerBound: tokens[tokenIndex - 1].range.upperBound,
            upperBound: tokens[tokenIndex].range.lowerBound
        )
    }

    private func containsLineBreak(lowerBound: Int, upperBound: Int) -> Bool {
        guard lowerBound < upperBound else {
            return false
        }

        var currentOffset = lowerBound
        while currentOffset < upperBound {
            guard let byte = buffer.byte(at: currentOffset) else {
                return false
            }

            if byte == parserAsciiLineFeed || byte == parserAsciiCarriageReturn {
                return true
            }
            currentOffset += 1
        }
        return false
    }

    private func continuedLineEndOffset(startingAt start: Int) -> Int {
        var lineStart = start
        while true {
            let physicalEnd = physicalLineEndOffset(startingAt: lineStart)
            if !hasLineContinuation(before: physicalEnd) {
                return physicalEnd
            }

            let nextLineStart = offsetAfterLineBreak(startingAt: physicalEnd)
            if nextLineStart <= lineStart {
                return physicalEnd
            }
            lineStart = nextLineStart
        }
    }

    private func physicalLineEndOffset(startingAt start: Int) -> Int {
        var currentOffset = start
        while let byte = buffer.byte(at: currentOffset) {
            if byte == parserAsciiLineFeed || byte == parserAsciiCarriageReturn {
                return currentOffset
            }
            currentOffset += 1
        }
        return buffer.count
    }

    private func hasLineContinuation(before lineEnd: Int) -> Bool {
        guard let lineBreakByte = buffer.byte(at: lineEnd),
              lineBreakByte == parserAsciiLineFeed || lineBreakByte == parserAsciiCarriageReturn else {
            return false
        }

        var currentOffset = lineEnd - 1
        while currentOffset >= 0 {
            guard let byte = buffer.byte(at: currentOffset) else {
                return false
            }

            if byte == parserAsciiSpace || byte == parserAsciiTab {
                currentOffset -= 1
                continue
            }

            if byte == parserAsciiLineFeed || byte == parserAsciiCarriageReturn {
                return false
            }

            return byte == parserAsciiBackslash
        }
        return false
    }

    private func offsetAfterLineBreak(startingAt lineEnd: Int) -> Int {
        guard let byte = buffer.byte(at: lineEnd) else {
            return lineEnd
        }

        if byte == parserAsciiCarriageReturn,
           buffer.byte(at: lineEnd + 1) == parserAsciiLineFeed {
            return lineEnd + 2
        }
        return lineEnd + 1
    }

    private var isAttributeStart: Bool {
        current.kind == .symbol(.leftParenthesis)
            && tokenAfter(index).kind == .symbol(.asterisk)
    }

    private mutating func skipAttribute() {
        let startRange = current.range
        advance()
        advance()
        while !isAtEnd {
            if current.kind == .symbol(.asterisk),
               tokenAfter(index).kind == .symbol(.rightParenthesis) {
                advance()
                advance()
                return
            }
            advance()
        }
        diagnostics.append(VerilogADiagnostic(
            severity: .error,
            message: "Expected '*)' to close attribute",
            range: VerilogASourceRange.joining(startRange, current.range)
        ))
    }

    private mutating func skipAttributes() {
        while isAttributeStart {
            skipAttribute()
        }
    }

    private mutating func parseCommaSeparatedDeclaratorNames(
        until terminator: VerilogATokenKind
    ) -> [VerilogASourceRange] {
        parseCommaSeparatedDeclarators(until: terminator).compactMap { declarator in
            VerilogADeclaratorNameExtractor.nameRange(in: declarator)
        }
    }

    private mutating func parseCommaSeparatedDeclarators(
        until terminator: VerilogATokenKind
    ) -> [[VerilogAToken]] {
        var declarators: [[VerilogAToken]] = []
        var declaratorTokens: [VerilogAToken] = []
        var parenthesisDepth = 0
        var bracketDepth = 0
        var braceDepth = 0

        while !isAtEnd {
            if current.kind == terminator {
                if parenthesisDepth == 0, bracketDepth == 0, braceDepth == 0 {
                    break
                }
                if shouldRecoverAtUnbalancedTerminator(
                    terminator,
                    parenthesisDepth: parenthesisDepth
                ) {
                    appendUnclosedDeclaratorDelimiterDiagnostic(
                        parenthesisDepth: parenthesisDepth,
                        bracketDepth: bracketDepth,
                        braceDepth: braceDepth,
                        range: current.range
                    )
                    break
                }
            }

            if isDeclaratorRecoveryBoundary(current.kind, terminator: terminator) {
                appendUnclosedDeclaratorDelimiterDiagnostic(
                    parenthesisDepth: parenthesisDepth,
                    bracketDepth: bracketDepth,
                    braceDepth: braceDepth,
                    range: current.range
                )
                break
            }

            if isAttributeStart {
                skipAttributes()
                continue
            }

            if current.kind == .symbol(.comma),
               parenthesisDepth == 0,
               bracketDepth == 0,
               braceDepth == 0 {
                appendDeclarator(from: &declaratorTokens, to: &declarators)
                advance()
                continue
            }

            updateDelimiterDepth(
                tokenKind: current.kind,
                parenthesisDepth: &parenthesisDepth,
                bracketDepth: &bracketDepth,
                braceDepth: &braceDepth
            )
            declaratorTokens.append(current)
            advance()
        }

        appendDeclarator(from: &declaratorTokens, to: &declarators)
        return declarators
    }

    private func shouldRecoverAtUnbalancedTerminator(
        _ terminator: VerilogATokenKind,
        parenthesisDepth: Int
    ) -> Bool {
        switch terminator {
        case .symbol(.semicolon):
            return true
        case .symbol(.rightParenthesis):
            return parenthesisDepth == 0
        default:
            return false
        }
    }

    private mutating func appendUnclosedDeclaratorDelimiterDiagnostic(
        parenthesisDepth: Int,
        bracketDepth: Int,
        braceDepth: Int,
        range: VerilogASourceRange
    ) {
        if parenthesisDepth > 0 || bracketDepth > 0 || braceDepth > 0 {
            diagnostics.append(VerilogADiagnostic(
                severity: .error,
                message: "Expected closing delimiter before declarator terminator",
                range: range
            ))
        }
    }

    private func isDeclaratorRecoveryBoundary(
        _ tokenKind: VerilogATokenKind,
        terminator: VerilogATokenKind
    ) -> Bool {
        if tokenKind == terminator {
            return false
        }

        switch tokenKind {
        case .symbol(.semicolon):
            return terminator != .symbol(.semicolon)
        case .keyword(.endmodule), .keyword(.module), .keyword(.endfunction):
            return true
        default:
            return false
        }
    }

    private func appendDeclarator(
        from declaratorTokens: inout [VerilogAToken],
        to destination: inout [[VerilogAToken]]
    ) {
        if !declaratorTokens.isEmpty {
            destination.append(declaratorTokens)
        }
        declaratorTokens.removeAll(keepingCapacity: true)
    }

    private func parseInlinePortDeclarations(
        from declarators: [[VerilogAToken]]
    ) -> [VerilogADeclaration] {
        var declarations: [VerilogADeclaration] = []
        var currentKind: VerilogADeclarationKind?
        var currentNameRanges: [VerilogASourceRange] = []
        var currentStartRange: VerilogASourceRange?
        var currentEndRange: VerilogASourceRange?

        func flushCurrentDeclaration() {
            guard let declarationKind = currentKind,
                  let startRange = currentStartRange,
                  let endRange = currentEndRange,
                  !currentNameRanges.isEmpty else {
                return
            }

            declarations.append(VerilogADeclaration(
                kind: declarationKind,
                nameRanges: currentNameRanges,
                sourceRange: VerilogASourceRange.joining(startRange, endRange)
            ))
            currentNameRanges.removeAll(keepingCapacity: true)
            currentStartRange = nil
            currentEndRange = nil
        }

        for declarator in declarators {
            if let nextKind = inlinePortDeclarationKind(in: declarator) {
                flushCurrentDeclaration()
                currentKind = nextKind
                currentStartRange = declarator.first?.range
            } else if currentKind != nil,
                      beginsWithNonDirectionalDeclarationKind(in: declarator) {
                flushCurrentDeclaration()
                currentKind = nil
            }

            guard currentKind != nil,
                  let nameRange = VerilogADeclaratorNameExtractor.nameRange(in: declarator) else {
                continue
            }

            if currentStartRange == nil {
                currentStartRange = declarator.first?.range ?? nameRange
            }
            currentNameRanges.append(nameRange)
            currentEndRange = nameRange
        }

        flushCurrentDeclaration()
        return declarations
    }

    private func beginsWithNonDirectionalDeclarationKind(
        in declarator: [VerilogAToken]
    ) -> Bool {
        for token in declarator {
            if token.kind == .identifier {
                return false
            }

            if let declarationKind = declarationKind(for: token.kind),
               !isPortDirectionDeclarationKind(declarationKind) {
                return true
            }
        }
        return false
    }

    private func isPortDirectionDeclarationKind(
        _ declarationKind: VerilogADeclarationKind
    ) -> Bool {
        switch declarationKind {
        case .input, .output, .inoutPort:
            return true
        default:
            return false
        }
    }

    private func inlinePortDeclarationKind(
        in declarator: [VerilogAToken]
    ) -> VerilogADeclarationKind? {
        for token in declarator {
            switch token.kind {
            case .keyword(.input):
                return .input
            case .keyword(.output):
                return .output
            case .keyword(.inoutKeyword):
                return .inoutPort
            default:
                break
            }
        }
        return nil
    }

    private func updateDelimiterDepth(
        tokenKind: VerilogATokenKind,
        parenthesisDepth: inout Int,
        bracketDepth: inout Int,
        braceDepth: inout Int
    ) {
        switch tokenKind {
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
        default:
            break
        }
    }

    private func tokenAfter(_ tokenIndex: Int) -> VerilogAToken {
        let nextIndex = tokenIndex + 1
        if nextIndex < tokens.count {
            return tokens[nextIndex]
        }
        return tokens[tokens.count - 1]
    }
}

private let parserAsciiTab: UInt8 = 9
private let parserAsciiLineFeed: UInt8 = 10
private let parserAsciiCarriageReturn: UInt8 = 13
private let parserAsciiSpace: UInt8 = 32
private let parserAsciiBackslash: UInt8 = 92
private let parserElseBytes: [UInt8] = [101, 108, 115, 101]

#endif
