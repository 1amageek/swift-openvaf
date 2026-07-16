import Foundation

#if OpenVAFCLI

/// Compiles Verilog-A sources into OSDI libraries through OpenVAF.
public protocol OpenVAFCompiler: Sendable {
    func availability() async -> OpenVAFAvailability
    func compile(_ request: OpenVAFCompilationRequest) async throws(OpenVAFError) -> OpenVAFCompilationResult
}

public extension OpenVAFCompiler {
    func compile(
        sourceAt sourceURL: URL,
        to outputDirectory: URL
    ) async throws(OpenVAFError) -> OpenVAFCompilationResult {
        try await compile(OpenVAFCompilationRequest(
            sourceURL: sourceURL,
            outputDirectory: outputDirectory
        ))
    }
}

#endif
