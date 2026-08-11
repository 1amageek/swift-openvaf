import CircuiteFoundation

public protocol OpenVAFArtifactBindingProviding: ArtifactProducing {
    var artifactBindings: [OpenVAFArtifactBinding] { get }
}

public extension OpenVAFArtifactBindingProviding {
    var artifacts: [ArtifactReference] {
        artifactBindings.map(\.reference)
    }
}
