import Foundation

#if VerilogACompiler

/// Error emitted when a source range does not identify bytes inside a source buffer.
public enum VerilogASourceRangeError: Error, Sendable, Equatable {
    case invalidRange(VerilogASourceRange, sourceByteCount: Int, message: String)
}

extension VerilogASourceRangeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidRange(let range, let sourceByteCount, let message):
            return "Invalid Verilog-A source range \(range.lowerBound)..<\(range.upperBound) for \(sourceByteCount) bytes: \(message)"
        }
    }
}

#endif
