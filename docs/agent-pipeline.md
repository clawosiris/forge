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
   │ (Opus)  │   OpenSpec    │ REVIEWER  │   Approved    │ (Codex)    │
   └─────────┘                │ (Sonnet)  │    Spec       └────────────┘
        │                     └───────────┘                     │
        │                           │                           ▼
        │                           │                    ┌────────────┐
        │                           │                    │ CI MONITOR │
        │                           │                    └────────────┘
        │                    ┌──────┴──────┐                    │
        │                    ▼             ▼                    ▼
        │             ┌──────────┐  ┌───────────┐        ┌────────────┐
        │             │ CHAOS    │  │ SECURITY  │        │ PR REVIEWER│
        │             │ RALPH    │  │ AUDITOR   │        │ (Claude    │
        │             │ (o3-mini)│  │ (Sonnet)  │        │  Code)     │
        │             └──────────┘  └───────────┘        └────────────┘
        │                    │             │                    │
        │                    └──────┬──────┘                    ▼
        │                           ▼                    ┌────────────┐
        │                    ┌────────────┐              │  GITHUB    │
        └────────────────────│   HUMAN    │◀─────────────│  ISSUES    │
                             │   GATES    │              └────────────┘
                             └────────────┘
```

## Design Principles

### Model Diversity as Defense-in-Depth

The pipeline deliberately uses **different model families** for generation vs review:

- **OpenAI (via Codex)** for implementation — autonomous coding with full-auto mode
- **Anthropic (via Claude Code)** for review — careful analysis with read-only constraints
- **o3-mini** for chaos testing — reasoning model for adversarial exploration

This provides complementary coverage: different training data means different blind spots, and reviewers naturally find flaws in other models' outputs.

### Mandatory Harness Usage

**Never call LLM APIs directly** for implementation or review tasks:

| Task | Required Harness | Why |
|------|------------------|-----|
| Implementation | **Codex CLI/ACP** | Provides workspace isolation, file ops, test execution, worklog |
| Code Review | **Claude Code CLI/ACP** | Provides repo access, read-only mode, GitHub CLI integration |

The harnesses enforce constraints (workspace boundaries, commit conventions, review-only mode) that raw API calls cannot provide.

### Review Findings as GitHub Issues

PR review findings are filed as GitHub Issues for tracking:

```bash
gh issue create \
  --title "[Review] <finding-title>" \
  --label "review-finding" --label "<severity>" \
  --body "<structured finding with location, description, fix>"
```

This creates a trackable workflow for resolving review findings and provides an audit trail.

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
Model: claude-sonnet-4
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

**Actor:** Implementer via **Codex ACP or CLI** (MANDATORY)  
**Input:** Merged OpenSpec, feature branch  
**Output:** Draft PR with implementation

**Always route GPT through Codex** — never call GPT models directly. Codex provides:
- Workspace isolation and file operations
- Shell access for tests and builds
- Commit convention enforcement
- Worklog maintenance for crash recovery

The Implementer (Codex):
1. Reads the OpenSpec as the contract
2. Creates feature branch and opens draft PR
3. Implements code following the spec phases
4. Writes tests alongside implementation
5. Maintains `worklog.md` with progress tracking
6. Runs pre-commit validation (format, lint, test, docs)
7. Pushes incremental commits referencing the requirement issue
8. Marks PR as "Ready for Review" when complete

```yaml
Runtime: acp
Agent: codex (gpt-5.3-codex)
Timeout: 1800s (30 min)
Knowledge: OpenSpec + project-context + patterns
Working Dir: {PROJECT_ROOT}
```

**Spawning options:**
```javascript
// Via ACP (preferred for orchestration)
sessions_spawn({
  runtime: "acp",
  agentId: "codex",
  mode: "run",
  task: "<implementation prompt>",
  cwd: "{PROJECT_ROOT}",
  runTimeoutSeconds: 1800
})

// Via CLI (alternative, e.g., from sandboxed agents)
exec({ command: "codex exec --full-auto '<prompt>'" })
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

Ralph performs adversarial testing using a **reasoning model** (o3-mini) to systematically explore edge cases:
- Boundary conditions and type confusion
- Error path stress testing
- Resource exhaustion scenarios
- Race conditions and concurrency issues
- Injection vectors

```yaml
Runtime: subagent
Model: o3-mini  # Reasoning model for adversarial exploration
Timeout: 600s
Knowledge: project-context + chaos-catalog
```

#### Security Auditor

**Actor:** Security Auditor (subagent runtime)  
**Input:** Implementation PR diff, compliance requirements  
**Output:** PR comment with security findings

The Security Auditor reviews using a structured checklist:
- Attack surface changes
- Authentication/authorization patterns
- Input validation and sanitization
- Cryptographic usage
- Dependency security

```yaml
Runtime: subagent
Model: claude-sonnet-4
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

**Actor:** PR Reviewer via **Claude Code ACP or CLI** (MANDATORY)  
**Input:** Implementation PR, OpenSpec, review checklist  
**Output:** GitHub PR review + GitHub Issues for findings

**Always route Claude through Claude Code** — never call Claude directly. Claude Code provides:
- Repo access and file reading
- GitHub CLI integration for PR reviews
- Read-only mode (no accidental code modifications)

The PR Reviewer (Claude Code):
1. Reviews diff via `gh pr diff`
2. Validates against OpenSpec sections
3. Checks: correctness, error handling, test coverage, idiomatic code
4. Uses Fix-First heuristic: AUTO-FIX mechanical issues, ASK for ambiguous
5. **Files each finding as a GitHub Issue** with `review-finding` label
6. Submits PR review via `gh pr review` linking to created issues

```yaml
Runtime: acp
Agent: claude-code (claude-sonnet-4)
Timeout: 900s (15 min)
Knowledge: OpenSpec + project-context only
Working Dir: {PROJECT_ROOT}
Mode: Read-only (REVIEW MODE — no file edits)
```

**Spawning options:**
```javascript
// Via ACP (preferred for orchestration)
sessions_spawn({
  runtime: "acp",
  agentId: "claude-code",
  mode: "run",
  task: "<review prompt with REVIEW MODE instruction>",
  cwd: "{PROJECT_ROOT}",
  runTimeoutSeconds: 900
})

// Via CLI (alternative)
exec({ command: "claude --print '<review prompt>'" })
```

**Filing findings as issues:**
```bash
gh issue create \
  --title "[Review] <finding-title>" \
  --label "review-finding" --label "<severity>" \
  --body "## Finding from PR #<pr> review
**Severity:** HIGH|MEDIUM|LOW
**Location:** \`file:line\`
### Description
<issue description>
### Suggested Fix
<recommendation>"
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
**Output:** Closed issue, updated knowledge, evidence bundle, journal entry

Post-completion tasks:
1. Close requirement issue with completion summary
2. Archive workflow metrics to history
3. Update knowledge files (decisions.json, chaos-findings.json)
4. Regenerate summary files (patterns.md, chaos-catalog.md)
5. **Generate evidence bundle** (High/Critical tier mandatory, Medium optional)
6. Commit final journal entry
7. Notify parent session

## Evidence Bundle

For audit-readiness, Forge generates an immutable evidence bundle at workflow completion.

**Location:** `evidence/<feature-name>/evidence-bundle.json`

**Contents:**
- Spec version and approval metadata
- Implementation PR, commits, AI usage flags
- Review approval with human reviewer ID
- Role separation verification
- Critical-tier reproduction evidence
- CI control outcomes (lint, SAST, license scan, etc.)
- Finding lifecycle (issue → closure)
- SBOM/license artifacts
- Bundle hash for integrity

**Tier requirements:**
| Tier | Evidence Bundle |
|------|-----------------|
| Critical | Mandatory |
| High | Mandatory |
| Medium | Recommended |
| Low | Not required |

**Schema:** `docs/schemas/evidence-bundle.schema.json`

## Agent Roster Summary

| Role | Runtime | Agent/Model | Timeout | Purpose |
|------|---------|-------------|---------|---------|
| Supervisor | — | — | — | Orchestration, state management |
| Analyst | subagent | claude-opus-4-6 | 900s | Requirements analysis, OpenSpec |
| Spec Reviewer | subagent | claude-sonnet-4 | 600s | Spec quality review |
| Implementer | **ACP (Codex)** | **gpt-5.3-codex** | 1800s | Code implementation |
| PR Reviewer | **ACP (Claude Code)** | **claude-sonnet-4** | 900s | Code review → GitHub Issues |
| Chaos Ralph | subagent | **o3-mini** | 600s | Adversarial testing |
| Security Auditor | subagent | claude-sonnet-4 | 600s | Security review |

### Model Selection Rationale

| Model | Roles | Why |
|-------|-------|-----|
| **claude-opus-4-6** | Analyst | Deep reasoning for complex requirements; initial spec quality determines downstream success |
| **claude-sonnet-4** | Spec Reviewer, PR Reviewer, Security Auditor | Careful analysis, nuance, instruction-following; cost-effective for review tasks |
| **gpt-5.3-codex** | Implementer | Optimized for autonomous coding; edit→test→fix loop; different family enables complementary review |
| **o3-mini** | Chaos Ralph | Reasoning model excels at adversarial thinking; systematic exploration of edge cases |

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
| Role Routing | Requirement issue `role:*` label |
| Specification | PR: `spec/<feature>/openspec.md` |
| Implementation | PR: `feature/<feature>` branch |
| Reviews | GitHub PR review comments |
| Review Findings | Issues with `review-finding` label |
| Status updates | Issue/PR comments tagged by role |

### Role assignment labels

Forge supports assigning issue ownership to agent roles using labels:
- `role:analyst`
- `role:spec-reviewer`
- `role:implementer`
- `role:pr-reviewer`
- `role:security-auditor`
- `role:chaos-ralph`
- `role:supervisor`

Supervisor rule: keep exactly one active `role:*` label on the requirement issue and update it on each state transition. Role labels are the source of truth for which agent should run next.

Optional: mirror role labels to GitHub assignees with `gh issue edit --add-assignee` if a role→user map is configured.

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

## Worklog Pattern

For extended implementation sessions, agents maintain a `worklog.md`:

```markdown
# Worklog: <feature-name>
**Last Updated:** YYYY-MM-DD HH:MM

## Mission
One-line goal.

## Progress Summary
✅ Completed items
🔄 In progress  
⬜ Not started

## Current State
What's working, what's not, where you are.

## Key Learnings
What you discovered that wasn't obvious.

## Next Steps
What to do next (for resumption).
```

This enables crash recovery and provides visibility into agent progress.

## Related Documentation

- [Supervisor Template](../workspace/templates/forge-supervisor.md) — Full supervisor prompt
- [Agent Templates](../workspace/templates/agents/) — Individual agent prompts
- [Review Checklist](rules/review-checklist.md) — PR review criteria
- [Escalation Protocol](rules/escalation-protocol.md) — When and how to escalate
- [CI Monitoring](rules/ci-monitoring.md) — CI failure handling
- [BSI/ANSSI Compliance](https://codeberg.org/llnvd/pages/src/branch/main/content/gists/openclaw/human-validation-spec-test-driven-dev.md) — Human validation proposal
