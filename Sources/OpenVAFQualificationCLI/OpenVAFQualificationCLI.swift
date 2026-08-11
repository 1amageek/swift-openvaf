import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFoundation
import Foundation
import OpenVAFSupport
import VerilogACompiler

#if OpenVAFCLI && VerilogACompiler

@main
struct OpenVAFQualificationCLI {
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment
        let executablePath = try required("OPENVAF_BIN", environment: environment)
        let expectedDigest = try required(
            "OPENVAF_EXPECTED_BINARY_SHA256",
            environment: environment
        )
        let evidenceRootPath = try required(
            "OPENVAF_EVIDENCE_ROOT",
            environment: environment
        )
        let upstreamRootPath = try required(
            "OPENVAF_UPSTREAM_ROOT",
            environment: environment
        )
        let executableURL = URL(fileURLWithPath: executablePath).standardizedFileURL
        let evidenceRoot = URL(
            fileURLWithPath: evidenceRootPath,
            isDirectory: true
        ).standardizedFileURL
        try FileManager.default.createDirectory(
            at: evidenceRoot,
            withIntermediateDirectories: true
        )

        let executableData = try Data(
            contentsOf: executableURL,
            options: .mappedIfSafe
        )
        let actualDigest = try SHA256ContentDigester()
            .digest(data: executableData)
            .hexadecimalValue
        guard actualDigest.caseInsensitiveCompare(expectedDigest) == .orderedSame else {
            throw OpenVAFQualificationError.executableDigestMismatch(
                expected: expectedDigest,
                actual: actualDigest
            )
        }

        let successResultPath = try await runSuccess(
            executableURL: executableURL,
            evidenceRoot: evidenceRoot,
            environment: environment
        )
        let failureResultPath = try await runFailure(
            executableURL: executableURL,
            evidenceRoot: evidenceRoot,
            environment: environment
        )
        let timeoutResultPath = try await runTimeout(
            executableURL: executableURL,
            evidenceRoot: evidenceRoot,
            environment: environment
        )
        let upstreamResultPaths = try await runUpstreamCorpus(
            executableURL: executableURL,
            evidenceRoot: evidenceRoot,
            upstreamRoot: URL(
                fileURLWithPath: upstreamRootPath,
                isDirectory: true
            ).standardizedFileURL,
            environment: environment
        )
        let report = OpenVAFQualificationReport(
            executablePath: executableURL.path,
            executableSHA256: actualDigest,
            successResultPath: successResultPath,
            failureResultPath: failureResultPath,
            timeoutResultPath: timeoutResultPath,
            upstreamResultPaths: upstreamResultPaths
        )
        try encode(report).write(
            to: evidenceRoot.appendingPathComponent("qualification-report.json"),
            options: .atomic
        )
    }

    private static func runSuccess(
        executableURL: URL,
        evidenceRoot: URL,
        environment: [String: String]
    ) async throws -> String {
        let root = evidenceRoot.appendingPathComponent(
            "successful-compilation",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("resistor.va")
        try Data(resistorModel.utf8).write(to: sourceURL, options: .atomic)
        let compiler = compiler(
            executableURL: executableURL,
            environment: environment,
            compileTimeout: .seconds(30)
        )
        let result = try await compiler.compile(OpenVAFCompilationRequest(
            sourceURL: sourceURL,
            outputDirectory: root.appendingPathComponent("output"),
            outputFileName: "resistor.osdi"
        ))
        guard let output = result.outputArtifact,
              output.byteCount > 0 else {
            throw OpenVAFQualificationError.unexpectedCompilationError(
                "successful compilation did not retain non-empty OSDI bytes"
            )
        }
        let path = root.appendingPathComponent("result.json")
        try encode(result).write(to: path, options: .atomic)
        return path.path
    }

    private static func runFailure(
        executableURL: URL,
        evidenceRoot: URL,
        environment: [String: String]
    ) async throws -> String {
        let root = evidenceRoot.appendingPathComponent(
            "failed-compilation",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("invalid.va")
        try Data(invalidModel.utf8).write(to: sourceURL, options: .atomic)
        let compiler = compiler(
            executableURL: executableURL,
            environment: environment,
            compileTimeout: .seconds(30)
        )
        do {
            _ = try await compiler.compile(OpenVAFCompilationRequest(
                sourceURL: sourceURL,
                outputDirectory: root.appendingPathComponent("output"),
                outputFileName: "invalid.osdi"
            ))
            throw OpenVAFQualificationError.expectedCompilationFailure
        } catch let error as OpenVAFQualificationError {
            throw error
        } catch let error as OpenVAFError {
            guard case .compilationFailed(let failure) = error else {
                throw OpenVAFQualificationError.unexpectedCompilationError(
                    error.localizedDescription
                )
            }
            let path = root.appendingPathComponent("failure.json")
            try encode(failure).write(to: path, options: .atomic)
            return path.path
        }
    }

    private static func runTimeout(
        executableURL: URL,
        evidenceRoot: URL,
        environment: [String: String]
    ) async throws -> String {
        let root = evidenceRoot.appendingPathComponent(
            "timed-out-compilation",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("timeout.va")
        try Data(resistorModel.utf8).write(to: sourceURL, options: .atomic)
        let compiler = compiler(
            executableURL: executableURL,
            environment: environment,
            compileTimeout: .nanoseconds(1)
        )
        do {
            _ = try await compiler.compile(OpenVAFCompilationRequest(
                sourceURL: sourceURL,
                outputDirectory: root.appendingPathComponent("output"),
                outputFileName: "timeout.osdi"
            ))
            throw OpenVAFQualificationError.expectedTimeout
        } catch let error as OpenVAFQualificationError {
            throw error
        } catch let error as OpenVAFError {
            guard case .compilationTimedOut(let failure, _) = error else {
                throw OpenVAFQualificationError.unexpectedCompilationError(
                    error.localizedDescription
                )
            }
            let path = root.appendingPathComponent("timeout.json")
            try encode(failure).write(to: path, options: .atomic)
            return path.path
        }
    }

    private static func runUpstreamCorpus(
        executableURL: URL,
        evidenceRoot: URL,
        upstreamRoot: URL,
        environment: [String: String]
    ) async throws -> [String] {
        let outputRoot = evidenceRoot.appendingPathComponent(
            "upstream-corpus",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outputRoot,
            withIntermediateDirectories: true
        )
        let compiler = compiler(
            executableURL: executableURL,
            environment: environment,
            compileTimeout: .seconds(30)
        )
        var resultPaths: [String] = []
        resultPaths.reserveCapacity(upstreamRelativePaths.count)
        for (index, relativePath) in upstreamRelativePaths.enumerated() {
            let sourceURL = upstreamRoot.appendingPathComponent(relativePath)
            let parseResult = try VerilogACompilerFrontend().parse(
                contentsOf: sourceURL
            )
            guard parseResult.diagnostics.isEmpty else {
                throw OpenVAFQualificationError.unexpectedCompilationError(
                    "frontend diagnostics were produced for \(relativePath)"
                )
            }
            let caseRoot = outputRoot.appendingPathComponent(
                "case-\(index + 1)",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: caseRoot,
                withIntermediateDirectories: true
            )
            let result = try await compiler.compile(OpenVAFCompilationRequest(
                sourceURL: sourceURL,
                outputDirectory: caseRoot.appendingPathComponent("output"),
                outputFileName: "upstream-\(index + 1).osdi"
            ))
            guard let output = result.outputArtifact, output.byteCount > 0 else {
                throw OpenVAFQualificationError.unexpectedCompilationError(
                    "upstream case \(relativePath) did not produce non-empty OSDI bytes"
                )
            }
            let resultPath = caseRoot.appendingPathComponent("result.json")
            try encode(result).write(to: resultPath, options: .atomic)
            resultPaths.append(resultPath.path)
        }
        return resultPaths
    }

    private static func compiler(
        executableURL: URL,
        environment: [String: String],
        compileTimeout: Duration
    ) -> CommandLineOpenVAFCompiler {
        CommandLineOpenVAFCompiler(configuration: OpenVAFConfiguration(
            executable: .path(executableURL.path),
            compileTimeout: compileTimeout,
            availabilityTimeout: .seconds(10),
            processEnvironment: environment
        ))
    }

    private static func required(
        _ name: String,
        environment: [String: String]
    ) throws -> String {
        guard let value = environment[name], !value.isEmpty else {
            throw OpenVAFQualificationError.environmentMissing(name)
        }
        return value
    }

    private static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    private static let resistorModel = """
`include "disciplines.vams"

module resistor(p, n);
    inout p, n;
    electrical p, n;

    parameter real resistance = 1.0;

    analog begin
        I(p, n) <+ V(p, n) / resistance;
    end
endmodule
"""

    private static let invalidModel = """
`include "disciplines.vams"

module invalid(p, n);
    inout p, n;
    electrical p, n;

    analog begin
        I(p, n) <+ ;
    end
endmodule
"""

    private static let upstreamRelativePaths = [
        "openvaf/test_data/ast/functions.va",
        "openvaf/test_data/item_tree/blocks.va",
        "openvaf/test_data/item_tree/function.va",
        "openvaf/test_data/body/function.va",
        "openvaf/test_data/mir/analog_initial.va",
        "openvaf/test_data/mir/case.va",
        "openvaf/test_data/osdi/noise.va",
    ]
}

#else

@main
struct OpenVAFQualificationCLI {
    static func main() throws {
        throw OpenVAFQualificationError.requiredTraitsMissing
    }
}

#endif
