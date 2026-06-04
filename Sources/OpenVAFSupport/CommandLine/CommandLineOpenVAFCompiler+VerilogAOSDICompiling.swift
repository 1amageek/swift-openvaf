import Foundation
import VerilogACompiler

#if OpenVAFCLI

extension CommandLineOpenVAFCompiler: VerilogAOSDICompiling {
    public var implementation: VerilogACompilerImplementation {
        .openVAF
    }

    public func compileOSDI(
        sourceAt sourceURL: URL,
        to outputDirectory: URL
    ) async throws -> OpenVAFCompilationArtifact {
        try await compile(OpenVAFCompilationRequest(
            sourceURL: sourceURL,
            outputDirectory: outputDirectory
        ))
    }
}

#endif
