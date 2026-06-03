# Changelog

All notable changes to this package will be documented in this file.

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
