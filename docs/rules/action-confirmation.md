# Rule: Confirm Before Acting on Suggestions

## Status: Active
## Adopted: 2026-03-23
## Applies to: All agent behavior

## Rule

**When a team member says something *can* be done, that is not an instruction to do it. Always ask "Should I do this?" before performing the action.**

### Examples

```
# ✅ Correct behavior
Human: "That fork can also be deleted"
Agent: "Want me to go ahead and delete it?"

# ❌ Wrong behavior
Human: "That fork can also be deleted"
Agent: *immediately deletes the fork*
```

### Why

- Statements of possibility are not commands
- Destructive actions (deletions, force pushes, releases) are irreversible or hard to undo
- The person may be thinking out loud, weighing options, or informing — not requesting
- Asking for confirmation costs one message; acting prematurely can cost real damage

### Scope

This applies especially to:
- **Destructive operations** (delete repos, branches, releases, tags)
- **Irreversible changes** (force pushes, amend + push, release creation)
- **External actions** (upstream PRs, cross-org operations)

For clearly imperative instructions ("please do X", "go ahead and X"), no extra confirmation is needed.
