import Foundation

#if VerilogACompiler

/// Declaration categories recognized by the package parser.
public enum VerilogADeclarationKind: Sendable, Equatable {
    case inoutPort
    case input
    case output
    case electrical
    case ground
    case branch
    case thermal
    case real
    case integer
    case string
}

#endif
