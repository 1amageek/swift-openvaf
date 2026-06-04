import Foundation

#if OpenVAFCLI

package enum OpenVAFProcessError: Error, Sendable, Equatable {
    case launchFailed(executablePath: String, message: String)
    case timedOut(
        executablePath: String,
        timeout: Duration,
        standardOutput: String,
        standardError: String,
        startedAt: Date,
        finishedAt: Date
    )
    case cancelled(
        executablePath: String,
        standardOutput: String,
        standardError: String,
        startedAt: Date,
        finishedAt: Date
    )
}

#endif
