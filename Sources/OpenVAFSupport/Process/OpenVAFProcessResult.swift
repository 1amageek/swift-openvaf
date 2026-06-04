import Foundation

#if OpenVAFCLI

package struct OpenVAFProcessResult: Sendable, Equatable {
    package let exitCode: Int32
    package let standardOutput: String
    package let standardError: String
    package let startedAt: Date
    package let finishedAt: Date

    package init(
        exitCode: Int32,
        standardOutput: String,
        standardError: String,
        startedAt: Date,
        finishedAt: Date
    ) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

#endif
