import Foundation

#if VerilogACompiler

/// Frontend API for parsing Verilog-A source into source-range IR.
public protocol VerilogAParsing: VerilogACompilerBackend {
    func parse(_ source: VerilogASourceBuffer) -> VerilogAParseResult
    func parse(contentsOf sourceURL: URL) throws(VerilogASourceError) -> VerilogAParseResult
}

#endif
