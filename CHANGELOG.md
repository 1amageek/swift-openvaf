# Changelog

All notable changes to this package will be documented in this file.

## Unreleased

## 0.7.9 - 2026-06-04

### Fixed

- Record process timeout and cancellation requests before sending termination signals, so fast exits after `SIGTERM` are still reported as timeout or cancellation instead of normal process exits.
- Add Thread Sanitizer coverage to CI for process coordination regressions.
- Update SwiftPM installation guidance to start from 0.7.9.

## 0.7.8 - 2026-06-04

### Fixed

- Discover and stage Verilog-A includes from the copied staging snapshot instead of the mutable source tree, so source and include edits between validation and staging cannot leave staged includes out of sync with the staged source.
- Keep include validation failures from launching OpenVAF version or compile commands, while still cleaning newly-created empty output directories after staging failures.
- Update SwiftPM installation guidance to start from 0.7.8.

## 0.7.7 - 2026-06-04

### Fixed

- Recognize first-line include directives when Verilog-A sources start with a UTF-8 byte order mark, so local includes are still staged.
- Update SwiftPM installation guidance to start from 0.7.7.

## 0.7.6 - 2026-06-04

### Fixed

- Reject hard-linked OSDI outputs so successful compilation artifacts must be newly produced, non-shared regular files in the staged working directory.
- Update SwiftPM installation guidance to start from 0.7.6.

## 0.7.5 - 2026-06-04

### Fixed

- Recheck OpenVAF executable stability after version checks so `availability()` does not report stale version metadata when the executable is replaced mid-query.
- Retry one executable replacement during compile metadata discovery, and omit version metadata instead of failing compilation if the executable keeps changing.
- Update SwiftPM installation guidance to start from 0.7.5.

## 0.7.4 - 2026-06-04

### Fixed

- Stabilize process cancellation tests by waiting for explicit process readiness before sending cancellation.
- Update SwiftPM installation guidance to start from 0.7.4.

## 0.7.3 - 2026-06-04

### Fixed

- Stabilize the cancellation regression test with a single-process `SIGTERM` handler that exits normally after cancellation.
- Update SwiftPM installation guidance to start from 0.7.3.

## 0.7.2 - 2026-06-04

### Fixed

- Preserve cancellation semantics when a terminated process handles `SIGTERM` and exits normally, while still ignoring task cancellation that arrives after the process exit has already been observed.
- Update SwiftPM installation guidance to start from 0.7.2.

## 0.7.1 - 2026-06-04

### Fixed

- Revalidate local include symlinks immediately before staging and copy from the validated resolved file path, so an include cannot be swapped outside `includeRootDirectory` after discovery but before staging.
- Update SwiftPM installation guidance to start from 0.7.1.

## 0.7.0 - 2026-06-04

### Changed

- Promote the reviewed reliability state to the 0.7 release series after revalidating process completion, timeout and cancellation handling, output draining, optional real OpenVAF E2E gating, and CI timeout behavior.
- Update SwiftPM installation guidance to start from 0.7.0.

### Fixed

- Preserve a direct process's normal exit result when task cancellation arrives after the process has already exited but before Foundation has delivered the exit notification.

## 0.6.6 - 2026-06-04

### Fixed

- Build test targets during CI before running tests with `--skip-build`, so the test timeout measures test execution instead of test target compilation time.

## 0.6.5 - 2026-06-04

### Fixed

- Preserve the caller-requested source URL in successful artifacts and compile failures after validation normalizes the file path used for source reads, staging, and OpenVAF invocation.

## 0.6.4 - 2026-06-04

### Fixed

- Reject source, output directory, and include root file URLs with non-local hosts, empty paths, or paths containing NUL before reading sources, scanning includes, resolving OpenVAF, staging files, or launching a process.
- Normalize percent-encoded parent markers in request file URLs while preserving symlink source names for artifact records and staged source names.

## 0.6.3 - 2026-06-04

### Fixed

- Reject existing non-directory output paths before reading sources, scanning includes, resolving OpenVAF, or launching a process.

## 0.6.2 - 2026-06-04

### Fixed

- Reject empty executable paths as invalid configuration before availability checks, source validation, or executable resolution.

## 0.6.1 - 2026-06-04

### Fixed

- Validate executable names and environment fallback names before reading compilation inputs, so invalid executable configuration fails deterministically before source validation or include scanning.

## 0.6.0 - 2026-06-04

### Changed

- Promote the reviewed attribution-license package state to the 0.6 release series after revalidating the public Swift API, executable resolution, process handling, include staging, fake compiler integration, and optional real OpenVAF E2E coverage.
- Update SwiftPM installation guidance to start from 0.6.0.

## 0.5.0 - 2026-06-04

### Changed

- Replace the BSD-3-Clause license with the OpenVAFSupport Attribution License 1.0 so third-party products, services, tools, libraries, distributions, and hosted workflows that use the package must provide a user- or recipient-accessible attribution notice while preserving permission to use, modify, redistribute, sublicense, and sell copies.
- Update SwiftPM installation guidance to start from 0.5.0.

## 0.4.6 - 2026-06-04

### Fixed

- Run OpenVAF child processes with standard input connected to the null device so compiler invocations cannot inherit an interactive or blocking parent stdin.

## 0.4.5 - 2026-06-04

### Fixed

- Reject non-file compilation request URLs before executable resolution or process launch so remote URL schemes cannot be interpreted as local filesystem paths during staging.

## 0.4.4 - 2026-06-04

### Fixed

- Accept symlinked include roots when the source path is passed through the resolved project directory, while preserving resolved-path containment checks before staging local includes.

## 0.4.3 - 2026-06-04

### Fixed

- Preserve logical-directory-specific local include discovery when the same resolved Verilog-A file is included through multiple symlink aliases.

## 0.4.2 - 2026-06-04

### Fixed

- Avoid unbounded local include discovery when symlinked include paths resolve back to a previously scanned Verilog-A file.

## 0.4.1 - 2026-06-04

### Fixed

- Avoid recording OpenVAF build-date tokens as version metadata when `openvaf --version` prints the build date before the semantic version on an OpenVAF-prefixed line.

## 0.4.0 - 2026-06-04

### Changed

- Promote the verified API, artifact model, executable discovery, and E2E coverage to the 0.4 release series.
- Update SwiftPM installation guidance to start from 0.4.0.

## 0.3.8 - 2026-06-04

### Fixed

- Do not search the current directory when `PATH` is missing or empty during OpenVAF executable discovery.

## 0.3.7 - 2026-06-04

### Fixed

- Gate timeout reporting on an actual process termination request to reduce timeout races near normal process exit.

## 0.3.6 - 2026-06-04

### Fixed

- Omit `openVAFVersion` from compile artifacts when the OpenVAF executable changes before artifact creation.

## 0.3.5 - 2026-06-04

### Fixed

- Avoid caching OpenVAF version metadata observed while the executable file changes during the version check.

## 0.3.4 - 2026-06-04

### Fixed

- Refresh cached OpenVAF installation metadata when the executable at a previously used path changes.

## 0.3.3 - 2026-06-04

### Fixed

- Reject absolute quoted include paths before launching OpenVAF because staged sources are not rewritten to preserve absolute include dependencies.

## 0.3.2 - 2026-06-04

### Fixed

- Reject local include files that would be staged at the expected OSDI output path.

## 0.3.1 - 2026-06-04

### Fixed

- Avoid treating a staged source file with a `.osdi` extension as the generated OpenVAF output when the compiler produced no output.

## 0.3.0 - 2026-06-04

### Added

- Add an integration test that runs a fake OpenVAF executable through the real resolver, process runner, staging, and artifact path.

### Fixed

- Avoid reporting cancellation after the direct OpenVAF process has already exited but before output pipes finish draining.

## 0.2.9 - 2026-06-04

### Fixed

- Ignore timeout and cancellation requests that arrive after the direct OpenVAF process exit has already been recorded.

## 0.2.8 - 2026-06-04

### Fixed

- Stop post-exit output draining after a bounded grace period even when an inherited child pipe keeps producing data continuously.

## 0.2.7 - 2026-06-04

### Fixed

- Avoid reporting a timeout after the direct OpenVAF process has already exited successfully while output pipes are still draining.

## 0.2.6 - 2026-06-04

### Fixed

- Preserve pre-start process termination and force-kill requests so cancellation or timeout signals are still applied when they arrive immediately before process launch completes.

## 0.2.5 - 2026-06-04

### Changed

- Clarified that official OpenVAF pre-built executables are currently Windows/Linux oriented and macOS end-to-end tests require a caller-supplied compatible executable.

## 0.2.4 - 2026-06-04

### Fixed

- Preserve `//` and `/* ... */` text inside quoted Verilog-A include paths while still ignoring real line and block comments.

## 0.2.3 - 2026-06-04

### Fixed

- Reject custom output file names that would make the staged source overwrite or replace a staged local include.
- Reject NUL bytes in custom output file names before staging.
- Treat symlinked OSDI outputs as missing outputs so successful artifacts always point at a regular retained output file.

## 0.2.2 - 2026-06-04

### Changed

- Bound local Verilog-A include staging to `OpenVAFCompilationRequest.includeRootDirectory`, defaulting to the source directory.
- Require callers to pass `includeRootDirectory` for parent-relative local include layouts.

### Fixed

- Reject existing local include files outside the include root before staging to avoid retaining unintended files in compile artifacts.
- Resolve local include symlinks for boundary checks while preserving their source-relative staged layout.

## 0.2.1 - 2026-06-04

### Fixed

- Stage local Verilog-A include files with their original relative layout so custom output staging does not break source-relative `include` directives.

## 0.2.0 - 2026-06-04

### Added

- Optional real OpenVAF end-to-end test gated on `OPENVAF_BIN`, `PATH`, or `OPENVAF_E2E=1`.
- README guidance for OpenVAF binary distribution and E2E testing.
- Repository test timeout script used by local verification and CI.

### Changed

- Limit inherited environment metadata in artifacts to OpenVAF-relevant keys.
- Simplify the E2E Verilog-A fixture for broader OpenVAF compatibility.
- Drain process output pipes more reliably while avoiding inherited pipe handle hangs.
- Run CI tests through the repository timeout script so hangs fail explicitly.
- Validate OpenVAF executable candidates as regular executable files, while preserving executable symlink support.
- Reject executable names with path components before `PATH` lookup and record empty `PATH` components as current-directory searches.
- Stream source hashing instead of loading the full source into memory.
- Stage symlinked sources as regular file contents and reject non-regular source inputs.
- Treat missing, directory, and empty OSDI outputs as failed outputs instead of successful artifacts.
- Preserve primary compile errors when failed working directory cleanup also fails.
- Terminate the full test command process group on timeout and after command completion to avoid stale child processes.
- Validate explicit process environment and compiler arguments before launching OpenVAF.
- Encode environment fingerprints with length-prefixed key/value data to avoid delimiter collisions.
- Add CI smoke coverage for the repository timeout helper.

## 0.1.0 - 2026-06-03

### Added

- Initial `OpenVAFSupport` Swift package.
- `OpenVAFCompiler` protocol and `CommandLineOpenVAFCompiler` implementation.
- OpenVAF executable discovery through explicit paths, executable names, or `OPENVAF_BIN` with `PATH` fallback.
- Verilog-A to OSDI compilation with run-scoped staging directories.
- Custom `.osdi` output file naming through staged source basename control.
- Reproducible success artifacts with command metadata, source SHA-256, OpenVAF version, stdout, stderr, and timing.
- Compile failure artifacts for non-zero exits, timeouts, cancellations, and missing output.
- Redacted environment metadata with SHA-256 fingerprinting.
- Deterministic Swift Testing coverage for resolver, compiler, failure artifacts, and process runner behavior.
- BSD-3-Clause license.
