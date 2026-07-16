import CircuiteFoundation
import Foundation

/// Canonical evidence produced by a successful OpenVAF compilation.
public struct OpenVAFCompilationResult: ArtifactProducing, DiagnosticReporting, Sendable, Hashable, Codable {
    public let artifacts: [ArtifactReference]
    public let diagnostics: [DesignDiagnostic]
    public let provenance: ExecutionProvenance
    public let openVAFVersion: String?
    public let exitCode: Int32

    public init(
        artifacts: [ArtifactReference],
        diagnostics: [DesignDiagnostic],
        provenance: ExecutionProvenance,
        openVAFVersion: String?,
        exitCode: Int32
    ) {
        self.artifacts = artifacts
        self.diagnostics = diagnostics
        self.provenance = provenance
        self.openVAFVersion = openVAFVersion
        self.exitCode = exitCode
    }

    public var outputArtifact: ArtifactReference? {
        artifacts.first {
            $0.locator.role == .output && $0.locator.kind == .model
        }
    }

    public var logArtifacts: [ArtifactReference] {
        artifacts.filter { $0.locator.kind == .log }
    }
}
