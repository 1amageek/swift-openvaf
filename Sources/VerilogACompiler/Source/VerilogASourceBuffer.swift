import Foundation

#if VerilogACompiler

/// Immutable Verilog-A source bytes shared by lexer, parser, and IR ranges.
public struct VerilogASourceBuffer: Sendable, Equatable {
    public let data: Data
    public let sourceURL: URL?

    public init(data: Data, sourceURL: URL? = nil) {
        self.data = data
        self.sourceURL = sourceURL
    }

    public init(string: String, sourceURL: URL? = nil) {
        self.init(data: Data(string.utf8), sourceURL: sourceURL)
    }

    public init(contentsOf url: URL) throws(VerilogASourceError) {
        try Self.validateSourceURL(url)
        do {
            try self.init(data: Data(contentsOf: url), sourceURL: url)
        } catch {
            throw VerilogASourceError.fileSystemFailure(
                operation: "read source",
                path: url.path,
                message: error.localizedDescription
            )
        }
    }

    private static func validateSourceURL(_ url: URL) throws(VerilogASourceError) {
        guard url.isFileURL else {
            throw .invalidSourceURL(
                operation: "validate source",
                path: url.absoluteString,
                message: "URL must use the file scheme"
            )
        }

        if let host = url.host(),
           !host.isEmpty,
           host.lowercased() != "localhost" {
            throw .invalidSourceURL(
                operation: "validate source",
                path: url.absoluteString,
                message: "File URL host must be empty or localhost"
            )
        }

        let decodedPath = url.path(percentEncoded: false)
        guard !decodedPath.contains("\0") else {
            throw .invalidSourceURL(
                operation: "validate source",
                path: url.path(percentEncoded: true),
                message: "File URL path must not contain NUL"
            )
        }

        guard !url.path.isEmpty else {
            throw .invalidSourceURL(
                operation: "validate source",
                path: url.absoluteString,
                message: "File URL path must not be empty"
            )
        }
    }

    public var count: Int {
        data.count
    }

    public func string(in range: VerilogASourceRange) -> String {
        let boundedRange = clamped(range)
        guard !boundedRange.isEmpty else { return "" }
        return String(decoding: data[boundedRange.lowerBound..<boundedRange.upperBound], as: UTF8.self)
    }

    package func byte(at offset: Int) -> UInt8? {
        guard offset >= 0, offset < data.count else { return nil }
        return data[offset]
    }

    package func matchesASCII(_ ascii: [UInt8], in range: VerilogASourceRange) -> Bool {
        guard range.count == ascii.count,
              range.lowerBound >= 0,
              range.upperBound <= data.count else {
            return false
        }

        for (index, expected) in ascii.enumerated() {
            if data[range.lowerBound + index] != expected {
                return false
            }
        }
        return true
    }

    private func clamped(_ range: VerilogASourceRange) -> VerilogASourceRange {
        VerilogASourceRange(
            lowerBound: max(0, min(data.count, range.lowerBound)),
            upperBound: max(0, min(data.count, range.upperBound))
        )
    }
}

#endif
