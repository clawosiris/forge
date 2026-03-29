# Rule: Supply Chain Security for GitHub Actions

## Status: Active
## Adopted: 2026-03-20
## Updated: 2026-03-28
## Applies to: All repositories under clawosiris/

---

## Summary

This rule defines security requirements for GitHub Actions workflows to mitigate supply chain attacks. It covers:
1. SHA pinning for actions
2. Version pinning for tools
3. Action verification before adoption
4. Runtime monitoring
5. Build provenance

---

## 1. Pin Third-Party Actions to Commit SHAs

**Never use version or branch tags for third-party GitHub Actions. Always pin to the full commit SHA.**

### Format

```yaml
# ✅ Correct: pinned to commit SHA with version comment
- uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6

# ❌ Wrong: mutable version tag
- uses: actions/checkout@v6

# ❌ Wrong: branch reference
- uses: dtolnay/rust-toolchain@stable
```

### Why

Version tags are **mutable** — a repository owner (or attacker who compromises the repo) can move a tag to point at different code. Commit SHAs are **immutable** and cryptographically identify specific code.

### How to Find the SHA

```bash
gh api repos/OWNER/REPO/git/ref/tags/TAG --jq '.object.sha'
```

### Version Comment Convention

Always include the human-readable version as a trailing comment for discoverability:

```yaml
uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6
```

---

## 2. Pin Tool Versions in Workflows

**All `cargo install`, `go install`, `pip install`, and similar commands MUST specify versions.**

### Format

```yaml
# ✅ Correct: pinned versions
- uses: taiki-e/install-action@<sha>
  with:
    tool: cargo-audit@0.22.1

- run: go install github.com/interlynk-io/sbomqs@v2.0.5

- run: cargo install cross --git https://github.com/cross-rs/cross --tag v0.2.5

# ❌ Wrong: unpinned
- run: cargo install cargo-audit
- run: go install github.com/example/tool@latest
- run: pip install some-package
```

### Why

`@latest` or unpinned installs can pull malicious versions at any time. Pinning ensures reproducibility and auditability.

### Centralize Versions

Define tool versions in workflow env vars for consistency:

```yaml
env:
  CARGO_AUDIT_VERSION: "0.22.1"
  SBOMQS_VERSION: "v2.0.5"
  CROSS_VERSION: "v0.2.5"

jobs:
  security:
    steps:
      - uses: taiki-e/install-action@<sha>
        with:
          tool: cargo-audit@${{ env.CARGO_AUDIT_VERSION }}
```

---

## 3. Verify Actions Before Adoption

Before adding a new third-party action to workflows, perform verification.

### 3.1 OpenSSF Scorecard

Run Scorecard to assess supply chain security posture:

```bash
export GITHUB_AUTH_TOKEN=$(gh auth token)
scorecard --repo=github.com/OWNER/ACTION
```

**Trust thresholds:**
- Score ≥ 7.0: Generally safe, proceed
- Score 5.0-6.9: Review findings, monitor closely
- Score < 5.0: Require code review before adoption

**Key checks to examine:**
- `Code-Review`: Are changes reviewed before merge?
- `Branch-Protection`: Can maintainers force-push?
- `Token-Permissions`: Does it request minimal permissions?
- `Vulnerabilities`: Known CVEs in dependencies?
- `Pinned-Dependencies`: Does the action itself pin its deps?

### 3.2 Code Review of Action Source

For actions with Scorecard < 7.0 or high-privilege needs, review the source:

```bash
git clone --depth 1 https://github.com/OWNER/ACTION
# Review: action.yml, entrypoint scripts, src/*, package.json
```

**Check for:**
1. **Entry points**: What files execute? Compiled JS harder to audit.
2. **Network calls**: URLs hardcoded or configurable? Data sent externally?
3. **Secrets handling**: How are tokens accessed? Could they leak?
4. **Command injection**: Can inputs be injected into shell commands?
5. **Dependencies**: npm deps pinned? Known-vulnerable packages?

**Red flags:**
- `curl | bash` patterns
- Obfuscated or minified entry points without source
- Secrets passed as command-line arguments (visible in `/proc`)
- Unquoted shell variable expansion (`$*` instead of `"$@"`)
- Network calls to non-GitHub domains

### 3.3 Trust Hierarchy

Prefer actions in this order:
1. **GitHub-owned** (`actions/*`) — most vetted
2. **Verified creators** (blue checkmark in marketplace)
3. **Well-known orgs** (docker, hashicorp, rust-lang ecosystem)
4. **Random repos** — highest risk, full audit required

---

## 4. Runtime Monitoring with Harden-Runner

Add [StepSecurity Harden-Runner](https://github.com/step-security/harden-runner) to monitor workflow execution.

### Setup

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: step-security/harden-runner@<sha> # v2
        with:
          egress-policy: audit  # Start with audit, graduate to block
      
      - uses: actions/checkout@<sha>
      # ... rest of job
```

### What It Detects

- Outbound network connections (useful for detecting exfiltration)
- Anomalous DNS lookups
- Process execution patterns

### Policy Progression

1. **audit**: Log all network activity, don't block (baseline phase)
2. **block**: Block unexpected egress after baseline established

---

## 5. Build Provenance Attestations

Add Sigstore attestations to release artifacts for SLSA compliance.

### Setup

```yaml
permissions:
  id-token: write
  attestations: write

jobs:
  release:
    steps:
      - name: Build
        run: cargo build --release
      
      - uses: actions/attest-build-provenance@<sha> # v2
        with:
          subject-path: 'target/release/my-binary'
```

### Verification

Users can verify artifacts came from your CI:

```bash
gh attestation verify my-binary --owner YOUR_ORG
```

---

## 6. Dependabot for Action Updates

Configure Dependabot to propose action updates:

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
```

**Review process for Dependabot PRs:**
1. Check the action's changelog for breaking changes
2. Verify the new SHA corresponds to a tagged release
3. For actions with Scorecard < 7.0, re-run Scorecard on the new version

---

## 7. Known Action Assessments

Actions used in Forge-managed workflows with their risk profiles:

| Action | Scorecard | Code Review | Notes |
|--------|-----------|-------------|-------|
| `actions/checkout` | 5.9 | LOW | GitHub first-party, simple |
| `actions/upload-artifact` | 5.8 | LOW | GitHub first-party |
| `dtolnay/rust-toolchain` | 4.9 | **LOW** | Clean shell, trusted maintainer |
| `EmbarkStudios/cargo-deny-action` | 4.6 | **MEDIUM** | Consider replacing with direct cargo deny |
| `softprops/action-gh-release` | 5.4 | **MEDIUM** | Token handling concern |
| `Swatinem/rust-cache` | 6.6 | LOW | Widely used |
| `taiki-e/install-action` | 7.4 | LOW | Well-maintained |
| `step-security/harden-runner` | — | LOW | Security-focused org |

### Actions to Consider Replacing

| Action | Alternative | Reason |
|--------|-------------|--------|
| `EmbarkStudios/cargo-deny-action` | Direct `cargo deny check` | Unmaintained, code issues |
| `softprops/action-gh-release` | `gh release create` CLI | More control, no third-party |

---

## Reference: Current SHA Pins

| Action | Version | SHA |
|--------|---------|-----|
| `actions/checkout` | v6 | `de0fac2e4500dabe0009e67214ff5f5447ce83dd` |
| `actions/upload-artifact` | v7 | `bbbca2ddaa5d8feaa63e36b76fdaad77386f024f` |
| `actions/download-artifact` | v8 | `3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c` |
| `actions/setup-python` | v6 | `a309ff8b426b58ec0e2a45f0f869d46889d02405` |
| `actions/setup-go` | v6 | `4b73464bb391d4059bd26b0524d20df3927bd417` |
| `actions/attest-build-provenance` | v2 | `96b4a1ef7235a096b17240c259729fdd70c83d45` |
| `step-security/harden-runner` | v2.16.0 | `fa2e9d605c4eeb9fcad4c99c224cee0c6c7f3594` |
| `taiki-e/install-action` | v2 | `a164de717a0ee9284c2d9db1c6016a4c339cd333` |
| `codecov/codecov-action` | v5 | `1af58845a975a7985b0beb0cbe6fbbb71a41dbad` |
| `EmbarkStudios/cargo-deny-action` | v2 | `3fd3802e88374d3fe9159b834c7714ec57d6c979` |
| `softprops/action-gh-release` | v2 | `153bb8e04406b158c6c84fc1615b65b24149a1fe` |
| `Swatinem/rust-cache` | v2 | `e18b497796c12c097a38f9edb9d0641fb99eee32` |
| `dtolnay/rust-toolchain` | stable | `631a55b12751854ce901bb631d5902ceb48146f7` |
| `docker/build-push-action` | v6 | `10e90e3645eae34f1e60eeb005ba3a3d33f178e8` |
| `docker/login-action` | v3 | `c94ce9fb468520275223c153574b00df6fe4bcc9` |
| `docker/metadata-action` | v5 | `c299e40c65443455700f0fdfc63efafe5b349051` |
| `docker/setup-buildx-action` | v3 | `8d2750c68a42422c14e847fe6c8ac0403b4cbd6f` |
| `docker/setup-qemu-action` | v3 | `c7c53464625b32c7a7e944ae62b3e17d2b600130` |

---

## Checklist for New Workflows

- [ ] All actions pinned by SHA with version comments
- [ ] All tool installs pinned by version
- [ ] Harden-runner added to all jobs
- [ ] Scorecard run for any new third-party actions
- [ ] Code review completed for actions with Scorecard < 7.0
- [ ] Dependabot configured for github-actions ecosystem
- [ ] Build attestations enabled for release artifacts

---

## References

- [GitHub: Security hardening for GitHub Actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions)
- [OpenSSF Scorecard](https://securityscorecards.dev/)
- [SLSA Framework](https://slsa.dev/)
- [StepSecurity Harden-Runner](https://github.com/step-security/harden-runner)
- [GitHub Artifact Attestations](https://docs.github.com/en/actions/security-guides/using-artifact-attestations-to-establish-provenance-for-builds)
