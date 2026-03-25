# Rule: CI Monitoring — Check, Act, Report

## Status: Active
## Adopted: 2026-03-23
## Applies to: All heartbeat-monitored CI/CD tasks

## Rule

**When a CI run is being monitored via HEARTBEAT.md, every heartbeat MUST follow the Check → Act → Report cycle. No silent failures.**

### The Cycle

```
1. CHECK  — Query run status (gh run view)
2. ACT    — If failed: analyze, fix, retrigger
             If succeeded: report success, remove task
             If in_progress: do nothing (HEARTBEAT_OK)
3. REPORT — Always report state changes to the Signal group
             Success → "✅ [run] passed — [link]"
             Failure → "❌ [run] failed — [cause] — fixing now"
             No silent completions. No unreported failures.
```

### Rules

1. **Never let a completed run go unreported.** If a monitored run finishes (pass or fail), report it immediately — don't wait to be asked.

2. **Failed runs require action, not just reporting.** Analyze logs, identify the cause, push a fix, retrigger, and report what you did.

3. **Update HEARTBEAT.md after every action.** New run URL, removed completed task, etc.

4. **Don't accumulate stale monitoring tasks.** If a task is done (succeeded + reported), remove it from HEARTBEAT.md.

5. **Include links.** Every report to the group must include the run URL.

### Anti-patterns

```
# ❌ Wrong: Check status but don't report
heartbeat fires → run failed → no message to group

# ❌ Wrong: Report but don't act
"❌ E2E failed" → no analysis, no fix, no retrigger

# ❌ Wrong: Fix but don't report
push fix + retrigger → no message to group about what changed

# ❌ Wrong: Wait to be asked
Daniel: "what's the status?" → (this means monitoring failed)
```

### Why

- CI monitoring is only useful if failures are caught and acted on promptly
- The team should never have to ask "what happened?" — they should already know
- Silent failures erode trust in automated monitoring
- The whole point of heartbeat tasks is autonomous operation
