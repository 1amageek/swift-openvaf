@preconcurrency import Foundation
import Darwin

package struct FoundationOpenVAFProcessRunner: OpenVAFProcessRunning {
    private static let pipeReadRetryInterval: Duration = .milliseconds(5)
    private static let postExitPipeDrainGrace: Duration = .milliseconds(100)

    package init() {}

    package func run(_ command: OpenVAFProcessCommand) async throws -> OpenVAFProcessResult {
        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.environment = command.environment
        process.currentDirectoryURL = command.workingDirectory

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice

        let executablePath = command.executableURL.path
        let timeout = command.timeout
        let terminationGrace = command.terminationGrace
        let timeoutTask = ProcessTimeoutTask()
        let controller = ProcessController(process: process)
        let exitState = ProcessExitState()
        let coordinator = ProcessRunCoordinator(
            executablePath: executablePath,
            timeout: timeout,
            startedAt: Date()
        )

        return try await withTaskCancellationHandler {
            if Task.isCancelled {
                Self.closePipeHandles(outputPipe: outputPipe, errorPipe: errorPipe)
                await coordinator.recordPrelaunchCancellation()
                return try await coordinator.waitForResult()
            }

            process.terminationHandler = { terminatedProcess in
                let status = exitState.record(status: terminatedProcess.terminationStatus)
                Task { await coordinator.recordExit(status) }
            }

            do {
                try await controller.run()
            } catch {
                Self.closePipeHandles(outputPipe: outputPipe, errorPipe: errorPipe)
                await coordinator.recordLaunchFailure(error.localizedDescription)
                return try await coordinator.waitForResult()
            }

            Self.closeWriteHandles(outputPipe: outputPipe, errorPipe: errorPipe)

            let outputTask = Task.detached(priority: nil) {
                let data = await Self.readAllData(
                    from: outputPipe.fileHandleForReading.fileDescriptor,
                    coordinator: coordinator
                )
                await coordinator.recordOutput(data)
            }
            let errorTask = Task.detached(priority: nil) {
                let data = await Self.readAllData(
                    from: errorPipe.fileHandleForReading.fileDescriptor,
                    coordinator: coordinator
                )
                await coordinator.recordError(data)
            }

            timeoutTask.set(Task { @Sendable in
                do {
                    try await ContinuousClock().sleep(for: timeout)
                } catch {
                    return
                }
                guard await controller.prepareTerminationIfRunningOrPendingStart() else { return }
                await coordinator.requestTermination(.timedOut)
                await controller.applyPreparedTermination()

                do {
                    try await ContinuousClock().sleep(for: terminationGrace)
                } catch {
                    return
                }
                guard await controller.isRunning() else { return }
                await controller.forceKillIfRunning()
            })

            defer {
                timeoutTask.cancel()
                outputTask.cancel()
                errorTask.cancel()
                Self.closeReadHandles(outputPipe: outputPipe, errorPipe: errorPipe)
            }

            return try await coordinator.waitForResult()
        } onCancel: {
            timeoutTask.cancel()
            Task {
                guard exitState.recordedStatus() == nil else { return }
                guard await controller.prepareTerminationIfRunningOrPendingStart() else { return }
                await coordinator.requestTermination(.cancelled)
                await controller.applyPreparedTermination()
                do {
                    try await ContinuousClock().sleep(for: terminationGrace)
                } catch {
                    return
                }
                await controller.forceKillIfRunning()
            }
        }
    }

    private static func closePipeHandles(outputPipe: Pipe, errorPipe: Pipe) {
        closeWriteHandles(outputPipe: outputPipe, errorPipe: errorPipe)
        closeReadHandles(outputPipe: outputPipe, errorPipe: errorPipe)
    }

    private static func closeWriteHandles(outputPipe: Pipe, errorPipe: Pipe) {
        outputPipe.fileHandleForWriting.closeFile()
        errorPipe.fileHandleForWriting.closeFile()
    }

    private static func closeReadHandles(outputPipe: Pipe, errorPipe: Pipe) {
        outputPipe.fileHandleForReading.closeFile()
        errorPipe.fileHandleForReading.closeFile()
    }

    private static func readAllData(
        from fileDescriptor: Int32,
        coordinator: ProcessRunCoordinator
    ) async -> Data {
        let clock = ContinuousClock()
        let originalFlags = fcntl(fileDescriptor, F_GETFL)
        let didSetNonBlocking: Bool
        if originalFlags == -1 {
            didSetNonBlocking = false
        } else {
            didSetNonBlocking = fcntl(fileDescriptor, F_SETFL, originalFlags | O_NONBLOCK) != -1
        }
        defer {
            if didSetNonBlocking {
                _ = fcntl(fileDescriptor, F_SETFL, originalFlags)
            }
        }

        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        var postExitDrainBeganAt: ContinuousClock.Instant?

        while true {
            if await coordinator.hasProcessFinished() {
                let now = clock.now
                if let drainBeganAt = postExitDrainBeganAt {
                    if drainBeganAt.duration(to: now) >= Self.postExitPipeDrainGrace {
                        break
                    }
                } else {
                    postExitDrainBeganAt = now
                }
            }

            let byteCount = buffer.withUnsafeMutableBufferPointer { pointer in
                read(fileDescriptor, pointer.baseAddress, pointer.count)
            }

            if byteCount > 0 {
                result.append(contentsOf: buffer.prefix(byteCount))
                continue
            }

            if byteCount == 0 {
                break
            }

            if errno == EINTR {
                continue
            }

            if errno == EAGAIN || errno == EWOULDBLOCK {
                do {
                    try await clock.sleep(for: Self.pipeReadRetryInterval)
                } catch {
                    break
                }
                continue
            }

            break
        }

        return result
    }
}
