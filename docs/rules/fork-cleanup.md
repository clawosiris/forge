# Rule: Clean Up Temporary Forks After Upstream PR Completion

## Status: Active
## Adopted: 2026-03-27
## Applies to: All repositories under `clawosiris/` used as temporary forks for upstream contributions

## Rule

**When a fork exists only to deliver an upstream contribution, delete the fork after all related upstream PRs are finished (merged or closed) and no follow-up work is pending.**

A completed contribution should not leave long-lived maintenance forks unless there is an explicit owner request to keep them.

## Cleanup Preconditions

Before deleting a fork, verify all of the following:

1. **All related upstream PRs are finished** (`merged` or `closed`).
2. **No open PR references branches from that fork**.
3. **No active task depends on the fork** (release follow-up, backport, review fixes).
4. **Important commits are preserved upstream** (merged) or intentionally abandoned.
5. **Deletion is explicitly requested/confirmed** by a human (destructive action safeguard).

## Recommended Flow

```bash
# 1) Verify upstream PR state(s)
gh pr view <upstream-pr-url> --json state,mergedAt

# 2) Verify no open PRs still depend on fork branches
# (check fork repo PR list and upstream references)
gh pr list --repo <fork-owner>/<fork-repo> --state open

# 3) Delete fork repository
gh repo delete <fork-owner>/<fork-repo> --yes
```

## Why

- Keeps org/repo list clean and focused
- Reduces stale maintenance burden and confusion
- Avoids accidental work on obsolete forks
- Encourages upstream-first contribution hygiene

## Exceptions

Keep the fork if any of the following apply:

- Ongoing multi-PR contribution stream to the same upstream
- Explicit request from maintainers to keep fork alive
- Fork is used as long-term mirror/sandbox, not a temporary contribution vehicle

## Example

If a contribution to `greenbone/actions` is complete and the upstream PR is finished, the corresponding temporary `clawosiris/actions` fork should be removed after confirmation.
