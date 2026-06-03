import Foundation
import Testing
@testable import OpenVAFSupport

@Suite("Process run coordinator", .timeLimit(.minutes(1)))
struct ProcessRunCoordinatorTests {
    @Test("Coordinator preserves timeout requests recorded before process exit")
    func coordinatorPreservesTimeoutRequestsRecordedBeforeProcessExit() async throws {
        let coordinator = ProcessRunCoordinator(
            executablePath: "/bin/openvaf",
            timeout: .milliseconds(50),
            startedAt: Date(timeIntervalSince1970: 1)
        )

        await coordinator.requestTermination(.timedOut)
        await coordinator.recordExit(15)
        await coordinator.recordOutput(Data("partial".utf8))
        await coordinator.recordError(Data("timed out".utf8))

        do {
            _ = try await coordinator.waitForResult()
            Issue.record("Expected timeout")
        } catch let error as OpenVAFProcessError {
            switch error {
            case .timedOut(_, let timeout, let standardOutput, let standardError, _, _):
                #expect(timeout == .milliseconds(50))
                #expect(standardOutput == "partial")
                #expect(standardError == "timed out")
            case .launchFailed, .cancelled:
                Issue.record("Expected timeout, got \(error)")
            }
        } catch {
            Issue.record("Expected OpenVAFProcessError, got \(error)")
        }
    }

    @Test("Coordinator ignores timeout requests recorded after process exit")
    func coordinatorIgnoresTimeoutRequestsRecordedAfterProcessExit() async throws {
        let coordinator = ProcessRunCoordinator(
            executablePath: "/bin/openvaf",
            timeout: .milliseconds(50),
            startedAt: Date(timeIntervalSince1970: 1)
        )

        await coordinator.recordExit(0)
        await coordinator.requestTermination(.timedOut)
        await coordinator.recordOutput(Data("ok".utf8))
        await coordinator.recordError(Data())

        let result = try await coordinator.waitForResult()

        #expect(result.exitCode == 0)
        #expect(result.standardOutput == "ok")
    }

    @Test("Coordinator ignores cancellation requests recorded after process exit")
    func coordinatorIgnoresCancellationRequestsRecordedAfterProcessExit() async throws {
        let coordinator = ProcessRunCoordinator(
            executablePath: "/bin/openvaf",
            timeout: .seconds(5),
            startedAt: Date(timeIntervalSince1970: 1)
        )

        await coordinator.recordExit(0)
        await coordinator.requestTermination(.cancelled)
        await coordinator.recordOutput(Data("ok".utf8))
        await coordinator.recordError(Data())

        let result = try await coordinator.waitForResult()

        #expect(result.exitCode == 0)
        #expect(result.standardOutput == "ok")
    }

    @Test("Coordinator maps normal exits after cancellation requests")
    func coordinatorMapsNormalExitsAfterCancellationRequests() async throws {
        let coordinator = ProcessRunCoordinator(
            executablePath: "/bin/openvaf",
            timeout: .seconds(5),
            startedAt: Date(timeIntervalSince1970: 1)
        )

        await coordinator.requestTermination(.cancelled)
        await coordinator.recordExit(2)
        await coordinator.recordOutput(Data("out".utf8))
        await coordinator.recordError(Data("err".utf8))

        do {
            _ = try await coordinator.waitForResult()
            Issue.record("Expected cancellation")
        } catch let error as OpenVAFProcessError {
            switch error {
            case .cancelled(_, let standardOutput, let standardError, _, _):
                #expect(standardOutput == "out")
                #expect(standardError == "err")
            case .launchFailed, .timedOut:
                Issue.record("Expected cancellation, got \(error)")
            }
        } catch {
            Issue.record("Expected OpenVAFProcessError, got \(error)")
        }
    }

    @Test("Coordinator maps terminated exits after cancellation requests")
    func coordinatorMapsTerminatedExitsAfterCancellationRequests() async throws {
        let coordinator = ProcessRunCoordinator(
            executablePath: "/bin/openvaf",
            timeout: .seconds(5),
            startedAt: Date(timeIntervalSince1970: 1)
        )

        await coordinator.requestTermination(.cancelled)
        await coordinator.recordExit(SIGTERM)
        await coordinator.recordOutput(Data("partial".utf8))
        await coordinator.recordError(Data())

        do {
            _ = try await coordinator.waitForResult()
            Issue.record("Expected cancellation")
        } catch let error as OpenVAFProcessError {
            switch error {
            case .cancelled(_, let standardOutput, let standardError, _, _):
                #expect(standardOutput == "partial")
                #expect(standardError == "")
            case .launchFailed, .timedOut:
                Issue.record("Expected cancellation, got \(error)")
            }
        } catch {
            Issue.record("Expected OpenVAFProcessError, got \(error)")
        }
    }
}
