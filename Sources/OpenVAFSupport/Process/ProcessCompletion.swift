#if OpenVAFCLI

import Foundation
import Synchronization
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

package enum ProcessCompletion: Sendable {
    case exited(Int32)
    case launchFailed(String)
    case timedOut
    case cancelled
}

package final class ProcessExitState: Sendable {
    private let exitStatus = Mutex<Int32?>(nil)

    package init() {}

    package func record(status: Int32) -> Int32 {
        exitStatus.withLock { state in
            if let state {
                return state
            }
            state = status
            return status
        }
    }

    package func recordedStatus() -> Int32? {
        exitStatus.withLock { $0 }
    }
}

package enum ProcessTerminationRequest: Sendable {
    case timedOut
    case cancelled
}

package actor ProcessController {
    private let process: Process
    private var didStart = false
    private var pendingTermination = false
    private var pendingForceKill = false

    package init(process: Process) {
        self.process = process
    }

    package func run() throws {
        try process.run()
        didStart = true
        applyPendingTermination()
    }

    package func terminate() {
        _ = terminateIfRunningOrPendingStart()
    }

    package func terminateIfRunningOrPendingStart() -> Bool {
        guard prepareTerminationIfRunningOrPendingStart() else { return false }
        applyPendingTermination()
        return true
    }

    package func prepareTerminationIfRunningOrPendingStart() -> Bool {
        guard didStart else {
            pendingTermination = true
            return true
        }
        guard process.isRunning else { return false }
        pendingTermination = true
        return true
    }

    package func applyPreparedTermination() {
        applyPendingTermination()
    }

    package func forceKillIfRunning() {
        _ = forceKillIfRunningOrPendingStart()
    }

    package func forceKillIfRunningOrPendingStart() -> Bool {
        guard didStart else {
            pendingTermination = true
            pendingForceKill = true
            return true
        }
        guard process.isRunning else { return false }
        kill(process.processIdentifier, SIGKILL)
        return true
    }

    package func isRunning() -> Bool {
        guard didStart else { return false }
        return process.isRunning
    }

    private func applyPendingTermination() {
        guard process.isRunning else { return }
        if pendingForceKill {
            kill(process.processIdentifier, SIGKILL)
        } else if pendingTermination {
            process.terminate()
        }
    }
}

package final class ProcessTimeoutTask: Sendable {
    private struct State: Sendable {
        var task: Task<Void, Never>?
        var shouldCancelImmediately = false
    }

    private let state = Mutex(State())

    package init() {}

    package func set(_ task: Task<Void, Never>) {
        let shouldCancel = state.withLock { state in
            if state.shouldCancelImmediately {
                return true
            }
            state.task = task
            return false
        }

        if shouldCancel {
            task.cancel()
        }
    }

    package func cancel() {
        let task = state.withLock { state in
            state.shouldCancelImmediately = true
            let task = state.task
            state.task = nil
            return task
        }
        task?.cancel()
    }
}

package actor ProcessRunCoordinator {
    private let executablePath: String
    private let timeout: Duration
    private let startedAt: Date

    private var outputData = Data()
    private var errorData = Data()
    private var didFinishOutput = false
    private var didFinishError = false
    private var exitCode: Int32?
    private var terminationRequest: ProcessTerminationRequest?
    private var immediateCompletion: ProcessCompletion?
    private var continuation: CheckedContinuation<OpenVAFProcessResult, any Error>?

    package init(
        executablePath: String,
        timeout: Duration,
        startedAt: Date
    ) {
        self.executablePath = executablePath
        self.timeout = timeout
        self.startedAt = startedAt
    }

    package func waitForResult() async throws -> OpenVAFProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            finishIfReady()
        }
    }

    package func recordOutput(_ data: Data) {
        outputData = data
        didFinishOutput = true
        finishIfReady()
    }

    package func recordError(_ data: Data) {
        errorData = data
        didFinishError = true
        finishIfReady()
    }

    package func recordExit(_ status: Int32) {
        exitCode = status
        finishIfReady()
    }

    package func hasProcessFinished() -> Bool {
        exitCode != nil || immediateCompletion != nil
    }

    package func requestTermination(_ request: ProcessTerminationRequest) {
        if exitCode == nil, immediateCompletion == nil, terminationRequest == nil {
            terminationRequest = request
        }
    }

    package func recordLaunchFailure(_ message: String) {
        immediateCompletion = .launchFailed(message)
        finishIfReady()
    }

    package func recordPrelaunchCancellation() {
        immediateCompletion = .cancelled
        finishIfReady()
    }

    private func finishIfReady() {
        guard let continuation else { return }

        if let immediateCompletion {
            self.continuation = nil
            resume(continuation, completion: immediateCompletion)
            return
        }

        guard let exitCode, didFinishOutput, didFinishError else { return }

        self.continuation = nil
        let completion: ProcessCompletion
        switch terminationRequest {
        case .timedOut:
            completion = .timedOut
        case .cancelled:
            completion = .cancelled
        case nil:
            completion = .exited(exitCode)
        }
        resume(continuation, completion: completion)
    }

    private func resume(
        _ continuation: CheckedContinuation<OpenVAFProcessResult, any Error>,
        completion: ProcessCompletion
    ) {
        let standardOutput = String(decoding: outputData, as: UTF8.self)
        let standardError = String(decoding: errorData, as: UTF8.self)
        let finishedAt = Date()

        switch completion {
        case .exited(let exitCode):
            continuation.resume(returning: OpenVAFProcessResult(
                exitCode: exitCode,
                standardOutput: standardOutput,
                standardError: standardError,
                startedAt: startedAt,
                finishedAt: finishedAt
            ))
        case .launchFailed(let message):
            continuation.resume(throwing: OpenVAFProcessError.launchFailed(
                executablePath: executablePath,
                message: message
            ))
        case .timedOut:
            continuation.resume(throwing: OpenVAFProcessError.timedOut(
                executablePath: executablePath,
                timeout: timeout,
                standardOutput: standardOutput,
                standardError: standardError,
                startedAt: startedAt,
                finishedAt: finishedAt
            ))
        case .cancelled:
            continuation.resume(throwing: OpenVAFProcessError.cancelled(
                executablePath: executablePath,
                standardOutput: standardOutput,
                standardError: standardError,
                startedAt: startedAt,
                finishedAt: finishedAt
            ))
        }
    }
}

#endif
