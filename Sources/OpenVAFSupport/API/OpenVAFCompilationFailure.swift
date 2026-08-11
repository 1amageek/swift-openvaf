import CircuiteFoundation
import CircuiteFoundationFoundation
import Foundation

/// Canonical evidence retained when an OpenVAF compilation does not complete.
public struct OpenVAFCompilationFailure: OpenVAFArtifactBindingProviding, DiagnosticReporting, Sendable, Hashable, Codable {
    public let artifactBindings: [OpenVAFArtifactBinding]
    public let diagnostics: [DesignDiagnostic]
    public let provenance: ExecutionProvenance
    public let openVAFVersion: String?
    public let exitCode: Int32?

    public init(
        artifactBindings: [OpenVAFArtifactBinding],
        diagnostics: [DesignDiagnostic],
        provenance: ExecutionProvenance,
        openVAFVersion: String?,
        exitCode: Int32?
    ) {
        self.artifactBindings = artifactBindings
        self.diagnostics = diagnostics
        self.provenance = provenance
        self.openVAFVersion = openVAFVersion
        self.exitCode = exitCode
    }

    public var logArtifacts: [ArtifactReference] {
        artifactBindings
            .filter { $0.descriptor.kind == .log }
            .map(\.reference)
    }
}
