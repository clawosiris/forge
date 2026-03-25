# Compliance

## License Policy

When a project specifies a license:

1. **All new source files** must include an SPDX header:
   ```
   // SPDX-License-Identifier: <license-id>
   ```
2. Use the SPDX identifier that matches the project's `LICENSE` file
3. Common identifiers: `MIT`, `Apache-2.0`, `GPL-3.0-or-later`, `AGPL-3.0-or-later`

## Dependency Auditing

For Rust projects:
- Use `cargo deny check` for license and advisory audits
- Use `cargo audit` for known vulnerability checks
- Use `cargo cyclonedx` for SBOM generation (CycloneDX format)

For Node.js projects:
- Use `npm audit` for vulnerability checks
- Use license-checker or similar for license compliance

## License Change Checklist

If changing a project's license:
1. Update `LICENSE` file
2. Update `Cargo.toml` / `package.json` license field
3. Update all SPDX headers in source files
4. Verify dependency compatibility with new license (`cargo deny`)
5. Note the change in CHANGELOG

## SBOM Requirements (Rust)

### Minimum requirements

Generate an SBOM for **release** and **nightly** builds:

- Tool: `cargo-cyclonedx`
- Format: CycloneDX **JSON + XML**
- Spec version: prefer **CycloneDX 1.5+**
- Artifact: package SBOMs as build artifacts (and attach to GitHub Release for tagged builds)

### Quality gate (sbomqs)

Add an SBOM quality gate using [`sbomqs`](https://github.com/interlynk-io/sbomqs):

- Run `sbomqs score` on the generated SBOM JSON files
- Fail the workflow if any SBOM score is below the threshold
- Suggested thresholds:
  - **Initial**: ≥ **7.0** (avoid blocking early adoption)
  - **Target**: ≥ **8.5** once metadata is improved
  - **Stretch**: ≥ **9.0** after signing + additional identifiers

### Required metadata improvements (lessons learned)

`cargo-cyclonedx` produces a strong Cargo-native dependency graph (licenses, checksums, source URIs), but SBOM quality scoring often flags missing *document* metadata fields.

To raise SBOM quality, add a deterministic post-processing step for `*.cdx.json` SBOMs that injects:

- SBOM data license (e.g., **CC0-1.0**) in `metadata.licenses`
- Build lifecycle phase (e.g., `metadata.lifecycles: [{ phase: "build" }]`)
- Supplier names:
  - first-party workspace crates → supplier = repo owner/org
  - crates.io dependencies → supplier = `crates.io` (best-effort)

### Common pitfalls

- **Fixture pollution**: if you store SBOM fixtures for tests, ensure your SBOM collection step excludes them (e.g., exclude `*/fixtures/*`). Otherwise the quality gate will score the fixture and fail.
- **Shell quoting**: when generating PR bodies / issue comments via CLI, avoid unescaped backticks (`` ` ``) inside double-quoted strings; use `--body-file` to prevent shell command substitution.

### Optional (for 9.0+)

To push scores toward 9.0+:

- Add additional vulnerability lookup identifiers (e.g., CPE) alongside purl
- Add SBOM signing (cosign/sigstore) and publish signatures
- Add BOM links / external references where meaningful

## CI Integration

Add compliance checks to CI:
- SPDX header verification (grep/script)
- `cargo deny` or equivalent dependency audit
- SBOM generation on release builds
- SBOM quality gate on release/nightly builds
