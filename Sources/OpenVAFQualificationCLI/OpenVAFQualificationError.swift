import Foundation

enum OpenVAFQualificationError: Error, LocalizedError {
    case environmentMissing(String)
    case executableDigestMismatch(expected: String, actual: String)
    case expectedCompilationFailure
    case unexpectedCompilationError(String)
    case expectedTimeout
    case requiredTraitsMissing

    var errorDescription: String? {
        switch self {
        case .environmentMissing(let name):
            "Required qualification environment variable \(name) is missing."
        case .executableDigestMismatch(let expected, let actual):
            "OpenVAF executable digest mismatch. Expected \(expected), got \(actual)."
        case .expectedCompilationFailure:
            "Malformed Verilog-A unexpectedly compiled successfully."
        case .unexpectedCompilationError(let message):
            "OpenVAF returned an unexpected qualification error: \(message)"
        case .expectedTimeout:
            "OpenVAF compilation unexpectedly completed within the forced timeout."
        case .requiredTraitsMissing:
            "OpenVAF qualification requires the OpenVAFCLI and VerilogACompiler traits."
        }
    }
}
