import Foundation
import SignoffToolSupport

#if OpenVAFCLI

package struct FoundationOpenVAFProcessRunner: OpenVAFProcessRunning {
    package init() {}

    package func run(
        _ command: OpenVAFProcessCommand
    ) async throws -> OpenVAFProcessResult {
        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.environment = command.environment
        process.currentDirectoryURL = command.workingDirectory

        let startedAt = Date()
        do {
            let result = try await TimedProcessRunner(
                timeoutSeconds: command.timeout.secondsValue,
                terminationGraceSeconds: command.terminationGrace.secondsValue,
                pipeDrainGraceSeconds: command.postExitOutputDrainGrace.secondsValue
            ).run(process: process)
            return OpenVAFProcessResult(
                exitCode: result.exitCode,
                standardOutput: result.standardOutput,
                standardError: result.standardError,
                startedAt: startedAt,
                finishedAt: Date()
            )
        } catch let error as TimedProcessError {
            let finishedAt = Date()
            switch error {
            case .launchFailed(let executablePath, let message):
                throw OpenVAFProcessError.launchFailed(
                    executablePath: executablePath,
                    message: message
                )
            case .invalidConfiguration(let message):
                throw OpenVAFProcessError.launchFailed(
                    executablePath: command.executableURL.path,
                    message: message
                )
            case .timedOut(
                let executablePath,
                _,
                let standardOutput,
                let standardError
            ):
                throw OpenVAFProcessError.timedOut(
                    executablePath: executablePath,
                    timeout: command.timeout,
                    standardOutput: standardOutput,
                    standardError: standardError,
                    startedAt: startedAt,
                    finishedAt: finishedAt
                )
            case .cancelled(
                let executablePath,
                let standardOutput,
                let standardError
            ):
                throw OpenVAFProcessError.cancelled(
                    executablePath: executablePath,
                    standardOutput: standardOutput,
                    standardError: standardError,
                    startedAt: startedAt,
                    finishedAt: finishedAt
                )
            case .cancellationCheckFailed(
                let executablePath,
                let message,
                _,
                _
            ):
                throw OpenVAFProcessError.launchFailed(
                    executablePath: executablePath,
                    message: message
                )
            }
        }
    }
}

private extension Duration {
    var secondsValue: Double {
        let components = self.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

#endif
