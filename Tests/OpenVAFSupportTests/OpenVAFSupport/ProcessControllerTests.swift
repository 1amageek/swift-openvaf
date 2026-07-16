import Darwin
import Foundation
import Testing
@testable import OpenVAFSupport

#if OpenVAFCLI

@Suite("Process controller", .serialized, .timeLimit(.minutes(1)))
struct ProcessControllerTests {
    @Test("Controller applies termination requested before process start")
    func controllerAppliesTerminationRequestedBeforeProcessStart() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["5"]
        let controller = ProcessController(process: process)

        await controller.terminate()
        try await controller.run()
        try await waitUntilProcessStops(process)

        #expect(!process.isRunning)
    }

    @Test("Controller applies force kill requested before process start")
    func controllerAppliesForceKillRequestedBeforeProcessStart() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["5"]
        let controller = ProcessController(process: process)

        await controller.forceKillIfRunning()
        try await controller.run()
        try await waitUntilProcessStops(process)

        #expect(!process.isRunning)
    }

    @Test("Controller prepares termination without signaling until applied")
    func controllerPreparesTerminationWithoutSignalingUntilApplied() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["5"]
        let controller = ProcessController(process: process)

        try await controller.run()

        let didPrepareTermination = await controller.prepareTerminationIfRunningOrPendingStart()

        #expect(didPrepareTermination)
        #expect(process.isRunning)

        await controller.applyPreparedTermination()
        try await waitUntilProcessStops(process)

        #expect(!process.isRunning)
    }

    @Test("Controller refuses termination after process exit")
    func controllerRefusesTerminationAfterProcessExit() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        let controller = ProcessController(process: process)

        try await controller.run()
        try await waitUntilProcessStops(process)

        let didRequestTermination = await controller.terminateIfRunningOrPendingStart()

        #expect(!didRequestTermination)
    }

    @Test("Controller refuses force kill after process exit")
    func controllerRefusesForceKillAfterProcessExit() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        let controller = ProcessController(process: process)

        try await controller.run()
        try await waitUntilProcessStops(process)

        let didRequestForceKill = await controller.forceKillIfRunningOrPendingStart()

        #expect(!didRequestForceKill)
    }

    private func waitUntilProcessStops(_ process: Process) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while process.isRunning && clock.now < deadline {
            try await clock.sleep(for: .milliseconds(10))
        }
        guard process.isRunning else { return }

        Issue.record("Process did not stop within the expected termination window")
        let processIdentifier = process.processIdentifier
        let killResult = kill(processIdentifier, SIGKILL)
        if killResult != 0 && errno != ESRCH {
            Issue.record("Failed to kill test process: errno \(errno)")
            return
        }

        let forceKillDeadline = clock.now.advanced(by: .seconds(1))
        while process.isRunning && clock.now < forceKillDeadline {
            try await clock.sleep(for: .milliseconds(10))
        }
        if process.isRunning {
            Issue.record("Process remained running after SIGKILL")
        }
    }
}

#endif
