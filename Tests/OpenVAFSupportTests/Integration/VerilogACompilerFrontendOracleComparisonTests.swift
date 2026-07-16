import CircuiteFoundation
import Foundation
import Testing
@testable import OpenVAFSupport
@testable import VerilogACompiler

#if OpenVAFCLI && VerilogACompiler

@Suite("Verilog-A compiler frontend oracle comparison", .timeLimit(.minutes(2)))
struct VerilogACompilerFrontendOracleComparisonTests {
    private static let environment = ProcessInfo.processInfo.environment
    private static let executableLocation = locateExecutable(environment: environment)
    private static let executableURL = executableLocation.url
    private static let isExplicitlyRequested = environment["OPENVAF_ORACLE"] == "1"
        || environment["OPENVAF_E2E"] == "1"
    private static let isEnabled = isExplicitlyRequested

    @Test(
        "Parser results match sources accepted by OpenVAF",
        .enabled(if: VerilogACompilerFrontendOracleComparisonTests.isEnabled)
    )
    func parserResultsMatchSourcesAcceptedByOpenVAF() async throws {
        let executableURL = try #require(
            Self.executableURL,
            "OpenVAF oracle comparison requires OPENVAF_BIN or openvaf on PATH. \(Self.executableLocation.failureMessage)"
        )

        let sandbox = try OracleTemporaryDirectory(name: "swift-openvaf-oracle")
        defer { sandbox.remove() }

        let commandLineCompiler = CommandLineOpenVAFCompiler(configuration: OpenVAFConfiguration(
            executable: .path(executableURL.path),
            compileTimeout: .seconds(30),
            availabilityTimeout: .seconds(10),
            processEnvironment: Self.environment
        ))

        for fixture in Self.acceptedFixtures {
            let sourceURL = sandbox.url.appendingPathComponent("\(fixture.fileStem).va")
            try Data(fixture.source.utf8).write(to: sourceURL)

            let parseResult = try VerilogACompilerFrontend().parse(contentsOf: sourceURL)
            #expect(parseResult.diagnostics.isEmpty, "Unexpected diagnostics for \(fixture.fileStem)")
            #expect(parseResult.modules.count == 1, "Unexpected module count for \(fixture.fileStem)")
            let module = try #require(parseResult.modules.first)
            #expect(module.name(in: parseResult.source) == fixture.moduleName)
            #expect(module.portNames(in: parseResult.source) == fixture.portNames)
            #expect(module.parameters.count == fixture.parameterCount)
            #expect(module.analogBlockRanges.count == fixture.analogBlockCount)

            let artifact = try await commandLineCompiler.compile(OpenVAFCompilationRequest(
                sourceURL: sourceURL,
                outputDirectory: sandbox.url.appendingPathComponent("out-\(fixture.fileStem)"),
                outputFileName: "\(fixture.fileStem).osdi"
            ))

            let outputArtifact = try #require(artifact.outputArtifact)
            let outputURL = try outputArtifact.locator.location.resolvedFileURL()
            #expect(artifact.exitCode == 0)
            #expect(outputURL.lastPathComponent == "\(fixture.fileStem).osdi")
            #expect(FileManager.default.fileExists(atPath: outputURL.path))
        }
    }

    private static func locateExecutable(environment: [String: String]) -> OracleExecutableLocation {
        do {
            let url = try PATHOpenVAFExecutableResolver().resolve(
                .environment(variable: "OPENVAF_BIN", fallbackName: "openvaf"),
                environment: environment
            )
            return .resolved(url)
        } catch {
            return .failed(error)
        }
    }

    private static let acceptedFixtures: [OracleAcceptedFixture] = [
        OracleAcceptedFixture(
            fileStem: "resistor",
            moduleName: "resistor",
            portNames: ["p", "n"],
            parameterCount: 1,
            analogBlockCount: 1,
            source: Self.resistorModel
        ),
        OracleAcceptedFixture(
            fileStem: "current_source",
            moduleName: "current_source",
            portNames: ["p", "n"],
            parameterCount: 1,
            analogBlockCount: 1,
            source: Self.currentSourceModel
        ),
        OracleAcceptedFixture(
            fileStem: "voltage_source",
            moduleName: "voltage_source",
            portNames: ["p", "n"],
            parameterCount: 1,
            analogBlockCount: 1,
            source: Self.voltageSourceModel
        ),
        OracleAcceptedFixture(
            fileStem: "vccs",
            moduleName: "vccs",
            portNames: ["outp", "outn", "inp", "inn"],
            parameterCount: 1,
            analogBlockCount: 1,
            source: Self.vccsModel
        ),
        OracleAcceptedFixture(
            fileStem: "inline_ports",
            moduleName: "inline_ports",
            portNames: ["out", "input_node", "reference"],
            parameterCount: 1,
            analogBlockCount: 1,
            source: Self.inlinePortsModel
        ),
        OracleAcceptedFixture(
            fileStem: "conditional_current",
            moduleName: "conditional_current",
            portNames: ["p", "n"],
            parameterCount: 1,
            analogBlockCount: 1,
            source: Self.conditionalCurrentModel
        ),
    ]

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

    private static let currentSourceModel = """
`include "disciplines.vams"

module current_source(p, n);
    inout p, n;
    electrical p, n;

    parameter real current = 1.0e-3;

    analog begin
        I(p, n) <+ current;
    end
endmodule
"""

    private static let voltageSourceModel = """
`include "disciplines.vams"

module voltage_source(p, n);
    inout p, n;
    electrical p, n;

    parameter real voltage = 1.2;

    analog begin
        V(p, n) <+ voltage;
    end
endmodule
"""

    private static let vccsModel = """
`include "disciplines.vams"

module vccs(outp, outn, inp, inn);
    inout outp, outn, inp, inn;
    electrical outp, outn, inp, inn;

    parameter real gain = 2.0;

    analog begin
        I(outp, outn) <+ gain * V(inp, inn);
    end
endmodule
"""

    private static let inlinePortsModel = """
`include "disciplines.vams"

module inline_ports(inout electrical out, input electrical input_node, (* compact *) inout electrical ground reference);
    parameter real gain = 1.0;

    analog begin
        I(out, reference) <+ gain * V(input_node, reference);
    end
endmodule
"""

    private static let conditionalCurrentModel = """
`include "disciplines.vams"

module conditional_current(p, n);
    inout p, n;
    electrical p, n;

    parameter real current = 1.0;

    analog if (current > 0) begin
        I(p, n) <+ current;
        I(p, n) <+ current / 2;
    end else begin
        I(p, n) <+ 0;
    end
endmodule
"""
}

private struct OracleAcceptedFixture: Sendable {
    let fileStem: String
    let moduleName: String
    let portNames: [String]
    let parameterCount: Int
    let analogBlockCount: Int
    let source: String
}

private enum OracleExecutableLocation: Sendable {
    case resolved(URL)
    case failed(OpenVAFError)

    var url: URL? {
        switch self {
        case .resolved(let url):
            return url
        case .failed:
            return nil
        }
    }

    var failureMessage: String {
        switch self {
        case .resolved:
            return ""
        case .failed(let error):
            return error.localizedDescription
        }
    }
}

#endif

private struct OracleTemporaryDirectory {
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
