import Foundation

#if VerilogACompiler

/// Byte range inside a Verilog-A source buffer.
public struct VerilogASourceRange: Sendable, Equatable, Hashable {
    public let lowerBound: Int
    public let upperBound: Int

    public init(lowerBound: Int, upperBound: Int) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    public var count: Int {
        max(0, upperBound - lowerBound)
    }

    public var isEmpty: Bool {
        count == 0
    }

    package static func joining(
        _ first: VerilogASourceRange,
        _ second: VerilogASourceRange
    ) -> VerilogASourceRange {
        VerilogASourceRange(
            lowerBound: min(first.lowerBound, second.lowerBound),
            upperBound: max(first.upperBound, second.upperBound)
        )
    }
}

#endif
