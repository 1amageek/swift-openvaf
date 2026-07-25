# swift-openvaf Remaining Tasks

Updated: 2026-07-26

The external OpenVAF wrapper and the in-process source-range structural
frontend are implemented. The wrapper does not bundle or embed OpenVAF.

## Remaining tasks

| ID | Priority | Owner | Task | Exit criteria |
|---|---|---|---|---|
| OVAF-2 | P2 | VerilogACompiler | Expand the structural frontend into deeper Verilog-A semantic analysis or code generation when required by consumers. | The supported semantic subset is explicitly versioned; types, contributions, functions, parameters, analog behavior, diagnostics, and source ranges have deterministic IR and independent oracle fixtures; unsupported semantics remain explicit. |

## Completed P1 tasks

| ID | Completed | Evidence |
|---|---|---|
| OVAF-1 | 2026-07-26 | Hosted CI run `30179955107` passed the pinned Linux OpenVAF installation and SHA verification, production-API Verilog-A-to-OSDI qualification, failure/timeout paths, retained evidence upload, SwiftPM traits, Thread Sanitizer, and pinned frontend parity without skip-based success. |

## External prerequisites

An OpenVAF executable is an external tool. The macOS Docker shim produces Linux
x86-64 OSDI artifacts and is suitable for compiler/oracle validation, not native
macOS model loading.

## Evidence reviewed

- `README.md`
- `Package.swift`
- GitHub CI workflow
- Hosted CI run `30179955107`
- External compiler, process, resolver, frontend, parser, and oracle test paths
- `Sources` incomplete-implementation marker scan
