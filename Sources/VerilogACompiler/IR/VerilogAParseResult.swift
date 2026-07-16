import CircuiteFoundation
import Foundation

#if VerilogACompiler

/// Parsed Verilog-A frontend result.
public struct VerilogAParseResult: Sendable, Equatable {
    public let source: VerilogASourceBuffer
    public let modules: [VerilogAModule]
    public let diagnostics: [VerilogADiagnostic]

    public init(
        source: VerilogASourceBuffer,
        modules: [VerilogAModule],
        diagnostics: [VerilogADiagnostic]
    ) {
        self.source = source
        self.modules = modules
        self.diagnostics = diagnostics
    }

    public var designDiagnostics: [DesignDiagnostic] {
        diagnostics.map {
            $0.designDiagnostic(sourceURL: source.sourceURL)
        }
    }
}

#endif
