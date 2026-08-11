import CircuiteFoundation
import CircuiteFoundationFoundation
import Foundation
import OpenVAFSupport
import Testing

@Suite("OpenVAF artifact binding")
struct OpenVAFArtifactBindingTests {
    @Test("Binding rejects availability for different content")
    func rejectsAvailabilityIdentityMismatch() throws {
        let reference = try artifactReference(hexDigit: "a")
        let otherReference = try artifactReference(hexDigit: "b")
        let availability = ArtifactAvailability.local(
            artifactID: otherReference.id,
            rootID: try ArtifactRootID(
                rawValue: OpenVAFArtifactBinding.localFileSystemRootIdentifier
            ),
            relativePath: try ArtifactRelativePath(segments: ["tmp", "model.osdi"])
        )

        #expect(throws: OpenVAFArtifactBindingError.availabilityIdentityMismatch) {
            _ = try OpenVAFArtifactBinding(
                reference: reference,
                availability: availability
            )
        }
    }

    @Test("Binding round-trips identity and local availability")
    func roundTripsLocalAvailability() throws {
        let reference = try artifactReference(hexDigit: "c")
        let binding = try OpenVAFArtifactBinding(
            reference: reference,
            availability: .local(
                artifactID: reference.id,
                rootID: ArtifactRootID(
                    rawValue: OpenVAFArtifactBinding.localFileSystemRootIdentifier
                ),
                relativePath: ArtifactRelativePath(segments: ["tmp", "model.osdi"])
            )
        )

        let encoded = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(OpenVAFArtifactBinding.self, from: encoded)

        #expect(decoded == binding)
        #expect(try decoded.localFileURL() == URL(filePath: "/tmp/model.osdi"))
    }

    @Test("Binding rejects unknown local roots")
    func rejectsUnknownLocalRoot() throws {
        let reference = try artifactReference(hexDigit: "d")
        let binding = try OpenVAFArtifactBinding(
            reference: reference,
            availability: .local(
                artifactID: reference.id,
                rootID: ArtifactRootID(rawValue: "unknown-root"),
                relativePath: ArtifactRelativePath(segments: ["model.osdi"])
            )
        )

        #expect(
            throws: OpenVAFArtifactBindingError.unsupportedLocalRoot("unknown-root")
        ) {
            _ = try binding.localFileURL()
        }
    }

    private func artifactReference(hexDigit: Character) throws -> ArtifactReference {
        try ArtifactReference(
            digest: ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: hexDigit, count: 64)
            ),
            byteCount: 1,
            descriptor: ArtifactDescriptor(
                role: .output,
                kind: .model,
                format: ArtifactFormat(rawValue: "osdi")
            )
        )
    }
}
