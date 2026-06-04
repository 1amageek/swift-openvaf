import Foundation

#if VerilogACompiler

/// Verilog-A compiler frontend implementation.
public struct VerilogACompilerFrontend: VerilogAParsing {
    public init() {}

    public var implementation: VerilogACompilerImplementation {
        .inProcess
    }

    public func parse(_ source: VerilogASourceBuffer) -> VerilogAParseResult {
        var parser = VerilogAParser(buffer: source)
        return parser.parse()
    }

    public func parse(contentsOf sourceURL: URL) throws(VerilogASourceError) -> VerilogAParseResult {
        try parse(VerilogASourceBuffer(contentsOf: sourceURL))
    }
}

#endif
