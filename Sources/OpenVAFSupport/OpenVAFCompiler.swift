import Foundation

/// Compiles Verilog-A sources into OSDI libraries through OpenVAF.
public protocol OpenVAFCompiler: Sendable {
    func availability() async -> OpenVAFAvailability
    func compile(_ request: OpenVAFCompilationRequest) async throws(OpenVAFError) -> OpenVAFCompilationArtifact
}

public extension OpenVAFCompiler {
    func compile(
        sourceAt sourceURL: URL,
        to outputDirectory: URL
    ) async throws(OpenVAFError) -> OpenVAFCompilationArtifact {
        try await compile(OpenVAFCompilationRequest(
            sourceURL: sourceURL,
            outputDirectory: outputDirectory
        ))
    }
}
