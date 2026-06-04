import Foundation

/// Reproducible record of a failed OpenVAF compile invocation.
public struct OpenVAFCompilationFailure: Sendable, Equatable {
    public let sourceURL: URL
    public let sourceSHA256: String
    public let inputFiles: [OpenVAFInputFileRecord]
    public let stagedSourceURL: URL
    public let outputURL: URL
    public let command: OpenVAFCommandRecord
    public let openVAFVersion: String?
    public let exitCode: Int32?
    public let standardOutput: String
    public let standardError: String
    public let startedAt: Date?
    public let finishedAt: Date?

    public init(
        sourceURL: URL,
        sourceSHA256: String,
        inputFiles: [OpenVAFInputFileRecord] = [],
        stagedSourceURL: URL,
        outputURL: URL,
        command: OpenVAFCommandRecord,
        openVAFVersion: String?,
        exitCode: Int32?,
        standardOutput: String,
        standardError: String,
        startedAt: Date?,
        finishedAt: Date?
    ) {
        self.sourceURL = sourceURL
        self.sourceSHA256 = sourceSHA256
        self.inputFiles = inputFiles
        self.stagedSourceURL = stagedSourceURL
        self.outputURL = outputURL
        self.command = command
        self.openVAFVersion = openVAFVersion
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}
