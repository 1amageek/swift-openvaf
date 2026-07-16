import CircuiteFoundation
import Foundation

#if VerilogACompiler

/// Diagnostic produced by the Verilog-A compiler frontend.
public struct VerilogADiagnostic: Sendable, Equatable {
    public enum Severity: Sendable, Equatable {
        case error
        case warning
    }

    public let severity: Severity
    public let message: String
    public let range: VerilogASourceRange

    public init(
        severity: Severity,
        message: String,
        range: VerilogASourceRange
    ) {
        self.severity = severity
        self.message = message
        self.range = range
    }

    /// Projects the domain diagnostic into the shared diagnostic contract while
    /// retaining the exact byte range in the detail payload.
    public func designDiagnostic(
        sourceURL: URL?,
        artifactID: ArtifactID? = nil
    ) -> DesignDiagnostic {
        let source = sourceURL?.standardizedFileURL.path(percentEncoded: false) ?? "in-memory"
        return DesignDiagnostic(
            code: .trusted("verilog-a.frontend.\(severity.code)"),
            severity: severity.designSeverity,
            summary: message,
            detail: "Source: \(source); UTF-8 byte range: [\(range.lowerBound), \(range.upperBound)).",
            artifactID: artifactID,
            suggestedActions: [
                SuggestedAction(
                    code: "inspect_verilog_a_source",
                    summary: "Inspect the reported Verilog-A source range."
                ),
            ]
        )
    }
}

private extension VerilogADiagnostic.Severity {
    var code: String {
        switch self {
        case .error: "error"
        case .warning: "warning"
        }
    }

    var designSeverity: DiagnosticSeverity {
        switch self {
        case .error: .error
        case .warning: .warning
        }
    }
}

#endif
