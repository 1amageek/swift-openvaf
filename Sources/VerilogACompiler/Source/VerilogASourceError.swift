import Foundation

#if VerilogACompiler

/// Errors emitted while loading Verilog-A source for the Verilog-A compiler frontend.
public enum VerilogASourceError: Error, Sendable, Equatable {
    case invalidSourceURL(operation: String, path: String, message: String)
    case fileSystemFailure(operation: String, path: String, message: String)
}

extension VerilogASourceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidSourceURL(let operation, let path, let message):
            return "Verilog-A source operation failed: \(operation) at \(path): \(message)"
        case .fileSystemFailure(let operation, let path, let message):
            return "Verilog-A source operation failed: \(operation) at \(path): \(message)"
        }
    }
}

#endif
