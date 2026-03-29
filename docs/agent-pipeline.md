# Forge Agent Pipeline

This document describes the multi-agent pipeline that powers Forge's automated software development workflow.

## Overview

Forge orchestrates a structured pipeline of specialized AI agents to move requirements through analysis, specification, implementation, testing, and review. The **Supervisor** manages the workflow state machine while spawning specialist agents for each phase.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              SUPERVISOR                                      │
│  (Workflow orchestrator — never writes code, only manages state & spawns)    │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        ▼                           ▼                           ▼
   ┌─────────┐                ┌───────────┐              ┌────────────┐
   │ ANALYST │───────────────▶│ SPEC      │──────────────▶│ IMPLEMENTER│
   │         │   OpenSpec    │ REVIEWER  │   Approved    │ (Codex)    │
   └─────────┘                └───────────┘    Spec       └────────────┘
        │                           │                           │
        │                           │                           ▼
        │                           │                    ┌────────────┐
        │                           │                    │ CI MONITOR │
        │                           │                    └────────────┘
        │                           │                           │
        │                    ┌──────┴──────┐                    │
        │                    ▼             ▼                    ▼
        │             ┌──────────┐  ┌───────────┐        ┌────────────┐
        │             │ CHAOS    │  │ SECURITY  │        │ PR REVIEWER│
        │             │ RALPH    │  │ AUDITOR   │        │ (Claude)   │
        │             └──────────┘  └───────────┘        └────────────┘
        │                    │             │                    │
        │                    └──────┬──────┘                    │
        │                           ▼                           ▼
        │                    ┌────────────┐              ┌────────────┐
        └────────────────────│   HUMAN    │◀─────────────│   MERGE    │
                             │   GATES    │              │  APPROVAL  │
                             └────────────┘              └────────────┘
```

## Pipeline Stages

### 1. Issue Creation

**Actor:** Supervisor  
**Trigger:** Human provides requirement  
**Output:** GitHub Issue with `requirement` label

The supervisor creates a tracking issue containing:
- Requirement text and acceptance criteria
- Tier assessment (small/medium/large)
- Initial labels for workflow tracking

### 2. Analysis (Analyst)

**Actor:** Analyst agent (subagent runtime)  
**Input:** Requirement issue, project context, past decisions  
**Output:** OpenSpec document at `spec/<feature>/openspec.md`

The Analyst:
1. Analyzes the problem space and constraints
2. Reviews past architectural decisions
3. Produces a structured OpenSpec including:
   - Overview with goals and non-goals
   - Architecture and component design
   - Interface definitions (types, traits, APIs)
   - Error handling strategy
   - Dependencies analysis
   - Testing strategy
   - Implementation phases with exit criteria

```yaml
Runtime: subagent
Model: claude-opus-4-6
Timeout: 900s
Knowledge: project-context + past-decisions + known-issues
```

### 3. Spec Review (Spec Reviewer)

**Actor:** Spec Reviewer agent (subagent runtime)  
**Input:** OpenSpec PR, project context  
**Output:** GitHub PR review (Approve / Request Changes)

The Spec Reviewer:
1. Reviews the OpenSpec for completeness and clarity
2. Checks for ambiguities that could cause implementation churn
3. Validates architectural decisions against project patterns
4. Submits PR review via GitHub

```yaml
Runtime: subagent
Model: claude-sonnet-4-6
Timeout: 600s
Knowledge: project-context only (minimal — preserves fresh perspective)
```

**Iteration:** If reviewer requests changes, Analyst revises (max 3 iterations).

### 4. Human Gate: Spec Approval

**Actor:** Human  
**Input:** Approved spec PR  
**Output:** Merged spec PR

The supervisor adds `awaiting-approval` label and posts a summary. Human reviews and merges the spec PR to signal approval.

### 5. Implementation (Implementer / Codex)

**Actor:** Implementer via Codex ACP  
**Input:** Merged OpenSpec, feature branch  
**Output:** Draft PR with implementation

The Implementer (Codex):
1. Reads the OpenSpec as the contract
2. Creates feature branch and opens draft PR
3. Implements code following the spec phases
4. Writes tests alongside implementation
5. Runs pre-commit validation (format, lint, test, docs)
6. Pushes incremental commits referencing the requirement issue
7. Marks PR as "Ready for Review" when complete

```yaml
Runtime: acp
Agent: codex
Timeout: 1800s (30 min)
Knowledge: OpenSpec + project-context + patterns
Working Dir: {PROJECT_ROOT}
```

### 6. CI Monitoring

**Actor:** Supervisor  
**Input:** Implementation PR  
**Output:** CI green (or escalation after 3 fix attempts)

The supervisor:
1. Polls CI status via `gh run list --branch <branch>`
2. On failure, extracts logs via `gh run view <id> --log-failed`
3. For trivial fixes (formatting, imports): spawns Implementer with targeted fix
4. For test failures: spawns Implementer with error context
5. Updates `workflow-state.json` with CI status

**Iteration:** Max 3 CI fix attempts before escalating to human.

### 7. Parallel Agents (Large Tier)

For **large** tier workflows, these agents run in parallel during implementation:

#### Chaos Agent (Ralph)

**Actor:** Chaos Ralph (subagent runtime)  
**Input:** Implementation PR, project context, chaos catalog  
**Output:** PR comment with chaos findings

Ralph performs adversarial testing:
- Edge cases and boundary conditions
- Error path stress testing
- Resource exhaustion scenarios
- Race conditions and concurrency issues

```yaml
Runtime: subagent
Model: claude-sonnet-4-6
Timeout: 600s
Knowledge: project-context + chaos-catalog
```

#### Security Auditor

**Actor:** Security Auditor (subagent runtime)  
**Input:** Implementation PR diff, compliance requirements  
**Output:** PR comment with security findings

The Security Auditor reviews:
- Attack surface changes
- Authentication/authorization patterns
- Input validation and sanitization
- Cryptographic usage
- Dependency security

```yaml
Runtime: subagent
Model: claude-sonnet-4-6
Timeout: 600s
Knowledge: project-context + compliance + chaos-catalog
```

**Note:** HIGH/CRITICAL findings trigger immediate notification to parent session with `⚠️ SECURITY:` prefix.

### 8. Spec Drift Check

**Actor:** Supervisor  
**Input:** Implementation PR, OpenSpec  
**Output:** `spec/<feature>/spec-delta.md`

After CI is green, the supervisor compares implementation against spec:
- Items implemented but not in spec (scope creep)
- Items in spec but not implemented (gaps)

Significant drift triggers human notification before proceeding.

### 9. PR Review (PR Reviewer / Claude Code)

**Actor:** PR Reviewer via Claude Code ACP  
**Input:** Implementation PR, OpenSpec, review checklist  
**Output:** GitHub PR review (Approve / Request Changes)

The PR Reviewer (Claude Code):
1. Reviews diff via `gh pr diff`
2. Validates against OpenSpec sections
3. Checks: correctness, error handling, test coverage, idiomatic code
4. Uses Fix-First heuristic: AUTO-FIX mechanical issues, ASK for ambiguous
5. Submits PR review via `gh pr review`

```yaml
Runtime: acp
Agent: claude-code
Timeout: 900s (15 min)
Knowledge: OpenSpec + project-context only
Working Dir: {PROJECT_ROOT}
Mode: Read-only (no file edits — review only)
```

**Iteration:** If reviewer requests changes, Implementer revises (max 3 iterations).

### 10. Human Gate: Merge Approval

**Actor:** Human  
**Input:** Approved implementation PR  
**Output:** Merged implementation PR

The supervisor adds `awaiting-merge` label and posts a summary including:
- Implementation complete status
- Test results
- Security/Chaos findings (if any)
- Link to spec for reference

Human reviews and merges to signal approval.

### 11. Release (Optional)

**Actor:** Supervisor  
**Input:** Merged PR, release configuration  
**Output:** Git tag, release workflow triggered

If the workflow includes a release stage:
1. Verify release checklist (CI green, CHANGELOG, version bump)
2. Create and push version tag
3. Monitor release workflow
4. Update workflow state with release version

### 12. Completion

**Actor:** Supervisor  
**Output:** Closed issue, updated knowledge, journal entry

Post-completion tasks:
1. Close requirement issue with completion summary
2. Archive workflow metrics to history
3. Update knowledge files (decisions.json, chaos-findings.json)
4. Regenerate summary files (patterns.md, chaos-catalog.md)
5. Commit final journal entry
6. Notify parent session

## Agent Roster Summary

| Role | Runtime | Agent/Model | Timeout | Purpose |
|------|---------|-------------|---------|---------|
| Supervisor | — | — | — | Orchestration, state management |
| Analyst | subagent | claude-opus-4-6 | 900s | Requirements analysis, OpenSpec |
| Spec Reviewer | subagent | claude-sonnet-4-6 | 600s | Spec quality review |
| Implementer | **ACP** | **Codex** | 1800s | Code implementation |
| PR Reviewer | **ACP** | **Claude Code** | 900s | Code review |
| Chaos Ralph | subagent | claude-sonnet-4-6 | 600s | Adversarial testing |
| Security Auditor | subagent | claude-sonnet-4-6 | 600s | Security review |

## Workflow Tiers

| Tier | Scope | Agents Used |
|------|-------|-------------|
| **Small** | Bug fix, config, <50 LOC | Implementer + PR Reviewer only |
| **Medium** | Feature, refactor, 50-500 LOC | Analyst + Spec Reviewer + Implementer + PR Reviewer |
| **Large** | New system, architecture, >500 LOC | All agents including Security Auditor + Chaos Ralph |

## Circuit Breakers

The pipeline includes safeguards to prevent runaway agent activity:

| Limit | Threshold | Action |
|-------|-----------|--------|
| Agent spawns | Max 15 per workflow | Pause, report to human |
| Wall-clock time | Max 4 hours | Checkpoint, notify human |
| Feedback iterations | Max 3 per loop | Escalate to human |
| CI fix attempts | Max 3 | Escalate to human |

## State Machine

```
idle → issue-created → analyzing → spec-pr ⟲ (max 3)
  → awaiting-spec-approval → implementing
  → ci-monitoring ⟲ (max 3) → spec-drift-check
  → pr-review ⟲ (max 3) → awaiting-merge-approval
  → release (optional) → complete
```

## GitHub Integration

All workflow steps are tracked through **GitHub Issues and Pull Requests**:

| Artifact | Location |
|----------|----------|
| Requirements | Issue with `requirement` label |
| Specification | PR: `spec/<feature>/openspec.md` |
| Implementation | PR: `feature/<feature>` branch |
| Reviews | GitHub PR review comments |
| Status updates | Issue/PR comments tagged by role |

Agent comments are tagged with role: `**[Supervisor]**`, `**[Analyst]**`, `**[Reviewer]**`, etc.

## Knowledge Flow

```
┌──────────────────────────────────────────────────────────────────┐
│                         KNOWLEDGE BASE                            │
├──────────────────────────────────────────────────────────────────┤
│ Tier 1 (Summary — always injected)                                │
│  ├── project-context.md    → All agents                          │
│  ├── patterns.md           → Implementer                          │
│  ├── chaos-catalog.md      → Chaos Ralph                          │
│  ├── known-issues.md       → Analyst                              │
│  └── compliance.md         → Implementer, Security Auditor        │
├──────────────────────────────────────────────────────────────────┤
│ Tier 2 (Structured — on demand)                                   │
│  ├── decisions.json        → Analyst (architectural history)      │
│  └── chaos-findings.json   → Chaos Ralph (recurrence check)       │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│                       WORKFLOW OUTPUT                             │
│  spec/<feature>/openspec.md                                       │
│  spec/<feature>/spec-delta.md                                     │
│  journal/YYYY-MM-DD.md                                            │
│  → Extracted to knowledge/ after completion                       │
└──────────────────────────────────────────────────────────────────┘
```

## Related Documentation

- [Supervisor Template](../workspace/templates/forge-supervisor.md) — Full supervisor prompt
- [Agent Templates](../workspace/templates/agents/) — Individual agent prompts
- [Review Checklist](rules/review-checklist.md) — PR review criteria
- [Escalation Protocol](rules/escalation-protocol.md) — When and how to escalate
- [CI Monitoring](rules/ci-monitoring.md) — CI failure handling
