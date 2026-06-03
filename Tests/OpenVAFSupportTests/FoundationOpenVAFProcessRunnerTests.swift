import Foundation
import Testing
@testable import OpenVAFSupport

@Suite("FoundationOpenVAFProcessRunner", .timeLimit(.minutes(1)))
struct FoundationOpenVAFProcessRunnerTests {
    @Test("Run captures successful stdout and stderr")
    func runCapturesSuccessfulStdoutAndStderr() async throws {
        let runner = FoundationOpenVAFProcessRunner()
        let command = OpenVAFProcessCommand(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'out'; printf 'err' >&2"],
            environment: nil,
            workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            timeout: .seconds(5),
            terminationGrace: .milliseconds(10)
        )

        let result = try await runner.run(command)

        #expect(result.exitCode == 0)
        #expect(result.standardOutput == "out")
        #expect(result.standardError == "err")
    }

    @Test("Run provides EOF on standard input")
    func runProvidesEOFOnStandardInput() async throws {
        let runner = FoundationOpenVAFProcessRunner()
        let command = OpenVAFProcessCommand(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "if IFS= read -r line; then printf 'input:%s' \"$line\"; else printf eof; fi"],
            environment: nil,
            workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            timeout: .seconds(5),
            terminationGrace: .milliseconds(10)
        )

        let result = try await runner.run(command)

        #expect(result.exitCode == 0)
        #expect(result.standardOutput == "eof")
        #expect(result.standardError == "")
    }

    @Test("Run preserves invalid UTF-8 output with replacement characters")
    func runPreservesInvalidUTF8OutputWithReplacementCharacters() async throws {
        let runner = FoundationOpenVAFProcessRunner()
        let command = OpenVAFProcessCommand(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'prefix\\377suffix'"],
            environment: nil,
            workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            timeout: .seconds(5),
            terminationGrace: .milliseconds(10)
        )

        let result = try await runner.run(command)

        #expect(result.standardOutput.contains("prefix"))
        #expect(result.standardOutput.contains("suffix"))
        #expect(!result.standardOutput.isEmpty)
    }

    @Test("Run drains large stdout and stderr")
    func runDrainsLargeStdoutAndStderr() async throws {
        let runner = FoundationOpenVAFProcessRunner()
        let command = OpenVAFProcessCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/perl"),
            arguments: ["-e", "print \"o\" x 131072; print STDERR \"e\" x 131072;"],
            environment: nil,
            workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            timeout: .seconds(5),
            terminationGrace: .milliseconds(10)
        )

        let result = try await runner.run(command)

        #expect(result.exitCode == 0)
        #expect(result.standardOutput.count == 131_072)
        #expect(result.standardError.count == 131_072)
    }

    @Test("Run completes when an exited child leaves inherited pipe handles open")
    func runCompletesWhenExitedChildLeavesInheritedPipeHandlesOpen() async throws {
        let runner = FoundationOpenVAFProcessRunner()
        let clock = ContinuousClock()
        let startedAt = clock.now
        let command = OpenVAFProcessCommand(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "(sleep 2) & printf done"],
            environment: nil,
            workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            timeout: .seconds(5),
            terminationGrace: .milliseconds(10)
        )

        let result = try await runner.run(command)
        let elapsed = startedAt.duration(to: clock.now)

        #expect(result.exitCode == 0)
        #expect(result.standardOutput == "done")
        #expect(elapsed < .seconds(1))
    }

    @Test("Run stops draining after exited child continuously writes to inherited pipe")
    func runStopsDrainingAfterExitedChildContinuouslyWritesToInheritedPipe() async throws {
        let runner = FoundationOpenVAFProcessRunner()
        let clock = ContinuousClock()
        let startedAt = clock.now
        let command = OpenVAFProcessCommand(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "(sleep 0.01; while :; do printf x; sleep 0.01; done) & printf done"],
            environment: nil,
            workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            timeout: .seconds(5),
            terminationGrace: .milliseconds(10)
        )

        let result = try await runner.run(command)
        let elapsed = startedAt.duration(to: clock.now)

        #expect(result.exitCode == 0)
        #expect(result.standardOutput.hasPrefix("done"))
        #expect(elapsed < .seconds(1))
    }

    @Test("Run does not time out after the direct process already exited")
    func runDoesNotTimeOutAfterTheDirectProcessAlreadyExited() async throws {
        let runner = FoundationOpenVAFProcessRunner()
        let command = OpenVAFProcessCommand(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "(sleep 1) & printf done"],
            environment: nil,
            workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            timeout: .milliseconds(50),
            terminationGrace: .milliseconds(10)
        )

        let result = try await runner.run(command)

        #expect(result.exitCode == 0)
        #expect(result.standardOutput == "done")
    }

    @Test("Run maps launch failures")
    func runMapsLaunchFailures() async throws {
        let runner = FoundationOpenVAFProcessRunner()
        let command = OpenVAFProcessCommand(
            executableURL: URL(fileURLWithPath: "/definitely/missing/openvaf"),
            arguments: [],
            environment: nil,
            workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            timeout: .seconds(5),
            terminationGrace: .milliseconds(10)
        )

        do {
            _ = try await runner.run(command)
            Issue.record("Expected launch failure")
        } catch let error as OpenVAFProcessError {
            switch error {
            case .launchFailed(let executablePath, _):
                #expect(executablePath == "/definitely/missing/openvaf")
            case .timedOut, .cancelled:
                Issue.record("Expected launch failure, got \(error)")
            }
        } catch {
            Issue.record("Expected OpenVAFProcessError, got \(error)")
        }
    }

    @Test("Run reports timeout")
    func runReportsTimeout() async throws {
        let runner = FoundationOpenVAFProcessRunner()
        let command = OpenVAFProcessCommand(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "trap '' TERM; echo started; sleep 5"],
            environment: nil,
            workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            timeout: .milliseconds(50),
            terminationGrace: .milliseconds(10)
        )

        do {
            _ = try await runner.run(command)
            Issue.record("Expected process timeout")
        } catch let error as OpenVAFProcessError {
            switch error {
            case .timedOut(let executablePath, let timeout, let standardOutput, _, let startedAt, let finishedAt):
                #expect(executablePath == "/bin/sh")
                #expect(timeout == .milliseconds(50))
                #expect(standardOutput.contains("started"))
                #expect(finishedAt >= startedAt)
            case .launchFailed, .cancelled:
                Issue.record("Expected timeout, got \(error)")
            }
        } catch {
            Issue.record("Expected OpenVAFProcessError, got \(error)")
        }
    }

    @Test("Run reports cancellation")
    func runReportsCancellation() async throws {
        let runner = FoundationOpenVAFProcessRunner()
        let command = OpenVAFProcessCommand(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "sleep 5"],
            environment: nil,
            workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            timeout: .seconds(30),
            terminationGrace: .milliseconds(10)
        )

        let task = Task {
            try await runner.run(command)
        }

        try await ContinuousClock().sleep(for: .milliseconds(50))
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected process cancellation")
        } catch let error as OpenVAFProcessError {
            switch error {
            case .cancelled(let executablePath, _, _, let startedAt, let finishedAt):
                #expect(executablePath == "/bin/sh")
                #expect(finishedAt >= startedAt)
            case .launchFailed, .timedOut:
                Issue.record("Expected cancellation, got \(error)")
            }
        } catch {
            Issue.record("Expected OpenVAFProcessError, got \(error)")
        }
    }

    @Test("Run ignores cancellation after the direct process already exited")
    func runIgnoresCancellationAfterTheDirectProcessAlreadyExited() async throws {
        let runner = FoundationOpenVAFProcessRunner()
        let sandbox = try ProcessRunnerTemporaryDirectory(name: "cancel-after-exit")
        defer { sandbox.remove() }

        let markerURL = sandbox.url.appendingPathComponent("direct-process-exited")
        let script = """
        /usr/bin/perl -e 'while (getppid() == $ARGV[0]) { select undef, undef, undef, 0.005 } open my $fh, ">", $ARGV[1] or die $!; close $fh; sleep 1' $$ "$1" & printf done
        """
        let command = OpenVAFProcessCommand(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script, "openvaf-runner-test", markerURL.path],
            environment: nil,
            workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            timeout: .seconds(5),
            terminationGrace: .milliseconds(10)
        )

        let task = Task {
            try await runner.run(command)
        }
        defer { task.cancel() }

        try await waitUntilFileExists(markerURL)
        task.cancel()

        let result = try await task.value

        #expect(result.exitCode == 0)
        #expect(result.standardOutput == "done")
    }

    private func waitUntilFileExists(_ url: URL) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !FileManager.default.fileExists(atPath: url.path) && clock.now < deadline {
            try await clock.sleep(for: .milliseconds(5))
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            throw ProcessRunnerTestError.markerNotCreated(url.path)
        }
    }
}

private enum ProcessRunnerTestError: Error {
    case markerNotCreated(String)
}

private struct ProcessRunnerTemporaryDirectory {
    let url: URL

    init(name: String) throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenVAFSupportTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            Issue.record("Failed to remove temporary directory \(url.path): \(error)")
        }
    }
}
