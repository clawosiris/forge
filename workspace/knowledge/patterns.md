# Patterns

## Sandbox-Safe Testing

When writing tests that require OS resources (sockets, ports, filesystem, processes):

- **Feature-gate** tests behind feature flags (e.g., `#[cfg(feature = "unix-socket-tests")]`)
- **Graceful skip on PermissionDenied:** Detect sandbox restrictions and skip (not fail)
  ```rust
  match result {
      Err(e) if e.kind() == std::io::ErrorKind::PermissionDenied => {
          eprintln!("Skipping: sandbox restriction");
          return;
      }
      _ => {}
  }
  ```
- **Test with and without feature flags** in CI to catch both paths
- **Document sandbox constraints** in test-criteria.md or test-infrastructure.md
- **Use cwd-relative paths** for temp files/sockets (not `/tmp/`) to avoid path length limits in containers

## Codex Task Spec Pattern

The most reliable Codex output comes from single-file task specs with explicit validation:

1. Write a `TASK.md` with: goal, files to create/modify, constraints, validation commands
2. Run: `codex exec --full-auto "Read TASK.md and implement everything"`
3. Codex works best with clear scope — one feature per task spec
4. Include "run these commands to validate" at the end of the spec
5. Max 3 Codex iterations before escalating

**Anti-pattern:** Giving Codex broad instructions without a written spec leads to scope creep and inconsistent results.

## Pre-Commit Validation

Always run the full validation chain before declaring implementation complete:

1. Formatter (`cargo fmt`, `prettier`, `black`, etc.)
2. Linter (`clippy`, `eslint`, `ruff`, etc.)
3. Tests (`cargo test`, `npm test`, `pytest`, etc.)
4. Docs build (if applicable)

Codex frequently produces code that passes tests but fails formatting. This wastes CI cycles.

## Test Infrastructure as First-Class Code

Mock servers, fixtures, and test doubles often become as complex as the library itself:

- Spec them alongside feature code
- Review them with equal rigor
- Version them (they're API contracts for testing)
- Consider cross-language validation (e.g., run the reference client against your mock)

## Spec-Implementation Drift

After implementation, check for drift:
- **Scope creep:** Features implemented but not in the spec
- **Gaps:** Spec items not yet implemented
- **Document organic evolution** — if useful features emerged, update the spec retroactively

This prevents specs from becoming stale artifacts that no one trusts.
