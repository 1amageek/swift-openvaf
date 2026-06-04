import Foundation

package struct VerilogAIncludeScanner: Sendable {
    private var lineBytes: [UInt8] = []
    private var isInBlockComment = false
    private var isAtStartOfFile = true
    private var definedMacros: Set<String> = []
    private var conditionalStack: [IncludeConditionalFrame] = []
    private var paths: [String] = []

    package init() {}

    package static func includePaths(in sourceURL: URL) throws(VerilogAIncludeScannerError) -> [String] {
        guard let stream = InputStream(url: sourceURL) else {
            throw .fileSystemFailure(
                operation: "scan includes",
                path: sourceURL.path,
                message: "Unable to open input stream"
            )
        }
        stream.open()
        defer { stream.close() }

        var scanner = VerilogAIncludeScanner()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let byteCount = buffer.withUnsafeMutableBufferPointer { pointer in
                guard let baseAddress = pointer.baseAddress else { return 0 }
                return stream.read(baseAddress, maxLength: pointer.count)
            }

            if byteCount > 0 {
                for byte in buffer.prefix(byteCount) {
                    scanner.consume(byte)
                }
                continue
            }

            if byteCount == 0 {
                scanner.finish()
                return scanner.paths
            }

            throw .fileSystemFailure(
                operation: "scan includes",
                path: sourceURL.path,
                message: stream.streamError?.localizedDescription ?? "Input stream read failed"
            )
        }
    }

    private mutating func consume(_ byte: UInt8) {
        if byte == 0x0A || byte == 0x0D {
            finishLine()
            return
        }
        lineBytes.append(byte)
    }

    private mutating func finish() {
        finishLine()
    }

    private mutating func finishLine() {
        guard !lineBytes.isEmpty else {
            if isAtStartOfFile {
                isAtStartOfFile = false
            }
            return
        }
        var line = String(decoding: lineBytes, as: UTF8.self)
        lineBytes.removeAll(keepingCapacity: true)
        if isAtStartOfFile {
            line.removeUTF8ByteOrderMark()
            isAtStartOfFile = false
        }

        let uncommented = Self.removingComments(from: line, isInBlockComment: &isInBlockComment)
        handleLine(uncommented)
    }

    private mutating func handleLine(_ line: String) {
        guard let directive = Self.directive(from: line) else { return }

        switch directive.name {
        case "define":
            if isCurrentBranchActive,
               let macroName = Self.directiveArgument(from: directive.remainder) {
                definedMacros.insert(macroName)
            }
        case "undef":
            if isCurrentBranchActive,
               let macroName = Self.directiveArgument(from: directive.remainder) {
                definedMacros.remove(macroName)
            }
        case "ifdef":
            pushConditionalFrame(
                conditionIsActive: Self.directiveArgument(from: directive.remainder).map {
                    definedMacros.contains($0)
                } ?? false
            )
        case "ifndef":
            pushConditionalFrame(
                conditionIsActive: Self.directiveArgument(from: directive.remainder).map {
                    !definedMacros.contains($0)
                } ?? false
            )
        case "elsif":
            applyElsif(
                conditionIsActive: Self.directiveArgument(from: directive.remainder).map {
                    definedMacros.contains($0)
                } ?? false
            )
        case "else":
            applyElse()
        case "endif":
            popConditionalFrame()
        case "include":
            guard isCurrentBranchActive,
                  let path = Self.includePath(from: directive.remainder) else {
                return
            }
            paths.append(path)
        default:
            break
        }
    }

    private var isCurrentBranchActive: Bool {
        conditionalStack.last?.isCurrentBranchActive ?? true
    }

    private mutating func pushConditionalFrame(conditionIsActive: Bool) {
        let parentIsActive = isCurrentBranchActive
        conditionalStack.append(IncludeConditionalFrame(
            parentIsActive: parentIsActive,
            hasMatchedBranch: conditionIsActive,
            hasSeenElse: false,
            isCurrentBranchActive: parentIsActive && conditionIsActive
        ))
    }

    private mutating func applyElsif(conditionIsActive: Bool) {
        guard !conditionalStack.isEmpty else { return }

        var frame = conditionalStack.removeLast()
        if frame.hasSeenElse {
            frame.isCurrentBranchActive = false
            conditionalStack.append(frame)
            return
        }

        let branchShouldActivate = !frame.hasMatchedBranch && conditionIsActive
        frame.isCurrentBranchActive = frame.parentIsActive && branchShouldActivate
        frame.hasMatchedBranch = frame.hasMatchedBranch || conditionIsActive
        conditionalStack.append(frame)
    }

    private mutating func applyElse() {
        guard !conditionalStack.isEmpty else { return }

        var frame = conditionalStack.removeLast()
        if frame.hasSeenElse {
            frame.isCurrentBranchActive = false
            conditionalStack.append(frame)
            return
        }

        frame.hasSeenElse = true
        frame.isCurrentBranchActive = frame.parentIsActive && !frame.hasMatchedBranch
        frame.hasMatchedBranch = true
        conditionalStack.append(frame)
    }

    private mutating func popConditionalFrame() {
        guard !conditionalStack.isEmpty else { return }

        conditionalStack.removeLast()
    }

    private static func removingComments(
        from line: String,
        isInBlockComment: inout Bool
    ) -> String {
        var result = ""
        var index = line.startIndex
        var isInString = false
        var isEscaped = false

        while index < line.endIndex {
            if isInBlockComment {
                if line[index...].hasPrefix("*/") {
                    isInBlockComment = false
                    index = line.index(index, offsetBy: 2)
                } else {
                    index = line.index(after: index)
                }
                continue
            }

            let character = line[index]
            if isInString {
                result.append(character)
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInString = false
                }
                index = line.index(after: index)
                continue
            }

            if character == "\"" {
                isInString = true
                result.append(character)
                index = line.index(after: index)
                continue
            }

            if line[index...].hasPrefix("/*") {
                isInBlockComment = true
                index = line.index(index, offsetBy: 2)
                continue
            }

            if line[index...].hasPrefix("//") {
                break
            }

            result.append(character)
            index = line.index(after: index)
        }

        return result
    }

    private static func directive(from line: String) -> IncludeDirective? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.first == "`" else { return nil }

        var index = trimmed.index(after: trimmed.startIndex)
        let nameStart = index
        while index < trimmed.endIndex,
              isDirectiveNameCharacter(trimmed[index]) {
            index = trimmed.index(after: index)
        }

        guard nameStart < index else { return nil }
        guard index == trimmed.endIndex || trimmed[index].isWhitespace else {
            return nil
        }

        return IncludeDirective(
            name: String(trimmed[nameStart..<index]),
            remainder: trimmed[index...]
        )
    }

    private static func directiveArgument(from remainder: Substring) -> String? {
        let trimmed = remainder.trimmingCharacters(in: .whitespaces)
        var argument = ""

        for character in trimmed {
            if argument.isEmpty {
                guard isMacroNameStartCharacter(character) else { return nil }
            } else if !isMacroNamePartCharacter(character) {
                break
            }
            argument.append(character)
        }

        return argument.isEmpty ? nil : argument
    }

    private static func includePath(from remainder: Substring) -> String? {
        let remainder = remainder.trimmingCharacters(in: .whitespaces)
        guard remainder.first == "\"" else { return nil }

        var path = ""
        var isEscaped = false
        var index = remainder.index(after: remainder.startIndex)
        while index < remainder.endIndex {
            let character = remainder[index]
            if isEscaped {
                path.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                return path.isEmpty ? nil : path
            } else {
                path.append(character)
            }
            index = remainder.index(after: index)
        }

        return nil
    }

    private static func isDirectiveNameCharacter(_ character: Character) -> Bool {
        isASCIILetter(character)
    }

    private static func isMacroNameStartCharacter(_ character: Character) -> Bool {
        isASCIILetter(character) || character == "_" || character == "$"
    }

    private static func isMacroNamePartCharacter(_ character: Character) -> Bool {
        isMacroNameStartCharacter(character) || isASCIIDigit(character)
    }

    private static func isASCIILetter(_ character: Character) -> Bool {
        guard let value = asciiValue(of: character) else { return false }
        return (value >= asciiUpperA && value <= asciiUpperZ)
            || (value >= asciiLowerA && value <= asciiLowerZ)
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        guard let value = asciiValue(of: character) else { return false }
        return value >= asciiZero && value <= asciiNine
    }

    private static func asciiValue(of character: Character) -> UInt8? {
        let scalars = character.unicodeScalars
        guard scalars.count == 1,
              let scalar = scalars.first,
              scalar.value <= UInt8.max else {
            return nil
        }
        return UInt8(scalar.value)
    }
}

private struct IncludeDirective: Sendable {
    let name: String
    let remainder: Substring
}

private struct IncludeConditionalFrame: Sendable {
    let parentIsActive: Bool
    var hasMatchedBranch: Bool
    var hasSeenElse: Bool
    var isCurrentBranchActive: Bool
}

private extension String {
    mutating func removeUTF8ByteOrderMark() {
        guard let first = first, first == "\u{FEFF}" else { return }
        removeFirst()
    }
}

private let asciiZero: UInt8 = 48
private let asciiNine: UInt8 = 57
private let asciiUpperA: UInt8 = 65
private let asciiUpperZ: UInt8 = 90
private let asciiLowerA: UInt8 = 97
private let asciiLowerZ: UInt8 = 122
