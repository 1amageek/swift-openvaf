import CircuiteFoundation
import CircuiteFoundationFoundation
import Foundation

public enum OpenVAFArtifactBindingError: Error, Sendable, Equatable {
    case availabilityIdentityMismatch
    case localAvailabilityRequired
    case unsupportedLocalRoot(String)
}

/// Binds location-independent content identity to one OpenVAF execution materialization.
public struct OpenVAFArtifactBinding: Sendable, Hashable, Codable {
    public static let localFileSystemRootIdentifier = "openvaf-local-file-system"

    public let reference: ArtifactReference
    public let availability: ArtifactAvailability

    public var id: ArtifactID { reference.id }
    public var descriptor: ArtifactDescriptor { reference.descriptor }
    public var digest: ContentDigest { reference.digest }
    public var byteCount: UInt64 { reference.byteCount }

    public init(
        reference: ArtifactReference,
        availability: ArtifactAvailability
    ) throws {
        guard reference.id == availability.artifactID else {
            throw OpenVAFArtifactBindingError.availabilityIdentityMismatch
        }
        self.reference = reference
        self.availability = availability
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            reference: container.decode(ArtifactReference.self, forKey: .reference),
            availability: container.decode(ArtifactAvailability.self, forKey: .availability)
        )
    }

    public static func local(
        reference: ArtifactReference,
        fileURL: URL
    ) throws -> Self {
        guard fileURL.isFileURL else {
            throw OpenVAFArtifactBindingError.localAvailabilityRequired
        }
        return try Self(
            reference: reference,
            availability: .local(
                artifactID: reference.id,
                rootID: ArtifactRootID(rawValue: localFileSystemRootIdentifier),
                relativePath: ArtifactRelativePath(
                    segments: fileURL.standardizedFileURL.path(percentEncoded: false)
                        .split(separator: "/", omittingEmptySubsequences: true)
                        .map(String.init)
                )
            )
        )
    }

    public func localFileURL() throws -> URL {
        guard case .local(_, let rootID, let relativePath) = availability else {
            throw OpenVAFArtifactBindingError.localAvailabilityRequired
        }
        guard rootID.rawValue == Self.localFileSystemRootIdentifier else {
            throw OpenVAFArtifactBindingError.unsupportedLocalRoot(rootID.rawValue)
        }
        return relativePath.segments.reduce(URL(filePath: "/", directoryHint: .isDirectory)) {
            partial, segment in
            partial.appending(path: segment)
        }
    }
}
