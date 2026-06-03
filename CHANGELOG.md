# Changelog

All notable changes to this package will be documented in this file.

## Unreleased

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
