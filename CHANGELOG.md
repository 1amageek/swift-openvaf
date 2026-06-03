# Changelog

All notable changes to this package will be documented in this file.

## Unreleased

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
- Stream source hashing instead of loading the full source into memory.
- Stage symlinked sources as regular file contents and reject non-regular source inputs.
- Treat missing, directory, and empty OSDI outputs as failed outputs instead of successful artifacts.
- Preserve primary compile errors when failed working directory cleanup also fails.

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
