import Foundation

package enum VerilogAIncludeScannerError: Error, Sendable, Equatable {
    case fileSystemFailure(
        operation: String,
        path: String,
        message: String
    )
}
