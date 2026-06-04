import Foundation

/// Capability for producing an OSDI artifact from a Verilog-A source file.
public protocol VerilogAOSDICompiling<Artifact>: VerilogACompilerBackend {
    associatedtype Artifact: Sendable

    func compileOSDI(
        sourceAt sourceURL: URL,
        to outputDirectory: URL
    ) async throws -> Artifact
}
