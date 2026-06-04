import Foundation

#if VerilogACompiler

/// Verilog-A keywords recognized by the Verilog-A compiler frontend.
public enum VerilogAKeyword: String, Sendable, Equatable, CaseIterable {
    case module
    case endmodule
    case analog
    case function
    case endfunction
    case beginBlock = "begin"
    case endBlock = "end"
    case initial
    case caseKeyword = "case"
    case endcase
    case parameter
    case real
    case integer
    case intKeyword = "int"
    case string
    case from
    case exclude
    case inoutKeyword = "inout"
    case input
    case output
    case electrical
    case ground
    case gnd
    case branch
    case thermal

    package static func match(
        in buffer: VerilogASourceBuffer,
        range: VerilogASourceRange
    ) -> VerilogAKeyword? {
        for keyword in VerilogAKeyword.allCases {
            if buffer.matchesASCII(keyword.asciiBytes, in: range) {
                return keyword
            }
        }
        return nil
    }

    private var asciiBytes: [UInt8] {
        switch self {
        case .module:
            Self.moduleBytes
        case .endmodule:
            Self.endmoduleBytes
        case .analog:
            Self.analogBytes
        case .function:
            Self.functionBytes
        case .endfunction:
            Self.endfunctionBytes
        case .beginBlock:
            Self.beginBytes
        case .endBlock:
            Self.endBytes
        case .initial:
            Self.initialBytes
        case .caseKeyword:
            Self.caseBytes
        case .endcase:
            Self.endcaseBytes
        case .parameter:
            Self.parameterBytes
        case .real:
            Self.realBytes
        case .integer:
            Self.integerBytes
        case .intKeyword:
            Self.intBytes
        case .string:
            Self.stringBytes
        case .from:
            Self.fromBytes
        case .exclude:
            Self.excludeBytes
        case .inoutKeyword:
            Self.inoutBytes
        case .input:
            Self.inputBytes
        case .output:
            Self.outputBytes
        case .electrical:
            Self.electricalBytes
        case .ground:
            Self.groundBytes
        case .gnd:
            Self.gndBytes
        case .branch:
            Self.branchBytes
        case .thermal:
            Self.thermalBytes
        }
    }

    private static let moduleBytes: [UInt8] = [109, 111, 100, 117, 108, 101]
    private static let endmoduleBytes: [UInt8] = [101, 110, 100, 109, 111, 100, 117, 108, 101]
    private static let analogBytes: [UInt8] = [97, 110, 97, 108, 111, 103]
    private static let functionBytes: [UInt8] = [102, 117, 110, 99, 116, 105, 111, 110]
    private static let endfunctionBytes: [UInt8] = [101, 110, 100, 102, 117, 110, 99, 116, 105, 111, 110]
    private static let beginBytes: [UInt8] = [98, 101, 103, 105, 110]
    private static let endBytes: [UInt8] = [101, 110, 100]
    private static let initialBytes: [UInt8] = [105, 110, 105, 116, 105, 97, 108]
    private static let caseBytes: [UInt8] = [99, 97, 115, 101]
    private static let endcaseBytes: [UInt8] = [101, 110, 100, 99, 97, 115, 101]
    private static let parameterBytes: [UInt8] = [112, 97, 114, 97, 109, 101, 116, 101, 114]
    private static let realBytes: [UInt8] = [114, 101, 97, 108]
    private static let integerBytes: [UInt8] = [105, 110, 116, 101, 103, 101, 114]
    private static let intBytes: [UInt8] = [105, 110, 116]
    private static let stringBytes: [UInt8] = [115, 116, 114, 105, 110, 103]
    private static let fromBytes: [UInt8] = [102, 114, 111, 109]
    private static let excludeBytes: [UInt8] = [101, 120, 99, 108, 117, 100, 101]
    private static let inoutBytes: [UInt8] = [105, 110, 111, 117, 116]
    private static let inputBytes: [UInt8] = [105, 110, 112, 117, 116]
    private static let outputBytes: [UInt8] = [111, 117, 116, 112, 117, 116]
    private static let electricalBytes: [UInt8] = [101, 108, 101, 99, 116, 114, 105, 99, 97, 108]
    private static let groundBytes: [UInt8] = [103, 114, 111, 117, 110, 100]
    private static let gndBytes: [UInt8] = [103, 110, 100]
    private static let branchBytes: [UInt8] = [98, 114, 97, 110, 99, 104]
    private static let thermalBytes: [UInt8] = [116, 104, 101, 114, 109, 97, 108]
}

#endif
