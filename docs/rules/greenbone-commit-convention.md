# Rule: Greenbone Conventional Commit Format

## Status: Active
## Adopted: 2026-03-23
## Applies to: All contributions to greenbone/* repositories

## Rule

**When contributing to Greenbone repositories (greenbone/actions, greenbone/pontos, etc.), use Greenbone's conventional commit format — not the standard lowercase `feat:`/`fix:` style.**

### Format

```
<Type>: <description>
```

### Commit Types

| Type | Usage |
|------|-------|
| `Add:` | New features, capabilities, files, or actions |
| `Change:` | Modifications to existing behavior, refactors, config changes |
| `Fix:` | Bug fixes, corrections |
| `Deps:` | Dependency updates (usually automated by Dependabot) |

### Examples

```bash
# ✅ Correct: Greenbone convention (capitalized, colon, space)
Add: optional admin-bypass input for release action
Change: Raise minimum Python version to 3.10
Fix: detect actions defined with action.yaml
Deps: Bump actions/checkout in /release in the dependencies group

# ❌ Wrong: standard conventional commits (lowercase, parentheses scope)
feat(release): add optional admin-bypass input
fix: detect actions defined with action.yaml
chore(deps): bump actions/checkout

# ❌ Wrong: no type prefix
Optional admin-bypass input for release action
```

### Why

Greenbone uses [pontos](https://github.com/greenbone/pontos) for automated changelog generation and release management. Pontos parses commit messages using this specific format to categorize changes in the changelog:

- `Add:` → **Added** section
- `Change:` → **Changed** section
- `Fix:` → **Fixed** section
- `Deps:` → **Dependencies** section (often excluded from user-facing changelogs)

Using the wrong format means your changes won't appear correctly in the generated changelog, or may be miscategorized.

### Scope

This rule applies **only to Greenbone upstream repositories**. Our own clawosiris/* repos use the standard conventional commits format (`feat:`, `fix:`, `ci:`, `chore:`, etc.) which is the Rust/Cargo ecosystem convention.

| Repository owner | Commit format |
|-----------------|---------------|
| `greenbone/*` | `Add:` / `Change:` / `Fix:` / `Deps:` |
| `clawosiris/*` | `feat():` / `fix():` / `ci():` / `chore():` / `build():` |

### PR Title

The PR title should also follow the same format, as Greenbone repos typically squash-merge and use the PR title as the merge commit message.
