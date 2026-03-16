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

## CI Integration

Add compliance checks to CI:
- SPDX header verification (grep/script)
- `cargo deny` or equivalent dependency audit
- SBOM generation on release builds
