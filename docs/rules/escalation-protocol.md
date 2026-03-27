# Escalation Protocol

## Purpose

When agents encounter problems they cannot resolve, they must escalate clearly rather than spinning in retry loops or producing low-quality work. Bad work is worse than no work.

## Completion Status

Every agent task MUST end with a structured status block:

```
## Completion Status

STATUS: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
CONFIDENCE: HIGH | MEDIUM | LOW
REASON: [1-2 sentences explaining the status]
ATTEMPTED: [what approaches were tried, if not DONE]
RECOMMENDATION: [what the human should do next, if not DONE]
```

### Status Values

| Status | Meaning | Supervisor Action |
|--------|---------|-------------------|
| `DONE` | Task completed successfully | Proceed to next state |
| `DONE_WITH_CONCERNS` | Completed but with caveats | Log concerns, proceed with caution |
| `BLOCKED` | Cannot proceed without human help | Escalate to human immediately |
| `NEEDS_CONTEXT` | Missing information to proceed | Request context, then retry |

### Confidence Levels

| Confidence | Meaning |
|------------|---------|
| `HIGH` | Solution is correct and complete |
| `MEDIUM` | Solution is likely correct but edge cases may exist |
| `LOW` | Significant uncertainty — human review recommended |

## Three-Attempt Rule

Before escalating to BLOCKED:

1. **Attempt 1:** Try the obvious approach
2. **Attempt 2:** If that fails, try an alternative approach
3. **Attempt 3:** If that fails, try one more variation

After 3 failed attempts → **STOP and escalate as BLOCKED**

Do not continue retrying. Document what was tried and why each attempt failed.

## Mandatory Escalation Triggers

Immediately escalate (skip the three-attempt rule) for:

- **Security-sensitive changes:** Auth, crypto, permissions, secrets
- **Breaking changes:** API compatibility, data migrations
- **Scope ambiguity:** Unclear if something is in/out of scope
- **Conflicting requirements:** Spec contradicts itself or existing code
- **External dependencies:** Need access/credentials/approvals not available

## Escalation Format

When escalating, provide:

```
## Escalation

STATUS: BLOCKED
TRIGGER: [which mandatory trigger or "3 attempts failed"]
REASON: [1-2 sentences on why this is blocked]

### Attempted Approaches
1. [Approach 1]: [outcome]
2. [Approach 2]: [outcome]  
3. [Approach 3]: [outcome]

### Context Gathered
- [Relevant finding 1]
- [Relevant finding 2]

### Recommendation
[What the human should do — e.g., "Clarify whether X should Y or Z", "Provide access to service Q"]

### Artifacts
- [Links to any partial work, logs, or diagnostics]
```

## Supervisor Handling

When the supervisor receives an escalation:

1. **BLOCKED:** Post to GitHub issue with full escalation context, notify parent session, halt workflow
2. **NEEDS_CONTEXT:** Request clarification from human, re-spawn agent with additional context when received
3. **DONE_WITH_CONCERNS:** Log concerns in journal, proceed but flag for human review
4. **LOW confidence DONE:** Proceed but add to PR review notes for extra scrutiny

## Anti-Patterns

**DO NOT:**
- Retry indefinitely hoping for a different result
- Produce partial/broken output to "make progress"
- Assume context that wasn't provided
- Make security-sensitive decisions without escalation
- Hide failures in verbose output

**DO:**
- Fail fast and fail clearly
- Preserve diagnostic information
- Be specific about what's needed to unblock
- Acknowledge uncertainty explicitly
