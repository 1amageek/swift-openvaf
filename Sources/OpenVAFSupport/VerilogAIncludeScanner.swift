import Foundation

package struct VerilogAIncludeScanner: Sendable {
    private var lineBytes: [UInt8] = []
    private var isInBlockComment = false
    private var paths: [String] = []

    package init() {}

    package static func includePaths(in sourceURL: URL) throws(OpenVAFError) -> [String] {
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
        guard !lineBytes.isEmpty else { return }
        let line = String(decoding: lineBytes, as: UTF8.self)
        lineBytes.removeAll(keepingCapacity: true)

        let uncommented = Self.removingComments(from: line, isInBlockComment: &isInBlockComment)
        if let path = Self.includePath(from: uncommented) {
            paths.append(path)
        }
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

    private static func includePath(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let directive = "`include"
        guard trimmed.hasPrefix(directive) else { return nil }

        let directiveEnd = trimmed.index(trimmed.startIndex, offsetBy: directive.count)
        guard directiveEnd == trimmed.endIndex || trimmed[directiveEnd].isWhitespace else {
            return nil
        }

        let remainder = trimmed[directiveEnd...].trimmingCharacters(in: .whitespaces)
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
}
