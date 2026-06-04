import Foundation

#if VerilogACompiler

/// Minimal Verilog-A preprocessor pass that filters conditional source tokens.
package struct VerilogAPreprocessor: Sendable {
    private let buffer: VerilogASourceBuffer
    private let tokens: [VerilogAToken]
    private var index = 0
    private var definedMacros: Set<String> = []
    private var conditionalStack: [ConditionalFrame] = []
    private var diagnostics: [VerilogADiagnostic] = []

    package init(buffer: VerilogASourceBuffer, tokens: [VerilogAToken]) {
        self.buffer = buffer
        self.tokens = tokens
    }

    package mutating func process() -> (tokens: [VerilogAToken], diagnostics: [VerilogADiagnostic]) {
        var filteredTokens: [VerilogAToken] = []

        while index < tokens.count {
            let token = tokens[index]
            if token.kind == .endOfFile {
                filteredTokens.append(token)
                break
            }

            if isLineDirectiveStart(at: index) {
                handleLineDirective()
                continue
            }

            if isCurrentBranchActive {
                filteredTokens.append(token)
            }
            index += 1
        }

        appendUnclosedConditionalDiagnostics()

        if filteredTokens.last?.kind != .endOfFile,
           let eofToken = tokens.last,
           eofToken.kind == .endOfFile {
            filteredTokens.append(eofToken)
        }

        return (filteredTokens, diagnostics)
    }

    private var isCurrentBranchActive: Bool {
        conditionalStack.last?.isCurrentBranchActive ?? true
    }

    private mutating func handleLineDirective() {
        let directiveStartIndex = index
        let lineEnd = lineEndOffset(startingAt: tokens[directiveStartIndex].range.lowerBound)
        let directiveNameIndex = directiveStartIndex + 1

        guard directiveNameIndex < tokens.count,
              tokens[directiveNameIndex].range.lowerBound < lineEnd else {
            skipTokensThroughLine(endingAt: lineEnd)
            return
        }

        let directiveName = buffer.string(in: tokens[directiveNameIndex].range)
        switch directiveName {
        case "define":
            if isCurrentBranchActive,
               let macroName = directiveArgument(after: directiveNameIndex, before: lineEnd) {
                definedMacros.insert(macroName)
            }
        case "undef":
            if isCurrentBranchActive,
               let macroName = directiveArgument(after: directiveNameIndex, before: lineEnd) {
                definedMacros.remove(macroName)
            }
        case "ifdef":
            pushConditionalFrame(
                directiveRange: tokens[directiveNameIndex].range,
                conditionIsActive: directiveArgument(after: directiveNameIndex, before: lineEnd).map {
                    definedMacros.contains($0)
                } ?? false
            )
        case "ifndef":
            pushConditionalFrame(
                directiveRange: tokens[directiveNameIndex].range,
                conditionIsActive: directiveArgument(after: directiveNameIndex, before: lineEnd).map {
                    !definedMacros.contains($0)
                } ?? false
            )
        case "elsif":
            applyElsif(
                directiveRange: tokens[directiveNameIndex].range,
                conditionIsActive: directiveArgument(after: directiveNameIndex, before: lineEnd).map {
                    definedMacros.contains($0)
                } ?? false
            )
        case "else":
            applyElse(directiveRange: tokens[directiveNameIndex].range)
        case "endif":
            popConditionalFrame(directiveRange: tokens[directiveNameIndex].range)
        case "include":
            break
        default:
            break
        }

        skipTokensThroughLine(endingAt: lineEnd)
    }

    private mutating func pushConditionalFrame(
        directiveRange: VerilogASourceRange,
        conditionIsActive: Bool
    ) {
        let parentIsActive = isCurrentBranchActive
        conditionalStack.append(ConditionalFrame(
            directiveRange: directiveRange,
            parentIsActive: parentIsActive,
            hasMatchedBranch: conditionIsActive,
            hasSeenElse: false,
            isCurrentBranchActive: parentIsActive && conditionIsActive
        ))
    }

    private mutating func applyElsif(
        directiveRange: VerilogASourceRange,
        conditionIsActive: Bool
    ) {
        guard !conditionalStack.isEmpty else {
            appendUnmatchedConditionalDiagnostic(name: "elsif", range: directiveRange)
            return
        }

        var frame = conditionalStack.removeLast()
        if frame.hasSeenElse {
            diagnostics.append(VerilogADiagnostic(
                severity: .error,
                message: "Expected '`endif' before '`elsif' after '`else'",
                range: directiveRange
            ))
            frame.isCurrentBranchActive = false
            conditionalStack.append(frame)
            return
        }

        let branchShouldActivate = !frame.hasMatchedBranch && conditionIsActive
        frame.isCurrentBranchActive = frame.parentIsActive && branchShouldActivate
        frame.hasMatchedBranch = frame.hasMatchedBranch || conditionIsActive
        conditionalStack.append(frame)
    }

    private mutating func applyElse(directiveRange: VerilogASourceRange) {
        guard !conditionalStack.isEmpty else {
            appendUnmatchedConditionalDiagnostic(name: "else", range: directiveRange)
            return
        }

        var frame = conditionalStack.removeLast()
        if frame.hasSeenElse {
            diagnostics.append(VerilogADiagnostic(
                severity: .error,
                message: "Expected '`endif' before duplicate '`else'",
                range: directiveRange
            ))
            frame.isCurrentBranchActive = false
            conditionalStack.append(frame)
            return
        }

        frame.hasSeenElse = true
        frame.isCurrentBranchActive = frame.parentIsActive && !frame.hasMatchedBranch
        frame.hasMatchedBranch = true
        conditionalStack.append(frame)
    }

    private mutating func popConditionalFrame(directiveRange: VerilogASourceRange) {
        guard !conditionalStack.isEmpty else {
            appendUnmatchedConditionalDiagnostic(name: "endif", range: directiveRange)
            return
        }

        conditionalStack.removeLast()
    }

    private mutating func appendUnmatchedConditionalDiagnostic(
        name: String,
        range: VerilogASourceRange
    ) {
        diagnostics.append(VerilogADiagnostic(
            severity: .error,
            message: "Unexpected '`\(name)' without matching conditional directive",
            range: range
        ))
    }

    private mutating func appendUnclosedConditionalDiagnostics() {
        for frame in conditionalStack {
            diagnostics.append(VerilogADiagnostic(
                severity: .error,
                message: "Expected '`endif' for preprocessor conditional",
                range: frame.directiveRange
            ))
        }
    }

    private func directiveArgument(
        after directiveNameIndex: Int,
        before lineEnd: Int
    ) -> String? {
        let argumentIndex = directiveNameIndex + 1
        guard argumentIndex < tokens.count,
              tokens[argumentIndex].range.lowerBound < lineEnd else {
            return nil
        }

        switch tokens[argumentIndex].kind {
        case .identifier, .keyword:
            return buffer.string(in: tokens[argumentIndex].range)
        default:
            return nil
        }
    }

    private mutating func skipTokensThroughLine(endingAt lineEnd: Int) {
        while index < tokens.count,
              tokens[index].kind != .endOfFile,
              tokens[index].range.lowerBound < lineEnd {
            index += 1
        }
    }

    private func isLineDirectiveStart(at tokenIndex: Int) -> Bool {
        guard tokenIndex + 1 < tokens.count,
              tokens[tokenIndex].kind == .symbol(.backtick),
              isAtTokenLineStart(tokenIndex) else {
            return false
        }

        switch tokens[tokenIndex + 1].kind {
        case .identifier, .keyword:
            return isKnownDirectiveName(buffer.string(in: tokens[tokenIndex + 1].range))
        default:
            return false
        }
    }

    private func isKnownDirectiveName(_ name: String) -> Bool {
        switch name {
        case "define",
             "undef",
             "ifdef",
             "ifndef",
             "elsif",
             "else",
             "endif",
             "include":
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

            if byte == asciiLineFeed || byte == asciiCarriageReturn {
                return true
            }
            currentOffset += 1
        }
        return false
    }

    private func lineEndOffset(startingAt start: Int) -> Int {
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
            if byte == asciiLineFeed || byte == asciiCarriageReturn {
                return currentOffset
            }
            currentOffset += 1
        }
        return buffer.count
    }

    private func hasLineContinuation(before lineEnd: Int) -> Bool {
        guard let lineBreakByte = buffer.byte(at: lineEnd),
              lineBreakByte == asciiLineFeed || lineBreakByte == asciiCarriageReturn else {
            return false
        }

        var currentOffset = lineEnd - 1
        while currentOffset >= 0 {
            guard let byte = buffer.byte(at: currentOffset) else {
                return false
            }

            if byte == asciiSpace || byte == asciiTab {
                currentOffset -= 1
                continue
            }

            if byte == asciiLineFeed || byte == asciiCarriageReturn {
                return false
            }

            return byte == asciiBackslash
        }
        return false
    }

    private func offsetAfterLineBreak(startingAt lineEnd: Int) -> Int {
        guard let byte = buffer.byte(at: lineEnd) else {
            return lineEnd
        }

        if byte == asciiCarriageReturn,
           buffer.byte(at: lineEnd + 1) == asciiLineFeed {
            return lineEnd + 2
        }
        return lineEnd + 1
    }
}

private struct ConditionalFrame: Sendable {
    let directiveRange: VerilogASourceRange
    let parentIsActive: Bool
    var hasMatchedBranch: Bool
    var hasSeenElse: Bool
    var isCurrentBranchActive: Bool
}

private let asciiTab: UInt8 = 9
private let asciiLineFeed: UInt8 = 10
private let asciiCarriageReturn: UInt8 = 13
private let asciiSpace: UInt8 = 32
private let asciiBackslash: UInt8 = 92

#endif
