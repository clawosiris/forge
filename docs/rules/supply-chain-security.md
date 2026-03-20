# Rule: Pin Third-Party GitHub Actions to Commit SHAs

## Status: Active
## Adopted: 2026-03-20
## Applies to: All repositories under clawosiris/

## Rule

**Never use version or branch tags for third-party GitHub Actions. Always pin to the full commit SHA of the latest stable release.**

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

Version tags in GitHub are **mutable** — a repository owner (or attacker who compromises the repo) can move a tag to point at a different commit. This means `actions/checkout@v6` could silently change to execute different code without any visible change in your workflow files.

Commit SHAs are **immutable** — they cryptographically identify a specific version of the code. A compromised upstream cannot change what runs in your CI without the SHA changing in your workflow file, which creates a visible diff in code review.

This is a [documented best practice](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions#using-third-party-actions) by GitHub and part of the [OpenSSF Scorecard](https://github.com/ossf/scorecard/blob/main/docs/checks.md#pinned-dependencies) criteria.

### How to Find the SHA

```bash
# Get the commit SHA for a specific tag
gh api repos/OWNER/REPO/git/ref/tags/TAG --jq '.object.sha'

# Example
gh api repos/actions/checkout/git/ref/tags/v6 --jq '.object.sha'
# → de0fac2e4500dabe0009e67214ff5f5447ce83dd
```

### Version Comment Convention

Always include the human-readable version as a trailing comment:

```yaml
uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6
```

This makes it easy to:
1. See at a glance what version you're on
2. Know when Dependabot proposes an update
3. Search/grep for all uses of a specific version

### Updating Pinned Actions

When upgrading to a new version:
1. Look up the new SHA: `gh api repos/OWNER/REPO/git/ref/tags/NEW_TAG --jq '.object.sha'`
2. Replace the SHA in all workflow files
3. Update the version comment
4. Commit with message: `ci(deps): bump OWNER/REPO from vOLD to vNEW`

Dependabot handles this automatically when configured for `github-actions` ecosystem.

### Exceptions

- **`dtolnay/rust-toolchain`** uses branch refs (`stable`, `master`, `1.75.0`) rather than version tags. Pin these to the branch HEAD SHA and update periodically.
- **First-party actions** (actions owned by the same org) may use tags if the org controls the action repo and tag immutability is enforced.

### Reference SHAs (as of 2026-03-20)

| Action | Version | SHA |
|--------|---------|-----|
| `actions/checkout` | v6 | `de0fac2e4500dabe0009e67214ff5f5447ce83dd` |
| `actions/upload-artifact` | v7 | `bbbca2ddaa5d8feaa63e36b76fdaad77386f024f` |
| `actions/download-artifact` | v8 | `3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c` |
| `actions/setup-python` | v6 | `a309ff8b426b58ec0e2a45f0f869d46889d02405` |
| `actions/setup-go` | v6 | `4b73464bb391d4059bd26b0524d20df3927bd417` |
| `actions/cache` | v5 | `668228422ae6a00e4ad889ee87cd7109ec5666a7` |
| `codecov/codecov-action` | v5 | `1af58845a975a7985b0beb0cbe6fbbb71a41dbad` |
| `EmbarkStudios/cargo-deny-action` | v2 | `82eb9f621fbc699dd0918f3ea06864c14cc84246` |
| `softprops/action-gh-release` | v2 | `153bb8e04406b158c6c84fc1615b65b24149a1fe` |
| `Swatinem/rust-cache` | v2 | `42dc69e1aa15d09112580998cf2ef0119e2e91ae` |
| `taiki-e/install-action` | cargo-llvm-cov | `660ccd1d376e9007f8fbbc3c66b63643fa9ddd6e` |
| `dtolnay/rust-toolchain` | stable | `631a55b12751854ce901bb631d5902ceb48146f7` |
| `dtolnay/rust-toolchain` | master | `efa25f7f19611383d5b0ccf2d1c8914531636bf9` |
| `docker/build-push-action` | v6 | `10e90e3645eae34f1e60eeb005ba3a3d33f178e8` |
| `docker/login-action` | v3 | `c94ce9fb468520275223c153574b00df6fe4bcc9` |
| `docker/metadata-action` | v5 | `c299e40c65443455700f0fdfc63efafe5b349051` |
| `docker/setup-buildx-action` | v3 | `8d2750c68a42422c14e847fe6c8ac0403b4cbd6f` |
| `docker/setup-qemu-action` | v3 | `c7c53464625b32c7a7e944ae62b3e17d2b600130` |
| `snok/install-poetry` | v1 | `76e04a911780d5b312d89783f7b1cd627778900a` |
