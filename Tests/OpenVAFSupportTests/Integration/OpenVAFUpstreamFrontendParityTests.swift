import Foundation
import Testing
@testable import OpenVAFSupport
@testable import VerilogACompiler

#if VerilogACompiler

@Suite("OpenVAF upstream frontend parity", .timeLimit(.minutes(1)))
struct OpenVAFUpstreamFrontendParityTests {
    private static let upstreamRootLocation = locateUpstreamRoot()
    private static let upstreamRootURL = upstreamRootLocation.url
    private static let isEnabled = upstreamRootURL != nil

    #if OpenVAFCLI
    private static let executableLocation = locateExecutable()
    private static let executableURL = executableLocation.url
    private static let isOpenVAFOracleEnabled = upstreamRootURL != nil && executableURL != nil
    #endif

    @Test(
        "Verilog-A compiler frontend values match OpenVAF frontend fixtures",
        .enabled(if: OpenVAFUpstreamFrontendParityTests.isEnabled)
    )
    func compilerFrontendValuesMatchOpenVAFFrontendFixtures() throws {
        let upstreamRootURL = try #require(
            Self.upstreamRootURL,
            "Set OPENVAF_UPSTREAM_ROOT to an OpenVAF repository checkout. \(Self.upstreamRootLocation.failureMessage)"
        )

        for fixture in Self.fixtures {
            let sourceURL = upstreamRootURL.appendingPathComponent(fixture.relativePath)
            #expect(FileManager.default.fileExists(atPath: sourceURL.path), "\(fixture.relativePath) is missing")

            let result = try VerilogACompilerFrontend().parse(contentsOf: sourceURL)
            #expect(result.diagnostics.isEmpty, "Unexpected diagnostics for \(fixture.relativePath)")
            #expect(
                Self.moduleSummaries(in: result) == fixture.modules,
                "Frontend summary mismatch for \(fixture.relativePath)"
            )
        }
    }

    @Test(
        "Verilog-A compiler frontend parameter values exclude upstream constraint clauses",
        .enabled(if: OpenVAFUpstreamFrontendParityTests.isEnabled)
    )
    func compilerFrontendParameterValuesExcludeUpstreamConstraintClauses() throws {
        let upstreamRootURL = try #require(
            Self.upstreamRootURL,
            "Set OPENVAF_UPSTREAM_ROOT to an OpenVAF repository checkout. \(Self.upstreamRootLocation.failureMessage)"
        )
        let sourceURL = upstreamRootURL.appendingPathComponent("openvaf/test_data/osdi/noise.va")
        let result = try VerilogACompilerFrontend().parse(contentsOf: sourceURL)

        #expect(result.diagnostics.isEmpty)
        let module = try #require(result.modules.first)
        var parameterValues: [String: String] = [:]
        for parameter in module.parameters {
            if let valueRange = parameter.valueRange {
                parameterValues[result.source.string(in: parameter.nameRange)] = result.source.string(in: valueRange)
            }
        }

        #expect(parameterValues["pwr"] == "1e-14")
        #expect(parameterValues["flicker_exp"] == "1")
    }

    #if OpenVAFCLI

    @Test(
        "Verilog-A compiler frontend values match upstream fixtures accepted by OpenVAF",
        .enabled(if: OpenVAFUpstreamFrontendParityTests.isOpenVAFOracleEnabled)
    )
    func compilerFrontendValuesMatchUpstreamFixturesAcceptedByOpenVAF() async throws {
        let upstreamRootURL = try #require(
            Self.upstreamRootURL,
            "Set OPENVAF_UPSTREAM_ROOT to an OpenVAF repository checkout. \(Self.upstreamRootLocation.failureMessage)"
        )
        let executableURL = try #require(
            Self.executableURL,
            "OpenVAF oracle comparison requires OPENVAF_BIN or openvaf on PATH. \(Self.executableLocation.failureMessage)"
        )
        let sandbox = try UpstreamParityTemporaryDirectory(name: "upstream-openvaf-oracle")
        defer { sandbox.remove() }

        let compiler = CommandLineOpenVAFCompiler(configuration: OpenVAFConfiguration(
            executable: .path(executableURL.path),
            compileTimeout: .seconds(30),
            availabilityTimeout: .seconds(10),
            processEnvironment: ProcessInfo.processInfo.environment
        ))

        for relativePath in Self.openVAFAcceptedRelativePaths {
            let fixture = try #require(
                Self.fixtures.first { $0.relativePath == relativePath },
                "Missing expected value manifest for \(relativePath)"
            )
            let sourceURL = upstreamRootURL.appendingPathComponent(relativePath)
            let result = try VerilogACompilerFrontend().parse(contentsOf: sourceURL)
            #expect(result.diagnostics.isEmpty, "Unexpected diagnostics for \(relativePath)")
            #expect(
                Self.moduleSummaries(in: result) == fixture.modules,
                "Frontend summary mismatch for \(relativePath)"
            )

            let fileStem = sourceURL.deletingPathExtension().lastPathComponent
            let artifact = try await compiler.compile(OpenVAFCompilationRequest(
                sourceURL: sourceURL,
                outputDirectory: sandbox.url.appendingPathComponent(fileStem),
                outputFileName: "\(fileStem).osdi"
            ))

            #expect(artifact.exitCode == 0)
            #expect(artifact.outputURL.lastPathComponent == "\(fileStem).osdi")
            #expect(FileManager.default.fileExists(atPath: artifact.outputURL.path))
        }
    }

    #endif

    private static func locateUpstreamRoot() -> UpstreamRootLocation {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["OPENVAF_UPSTREAM_ROOT"],
              !path.isEmpty else {
            return .missing("OPENVAF_UPSTREAM_ROOT is not set")
        }

        let url = URL(fileURLWithPath: path).standardizedFileURL
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .missing("OPENVAF_UPSTREAM_ROOT is not an existing directory: \(url.path)")
        }

        let marker = url.appendingPathComponent("openvaf/test_data")
        guard FileManager.default.fileExists(atPath: marker.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .missing("OPENVAF_UPSTREAM_ROOT must point at an OpenVAF repository checkout: \(url.path)")
        }

        return .resolved(url)
    }

    private static func moduleSummaries(in result: VerilogAParseResult) -> [ModuleSummary] {
        result.modules.map { module in
            ModuleSummary(
                name: module.name(in: result.source),
                ports: module.portNames(in: result.source),
                declarations: declarationSummaries(module.declarations, source: result.source),
                parameters: module.parameters.map { parameter in
                    result.source.string(in: parameter.nameRange)
                },
                functions: module.functions.map { function in
                    FunctionSummary(
                        name: function.name(in: result.source),
                        returnType: function.returnTypeRange.map { result.source.string(in: $0) },
                        declarations: declarationSummaries(function.declarations, source: result.source)
                    )
                },
                analogBlockCount: module.analogBlockRanges.count
            )
        }
    }

    #if OpenVAFCLI

    private static func locateExecutable() -> UpstreamExecutableLocation {
        do {
            let url = try PATHOpenVAFExecutableResolver().resolve(
                .environment(variable: "OPENVAF_BIN", fallbackName: "openvaf"),
                environment: ProcessInfo.processInfo.environment
            )
            return .resolved(url)
        } catch {
            return .failed(error)
        }
    }

    #endif

    private static func declarationSummaries(
        _ declarations: [VerilogADeclaration],
        source: VerilogASourceBuffer
    ) -> [DeclarationSummary] {
        declarations.map { declaration in
            DeclarationSummary(
                kind: declaration.kind,
                names: declaration.nameRanges.map { source.string(in: $0) }
            )
        }
    }

    private static let fixtures: [UpstreamFixture] = [
        UpstreamFixture(
            relativePath: "openvaf/test_data/ast/ports.va",
            modules: [
                ModuleSummary(name: "test1"),
                ModuleSummary(
                    name: "test2",
                    ports: ["a", "b", "c", "d", "e", "f", "g"],
                    declarations: [
                        DeclarationSummary(kind: .output, names: ["a"]),
                        DeclarationSummary(kind: .input, names: ["b"]),
                        DeclarationSummary(kind: .inoutPort, names: ["c"]),
                        DeclarationSummary(kind: .inoutPort, names: ["d"]),
                        DeclarationSummary(kind: .output, names: ["e", "f"]),
                        DeclarationSummary(kind: .inoutPort, names: ["g"]),
                    ]
                ),
                ModuleSummary(
                    name: "test3",
                    ports: ["a", "b", "c", "d", "e", "f"],
                    declarations: [
                        DeclarationSummary(kind: .output, names: ["a", "b"]),
                        DeclarationSummary(kind: .input, names: ["c", "d", "e"]),
                        DeclarationSummary(kind: .inoutPort, names: ["f"]),
                    ]
                ),
            ]
        ),
        UpstreamFixture(
            relativePath: "openvaf/test_data/ast/branches.va",
            modules: [
                ModuleSummary(
                    name: "test",
                    ports: ["a", "b"],
                    declarations: [
                        DeclarationSummary(kind: .inoutPort, names: ["a"]),
                        DeclarationSummary(kind: .input, names: ["b"]),
                        DeclarationSummary(kind: .electrical, names: ["a", "b"]),
                        DeclarationSummary(kind: .branch, names: ["ab1", "ab2"]),
                        DeclarationSummary(kind: .branch, names: ["a_gnd"]),
                        DeclarationSummary(kind: .branch, names: ["port_flow_b"]),
                    ],
                    analogBlockCount: 1
                ),
            ]
        ),
        UpstreamFixture(
            relativePath: "openvaf/test_data/ast/functions.va",
            modules: [
                ModuleSummary(
                    name: "test",
                    functions: [
                        FunctionSummary(
                            name: "hypsmooth",
                            returnType: "real",
                            declarations: [
                                DeclarationSummary(kind: .input, names: ["x", "c"]),
                                DeclarationSummary(kind: .output, names: ["y", "z"]),
                                DeclarationSummary(kind: .inoutPort, names: ["m", "l"]),
                                DeclarationSummary(kind: .real, names: ["x", "c"]),
                                DeclarationSummary(kind: .integer, names: ["m", "z"]),
                                DeclarationSummary(kind: .string, names: ["l", "y"]),
                            ]
                        ),
                    ]
                ),
            ]
        ),
        UpstreamFixture(
            relativePath: "openvaf/test_data/ast/variables.va",
            modules: [
                ModuleSummary(
                    name: "test",
                    declarations: [
                        DeclarationSummary(kind: .real, names: ["x"]),
                        DeclarationSummary(kind: .integer, names: ["y", "z"]),
                        DeclarationSummary(kind: .real, names: ["t"]),
                        DeclarationSummary(kind: .integer, names: ["rt"]),
                    ],
                    analogBlockCount: 1
                ),
            ]
        ),
        UpstreamFixture(
            relativePath: "openvaf/test_data/item_tree/branches.va",
            modules: [
                ModuleSummary(
                    name: "test",
                    ports: ["a"],
                    declarations: [
                        DeclarationSummary(kind: .electrical, names: ["a"]),
                        DeclarationSummary(kind: .inoutPort, names: ["a"]),
                        DeclarationSummary(kind: .electrical, names: ["c"]),
                        DeclarationSummary(kind: .branch, names: ["br_ac"]),
                        DeclarationSummary(kind: .branch, names: ["br_a_port"]),
                    ]
                ),
            ]
        ),
        UpstreamFixture(
            relativePath: "openvaf/test_data/item_tree/function.va",
            modules: [
                ModuleSummary(
                    name: "test",
                    functions: [
                        FunctionSummary(
                            name: "hypsmooth",
                            returnType: "real",
                            declarations: [
                                DeclarationSummary(kind: .input, names: ["x", "c"]),
                                DeclarationSummary(kind: .output, names: ["y", "z"]),
                                DeclarationSummary(kind: .inoutPort, names: ["m", "l"]),
                                DeclarationSummary(kind: .real, names: ["x", "c"]),
                                DeclarationSummary(kind: .integer, names: ["m", "z"]),
                                DeclarationSummary(kind: .string, names: ["l", "y"]),
                            ]
                        ),
                    ]
                ),
            ]
        ),
        UpstreamFixture(
            relativePath: "openvaf/test_data/item_tree/nodes.va",
            modules: [
                ModuleSummary(
                    name: "test",
                    ports: ["foo", "test"],
                    declarations: [
                        DeclarationSummary(kind: .electrical, names: ["foo"]),
                        DeclarationSummary(kind: .inoutPort, names: ["foo"]),
                        DeclarationSummary(kind: .electrical, names: ["bar"]),
                        DeclarationSummary(kind: .ground, names: ["bar"]),
                        DeclarationSummary(kind: .inoutPort, names: ["test"]),
                    ]
                ),
            ]
        ),
        UpstreamFixture(
            relativePath: "openvaf/test_data/item_tree/blocks.va",
            modules: [
                ModuleSummary(
                    name: "test",
                    parameters: ["foo", "bar"],
                    analogBlockCount: 2
                ),
            ]
        ),
        UpstreamFixture(
            relativePath: "openvaf/test_data/body/function.va",
            modules: [
                ModuleSummary(name: "bar"),
                ModuleSummary(
                    name: "test",
                    declarations: [
                        DeclarationSummary(kind: .real, names: ["bar"]),
                    ],
                    parameters: ["foo"],
                    functions: [
                        FunctionSummary(
                            name: "test",
                            returnType: "real",
                            declarations: [
                                DeclarationSummary(kind: .input, names: ["x"]),
                                DeclarationSummary(kind: .input, names: ["y"]),
                                DeclarationSummary(kind: .real, names: ["x", "y"]),
                            ]
                        ),
                    ]
                ),
            ]
        ),
        UpstreamFixture(
            relativePath: "openvaf/test_data/body/branch_access.va",
            modules: [
                ModuleSummary(
                    name: "test",
                    analogBlockCount: 1
                ),
            ]
        ),
        UpstreamFixture(
            relativePath: "openvaf/test_data/body/nested_blocks.va",
            modules: [
                ModuleSummary(
                    name: "test",
                    analogBlockCount: 1
                ),
            ]
        ),
        UpstreamFixture(
            relativePath: "openvaf/test_data/mir/analog_initial.va",
            modules: [
                ModuleSummary(
                    name: "test",
                    declarations: [
                        DeclarationSummary(kind: .electrical, names: ["a", "b"]),
                        DeclarationSummary(kind: .real, names: ["test"]),
                        DeclarationSummary(kind: .real, names: ["test2"]),
                    ],
                    parameters: ["foo"],
                    analogBlockCount: 2
                ),
            ]
        ),
        UpstreamFixture(
            relativePath: "openvaf/test_data/mir/case.va",
            modules: [
                ModuleSummary(
                    name: "test",
                    declarations: [
                        DeclarationSummary(kind: .real, names: ["test"]),
                        DeclarationSummary(kind: .real, names: ["test2"]),
                    ],
                    parameters: ["foo", "bar"],
                    analogBlockCount: 1
                ),
            ]
        ),
        UpstreamFixture(
            relativePath: "openvaf/test_data/syn_ui/module_overwrite_unknown_lint.va",
            modules: [
                ModuleSummary(name: "test", parameters: ["bar"]),
                ModuleSummary(name: "test", parameters: ["bar"]),
                ModuleSummary(name: "test", parameters: ["bar"]),
            ]
        ),
        UpstreamFixture(
            relativePath: "openvaf/test_data/syn_ui/overwrite_reserved_ident.va",
            modules: [
                ModuleSummary(name: "cmos"),
                ModuleSummary(name: "cmos"),
                ModuleSummary(name: "cmos"),
            ]
        ),
        UpstreamFixture(
            relativePath: "openvaf/test_data/syn_ui/reserved_ident_nested.va",
            modules: [
                ModuleSummary(name: "foo", analogBlockCount: 1),
                ModuleSummary(name: "foo", parameters: ["nmos"], analogBlockCount: 1),
            ]
        ),
        UpstreamFixture(
            relativePath: "openvaf/test_data/syn_ui/unknown_lint.va",
            modules: [
                ModuleSummary(name: "test", parameters: ["bar"]),
            ]
        ),
        UpstreamFixture(
            relativePath: "openvaf/test_data/ui/ddx.va",
            modules: [
                ModuleSummary(
                    name: "diode",
                    ports: ["a", "c"],
                    declarations: [
                        DeclarationSummary(kind: .real, names: ["x"]),
                        DeclarationSummary(kind: .inoutPort, names: ["c"]),
                        DeclarationSummary(kind: .inoutPort, names: ["a"]),
                        DeclarationSummary(kind: .electrical, names: ["a"]),
                        DeclarationSummary(kind: .electrical, names: ["c"]),
                        DeclarationSummary(kind: .branch, names: ["br_ac"]),
                        DeclarationSummary(kind: .real, names: ["foo"]),
                    ],
                    analogBlockCount: 1
                ),
            ]
        ),
        UpstreamFixture(
            relativePath: "openvaf/test_data/ui/formatting.va",
            modules: [
                ModuleSummary(name: "diode", analogBlockCount: 1),
            ]
        ),
        UpstreamFixture(
            relativePath: "openvaf/test_data/ui/function.va",
            modules: [
                ModuleSummary(
                    name: "diode",
                    functions: [
                        FunctionSummary(
                            name: "test",
                            returnType: "real",
                            declarations: [
                                DeclarationSummary(kind: .input, names: ["x", "y"]),
                                DeclarationSummary(kind: .real, names: ["x", "y"]),
                            ]
                        ),
                    ]
                ),
            ]
        ),
        UpstreamFixture(
            relativePath: "openvaf/test_data/ui/function_resolve.va",
            modules: [
                ModuleSummary(
                    name: "test",
                    functions: [
                        FunctionSummary(
                            name: "lexp",
                            returnType: "real",
                            declarations: [
                                DeclarationSummary(kind: .input, names: ["x"]),
                                DeclarationSummary(kind: .real, names: ["x"]),
                            ]
                        ),
                        FunctionSummary(
                            name: "lln",
                            returnType: "real",
                            declarations: [
                                DeclarationSummary(kind: .input, names: ["x"]),
                                DeclarationSummary(kind: .real, names: ["x"]),
                            ]
                        ),
                        FunctionSummary(
                            name: "hypsmooth",
                            returnType: "real",
                            declarations: [
                                DeclarationSummary(kind: .input, names: ["x", "c"]),
                                DeclarationSummary(kind: .real, names: ["x", "c"]),
                            ]
                        ),
                        FunctionSummary(
                            name: "hypmax",
                            returnType: "real",
                            declarations: [
                                DeclarationSummary(kind: .input, names: ["x", "xmin", "c"]),
                                DeclarationSummary(kind: .real, names: ["x", "xmin", "c"]),
                            ]
                        ),
                        FunctionSummary(
                            name: "Tempdep",
                            returnType: "real",
                            declarations: [
                                DeclarationSummary(kind: .input, names: ["PARAML", "PARAMT", "DELTEMP", "TEMPMOD"]),
                                DeclarationSummary(kind: .real, names: ["PARAML", "PARAMT", "DELTEMP", "TEMPMOD"]),
                            ]
                        ),
                        FunctionSummary(
                            name: "Tempdep2",
                            returnType: "real",
                            declarations: [
                                DeclarationSummary(kind: .input, names: ["PARAML", "PARAMT", "DELTEMP", "TEMPMOD"]),
                                DeclarationSummary(kind: .real, names: ["PARAML", "PARAMT", "DELTEMP", "TEMPMOD"]),
                            ]
                        ),
                    ]
                ),
            ]
        ),
        UpstreamFixture(
            relativePath: "openvaf/test_data/ui/param_ty.va",
            modules: [
                ModuleSummary(
                    name: "param_ty",
                    declarations: [
                        DeclarationSummary(kind: .real, names: ["err", "ok"]),
                    ],
                    parameters: [
                        "explicit_real1",
                        "explicit_real2",
                        "explicit_int1",
                        "explicit_int2",
                        "infer_int",
                        "infer_real",
                        "infer_string",
                    ],
                    analogBlockCount: 1
                ),
            ]
        ),
        UpstreamFixture(
            relativePath: "openvaf/test_data/ui/port_without_direction.va",
            modules: [
                ModuleSummary(
                    name: "error",
                    ports: ["x"],
                    declarations: [
                        DeclarationSummary(kind: .electrical, names: ["x"]),
                    ]
                ),
                ModuleSummary(
                    name: "warning",
                    ports: ["x"],
                    declarations: [
                        DeclarationSummary(kind: .electrical, names: ["x"]),
                    ]
                ),
            ]
        ),
        UpstreamFixture(
            relativePath: "openvaf/test_data/osdi/diode_lim.va",
            modules: [
                ModuleSummary(
                    name: "diode_va",
                    ports: ["A", "C", "dT"],
                    declarations: [
                        DeclarationSummary(kind: .inoutPort, names: ["A", "C", "dT"]),
                        DeclarationSummary(kind: .electrical, names: ["A", "C", "CI"]),
                        DeclarationSummary(kind: .thermal, names: ["dT"]),
                        DeclarationSummary(kind: .branch, names: ["br_a_ci"]),
                        DeclarationSummary(kind: .branch, names: ["br_ci_c"]),
                        DeclarationSummary(kind: .branch, names: ["br_sht"]),
                        DeclarationSummary(kind: .real, names: ["vd", "vd_smooth", "vr", "id", "qd", "ist"]),
                        DeclarationSummary(kind: .real, names: ["vt", "x", "y", "vf", "tdev", "pterm", "rs_t", "rth_t", "is_t"]),
                    ],
                    parameters: [
                        "is",
                        "rs",
                        "zetars",
                        "n",
                        "cj0",
                        "vj",
                        "m",
                        "rth",
                        "zetarth",
                        "zetais",
                        "ea",
                        "tnom",
                        "minr",
                    ],
                    analogBlockCount: 1
                ),
            ]
        ),
        UpstreamFixture(
            relativePath: "openvaf/test_data/osdi/noise.va",
            modules: [
                ModuleSummary(
                    name: "noise_test",
                    ports: ["a", "c"],
                    declarations: [
                        DeclarationSummary(kind: .inoutPort, names: ["a"]),
                        DeclarationSummary(kind: .inoutPort, names: ["c"]),
                    ],
                    parameters: ["pwr", "flicker_exp"],
                    analogBlockCount: 1
                ),
            ]
        ),
    ]

    private static let openVAFAcceptedRelativePaths: [String] = [
        "openvaf/test_data/ast/functions.va",
        "openvaf/test_data/item_tree/blocks.va",
        "openvaf/test_data/item_tree/function.va",
        "openvaf/test_data/body/function.va",
        "openvaf/test_data/mir/analog_initial.va",
        "openvaf/test_data/mir/case.va",
        "openvaf/test_data/osdi/noise.va",
    ]
}

private struct UpstreamFixture: Sendable {
    let relativePath: String
    let modules: [ModuleSummary]
}

private struct ModuleSummary: Sendable, Equatable {
    let name: String
    let ports: [String]
    let declarations: [DeclarationSummary]
    let parameters: [String]
    let functions: [FunctionSummary]
    let analogBlockCount: Int

    init(
        name: String,
        ports: [String] = [],
        declarations: [DeclarationSummary] = [],
        parameters: [String] = [],
        functions: [FunctionSummary] = [],
        analogBlockCount: Int = 0
    ) {
        self.name = name
        self.ports = ports
        self.declarations = declarations
        self.parameters = parameters
        self.functions = functions
        self.analogBlockCount = analogBlockCount
    }
}

private struct FunctionSummary: Sendable, Equatable {
    let name: String
    let returnType: String?
    let declarations: [DeclarationSummary]
}

private struct DeclarationSummary: Sendable, Equatable {
    let kind: VerilogADeclarationKind
    let names: [String]
}

private enum UpstreamRootLocation: Sendable {
    case resolved(URL)
    case missing(String)

    var url: URL? {
        switch self {
        case .resolved(let url):
            return url
        case .missing:
            return nil
        }
    }

    var failureMessage: String {
        switch self {
        case .resolved:
            return ""
        case .missing(let message):
            return message
        }
    }
}

#if OpenVAFCLI

private enum UpstreamExecutableLocation: Sendable {
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

private struct UpstreamParityTemporaryDirectory {
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

#endif
