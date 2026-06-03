import Foundation

/// Sanitized command metadata. Environment values are intentionally not persisted.
public struct OpenVAFCommandRecord: Sendable, Equatable {
    public let executableURL: URL
    public let arguments: [String]
    public let workingDirectory: URL
    public let environment: OpenVAFEnvironmentRecord
    public let environmentKeys: [String]

    public init(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        environment: OpenVAFEnvironmentRecord
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.environmentKeys = environment.keys
    }

    public init(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        environmentKeys: [String]
    ) {
        self.init(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: OpenVAFEnvironmentRecord(
                source: .explicit,
                keys: environmentKeys,
                valueSHA256: ""
            )
        )
    }
}
