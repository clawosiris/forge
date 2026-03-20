# Rule: All Changes Via Pull Requests

## Status: Active
## Adopted: 2026-03-20
## Applies to: All repositories under clawosiris/

## Rule

**Never push directly to `main`. All changes — including CI/CD, configs, and docs — must go through a Pull Request from a feature branch.**

### Workflow

1. **Create a feature branch** for the work:
   ```bash
   git checkout -b feat/description-of-change
   ```

2. **Collect all related changes** into the branch. One PR per logical feature, not per-file.

3. **Push the branch and create a PR** when the work is complete:
   ```bash
   git push -u origin feat/description-of-change
   gh pr create --title "feat: description" --body "Details..."
   ```

4. **Share the PR link** with the team for review.

5. **Enable auto-merge (squash)** on the PR immediately after creation.
6. PR merges automatically once approved and CI passes.

### Branch Naming Convention

| Prefix | Use |
|--------|-----|
| `feat/` | New features |
| `fix/` | Bug fixes |
| `ci/` | CI/CD changes |
| `docs/` | Documentation |
| `refactor/` | Code restructuring |
| `chore/` | Maintenance |

### Why

- Code review catches issues before they reach `main`
- Change history is traceable and reversible
- CI runs against the branch before merge
- Team stays informed via PR notifications
- Prevents broken `main` from untested changes

### Auto-Merge

All PRs must have **auto-merge (squash)** enabled immediately after creation:

```bash
gh pr merge <number> --squash --auto
```

Or use the `greenbone/actions/auto-merge` action in CI to enable it automatically.

### Draft PRs

If a PR is **not ready for review**, open it as a draft:

```bash
gh pr create --draft --title "feat: work in progress"
```

Convert to ready-for-review when complete:

```bash
gh pr ready <number>
```

### Exceptions

None. Even single-line fixes go through a PR.
