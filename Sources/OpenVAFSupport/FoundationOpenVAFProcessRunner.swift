@preconcurrency import Foundation
import Darwin

package struct FoundationOpenVAFProcessRunner: OpenVAFProcessRunning {
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

        let executablePath = command.executableURL.path
        let timeout = command.timeout
        let terminationGrace = command.terminationGrace
        let timeoutTask = ProcessTimeoutTask()
        let controller = ProcessController(process: process)
        let coordinator = ProcessRunCoordinator(
            executablePath: executablePath,
            timeout: timeout,
            startedAt: Date()
        )

        return try await withTaskCancellationHandler {
            if Task.isCancelled {
                await coordinator.recordPrelaunchCancellation()
                return try await coordinator.waitForResult()
            }

            process.terminationHandler = { terminatedProcess in
                let status = terminatedProcess.terminationStatus
                Task { await coordinator.recordExit(status) }
            }

            do {
                try await controller.run()
            } catch {
                await coordinator.recordLaunchFailure(error.localizedDescription)
                return try await coordinator.waitForResult()
            }

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
                await coordinator.requestTermination(.timedOut)
                await controller.terminate()

                do {
                    try await ContinuousClock().sleep(for: terminationGrace)
                } catch {
                    return
                }
                await controller.forceKillIfRunning()
            })

            defer {
                timeoutTask.cancel()
                outputTask.cancel()
                errorTask.cancel()
                outputPipe.fileHandleForReading.closeFile()
                errorPipe.fileHandleForReading.closeFile()
            }

            return try await coordinator.waitForResult()
        } onCancel: {
            timeoutTask.cancel()
            Task {
                await coordinator.requestTermination(.cancelled)
                await controller.terminate()
                do {
                    try await ContinuousClock().sleep(for: terminationGrace)
                } catch {
                    return
                }
                await controller.forceKillIfRunning()
            }
        }
    }

    private static func readAllData(
        from fileDescriptor: Int32,
        coordinator: ProcessRunCoordinator
    ) async -> Data {
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

        while true {
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
                if await coordinator.shouldStopReadingWhenIdle() {
                    break
                }
                do {
                    try await ContinuousClock().sleep(for: .milliseconds(5))
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
