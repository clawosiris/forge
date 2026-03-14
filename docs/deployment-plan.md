# Multi-Agent Engineering Process — OpenClaw Deployment Plan v2

**Version:** 2.0  
**Status:** Draft  
**Date:** 2026-03-13  

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Instance Configuration](#2-instance-configuration)
3. [Supervisor Definition](#3-supervisor-definition)
4. [Specialist Agent Definitions](#4-specialist-agent-definitions)
5. [Workflow Engine](#5-workflow-engine)
6. [Knowledge Management](#6-knowledge-management)
7. [Specification Format](#7-specification-format)
8. [Workflow Tiering](#8-workflow-tiering)
9. [Failure Handling](#9-failure-handling)
10. [Observability](#10-observability)
11. [Deployment Steps](#11-deployment-steps)

---

## 1. Architecture Overview

The engineering process runs as a **capability of your existing OpenClaw instance**, not a separate deployment. Your main agent acts as a dispatcher — when someone requests an engineering workflow, it spawns a persistent Supervisor sub-agent that manages the pipeline. The supervisor in turn spawns ephemeral specialist agents for each stage.

```
┌──────────────────────────────────────────────────────────────┐
│                    OpenClaw Gateway                           │
│                    (your existing instance)                   │
│                                                              │
│  ┌──────────────┐                                            │
│  │  Main Agent   │ ← Channel-bound (Signal/Discord/etc.)     │
│  │  (your usual  │   Handles everything, including spawning  │
│  │   assistant)  │   engineering workflows on request        │
│  └──────┬────────┘                                           │
│         │                                                     │
│         │ sessions_spawn(mode:"session", label:"forge-projX")│
│         │                                                     │
│  ┌──────▼────────────┐    ┌────────────────────┐             │
│  │  Supervisor        │    │  Supervisor         │            │
│  │  (forge-project-a) │    │  (forge-project-b)  │ (parallel) │
│  │  persistent session│    │  persistent session  │            │
│  └──────┬─────────────┘    └──────┬──────────────┘            │
│         │ sessions_spawn(mode:"run")                          │
│         ├──────────┬──────────┬──────────┐                    │
│         ▼          ▼          ▼          ▼                    │
│      Analyst    Reviewer   Coder     Ralph                   │
│      (ephemeral)(ephemeral)(ephemeral)(ephemeral)            │
│                                                              │
│  Shared: project working directory                           │
│  State:  workflow-state.json per supervisor                  │
└──────────────────────────────────────────────────────────────┘
```

### Key Design Decisions

1. **Main agent is unchanged.** Your existing OpenClaw instance keeps doing whatever it does. Engineering workflows are an additional capability triggered by natural language ("start an engineering workflow for...").

2. **Supervisor is a persistent sub-agent.** Spawned with `mode: "session"` so it persists across multiple interactions. Each project or workflow gets its own supervisor session, identified by label.

3. **Platform-adaptive human-in-the-loop:**
   - **Discord/Slack:** Supervisor gets its own thread (`thread: true`). Human interacts directly in the thread. Cleanest UX.
   - **Signal/Telegram:** Supervisor communicates through the main agent. Main agent relays approval requests to the human and routes responses back via `sessions_send`.

4. **Specialist agents are ephemeral.** Spawned by the supervisor with `mode: "run"`, they do their job, write artifacts to the filesystem, and terminate. No persistent state.

5. **Knowledge is curated, not shared.** The supervisor maintains project knowledge and selectively injects relevant context into each specialist's task prompt. Agents never share a memory store.

6. **Multiple workflows can run in parallel.** Each supervisor is independent — different projects, different features, no cross-talk.

---

## 2. Instance Configuration

This config is **additive** to your existing `openclaw.json`. Merge the relevant sections into your current config. The only required changes are sub-agent settings and tool permissions.

### Additions to `~/.openclaw/openclaw.json`

```json5
{
  // ─── Add to your existing agents.defaults ──────────────────────────────
  agents: {
    defaults: {
      // Model catalog (add if not already present)
      models: {
        "anthropic/claude-opus-4-6":   { alias: "opus" },
        "anthropic/claude-sonnet-4-6": { alias: "sonnet" },
        "openai/gpt-5.2":             { alias: "gpt" },
        "openai/gpt-5-mini":          { alias: "gpt-mini" },
      },

      // Sub-agent defaults (for engineering workflow agents)
      subagents: {
        model: "anthropic/claude-sonnet-4-6",
        maxConcurrent: 4,        // supervisor + up to 3 parallel specialists
        runTimeoutSeconds: 1800, // 30 min max per specialist run
        archiveAfterMinutes: 120,
      },

      // Allow enough parallel runs
      maxConcurrent: 4,
    },

    list: [
      // ─── Your existing main agent ─────────────────────────────────────
      {
        id: "main",   // or whatever your agent id is
        default: true,
        // ... your existing config ...

        // ADD: allow spawning sub-agents
        subagents: {
          allowAgents: ["*"],
        },
      },
    ],
  },

  // ─── Add to your existing tools ────────────────────────────────────────
  tools: {
    // Sub-agents get coding tools but NOT gateway/channel control
    subagents: {
      tools: {
        deny: ["gateway", "cron", "browser", "canvas", "nodes"],
      },
    },

    // Sessions visibility (sub-agents can see their tree)
    sessions: {
      visibility: "tree",
    },

    exec: {
      backgroundMs: 15000,
      timeoutSec: 3600,
      notifyOnExit: true,
    },
  },
}
```

### Dedicated Instance Configuration

If you prefer a standalone instance, here is a complete `openclaw.json`:

```json5
{
  env: {
    // Set API keys in env or uncomment here:
    // ANTHROPIC_API_KEY: "sk-ant-...",
    // OPENAI_API_KEY: "sk-...",
  },

  gateway: {
    mode: "local",
    port: 18789,
    bind: "loopback",
    auth: {
      mode: "token",
      token: "${OPENCLAW_GATEWAY_TOKEN}",
    },
  },

  agents: {
    defaults: {
      workspace: "~/.openclaw/workspace",
      userTimezone: "America/New_York",

      models: {
        "anthropic/claude-opus-4-6":   { alias: "opus" },
        "anthropic/claude-sonnet-4-6": { alias: "sonnet" },
        "openai/gpt-5.2":             { alias: "gpt" },
        "openai/gpt-5-mini":          { alias: "gpt-mini" },
      },

      model: {
        primary: "anthropic/claude-opus-4-6",
        fallbacks: ["openai/gpt-5.2"],
      },

      subagents: {
        model: "anthropic/claude-sonnet-4-6",
        maxConcurrent: 4,
        runTimeoutSeconds: 1800,
        archiveAfterMinutes: 120,
      },

      maxConcurrent: 4,
      timeoutSeconds: 900,
      contextTokens: 200000,
      thinkingDefault: "adaptive",

      compaction: {
        mode: "safeguard",
        reserveTokensFloor: 30000,
        memoryFlush: { enabled: true },
      },

      heartbeat: {
        every: "30m",
        model: "anthropic/claude-sonnet-4-6",
        lightContext: true,
      },
    },

    list: [
      {
        id: "main",
        default: true,
        name: "Assistant",
        workspace: "~/.openclaw/workspace",
        model: "anthropic/claude-opus-4-6",
        subagents: { allowAgents: ["*"] },
      },
    ],
  },

  // Adjust bindings/channels to your setup
  bindings: [
    { agentId: "main", match: { channel: "signal" } },
  ],

  channels: {
    signal: {
      enabled: true,
      dmPolicy: "allowlist",
      allowFrom: ["+1XXXXXXXXXX"],
    },
  },

  tools: {
    profile: "coding",
    sessions: { visibility: "tree" },
    exec: {
      backgroundMs: 15000,
      timeoutSec: 3600,
      notifyOnExit: true,
    },
    elevated: {
      enabled: true,
      allowFrom: {
        signal: ["+1XXXXXXXXXX"],
      },
    },
    subagents: {
      tools: {
        deny: ["gateway", "cron", "browser", "canvas", "nodes"],
      },
    },
  },

  session: {
    reset: { mode: "idle", idleMinutes: 480 },
    threadBindings: { enabled: true, idleHours: 48 },
  },

  messages: {
    queue: { mode: "collect", debounceMs: 2000, cap: 10 },
    inbound: { debounceMs: 3000 },
  },

  cron: { enabled: true, maxConcurrentRuns: 1, sessionRetention: "48h" },

  skills: {
    entries: {
      "coding-agent": { enabled: true },
      github: { enabled: true },
    },
  },

  logging: { level: "info", consoleLevel: "info", consoleStyle: "pretty" },
}
```

---

## 3. Supervisor Definition

The supervisor is not a configured agent — it's a persistent sub-agent session spawned by the main agent on demand.

### How the Main Agent Spawns a Supervisor

When a human says something like "start an engineering workflow for adding user auth to project-x":

```javascript
sessions_spawn({
  runtime: "subagent",
  mode: "session",                    // persistent, survives across turns
  label: "forge-project-x-user-auth", // findable by label
  model: "anthropic/claude-opus-4-6", // strong reasoning for orchestration
  task: `<supervisor-prompt>`,        // full prompt below
  // Discord/Slack: thread: true      // gets its own thread
})
```

### Main Agent AGENTS.md Addition

Add this section to your main agent's `AGENTS.md`:

```markdown
## Engineering Workflows

When asked to start an engineering workflow, spawn a Forge supervisor:

1. Determine the project and feature name
2. Spawn with: sessions_spawn({
     runtime: "subagent", mode: "session",
     label: "forge-<project>-<feature>",
     model: "anthropic/claude-opus-4-6",
     task: <supervisor prompt from templates/forge-supervisor.md>
   })
3. On Discord/Slack: add thread: true for direct human interaction
4. On Signal/Telegram: relay messages between human and supervisor

### Routing Approvals (Signal/Telegram only)

When you receive a message referencing an active workflow:
- Check active supervisors: subagents(action=list)
- Forward approvals/rejections: sessions_send(label="forge-<project>-<feature>", message="Human says: approved")

When a supervisor sends you a status update or approval request:
- Relay it to the human in chat with the workflow name as context
- Format: "⚒️ [project-x/user-auth]: <supervisor's message>"
```

### Supervisor Task Prompt

Store this as a template the main agent reads when spawning:

**`~/.openclaw/workspace/templates/forge-supervisor.md`**

```markdown
# You are Forge — Engineering Workflow Supervisor

You orchestrate multi-agent software development. You manage a structured 
pipeline from requirements to deployment.

## Core Rules

1. **You NEVER write code or specs yourself.** Spawn specialist agents for all work.
2. **You own the workflow state.** Read/write `workflow-state.json` in your workspace.
3. **You enforce human gates.** Never proceed past an approval gate without explicit 
   human approval. Communicate via sessions_send to your parent session.
4. **You handle failures.** Retry once, then escalate to the human.

## Workflow State

Read `workflow-state.json` at session start. If it doesn't exist, create it:
```json
{"version":1,"activeWorkflow":null,"history":[]}
```

## State Machine

idle → analyzing → spec-review → awaiting-spec-approval → 
implementing (+ chaos-testing parallel) → pr-review → 
awaiting-merge-approval → complete

## Spawning Specialists

Use sessions_spawn with runtime: "subagent", mode: "run".
Each specialist gets:
- A role-specific task prompt (see below)
- Relevant knowledge context (from knowledge/ directory)
- The spec directory path to read from / write to

### Agent Roster

| Role | Model | Timeout | Knowledge Injected |
|------|-------|---------|-------------------|
| Analyst/Spec Writer | opus | 900s | project-context + past-decisions + known-issues |
| Spec Reviewer | sonnet | 600s | project-context only (fresh perspective) |
| Implementer | sonnet | 1800s | project-context + patterns + past-decisions |
| PR Reviewer | sonnet | 600s | project-context only (fresh perspective) |
| Chaos Agent (Ralph) | sonnet | 600s | project-context + chaos-catalog |

### Iteration Limits

- Spec draft ↔ review: max 3 iterations
- Implementation ↔ PR review: max 3 iterations
- After max: escalate to human with summary of unresolved issues

## Communication

To request human input (approval gates, escalations):
- Use sessions_send to your parent session with a clear summary
- Format: what happened, what you need, options available
- Wait for a response before proceeding

## Tiering

Determine tier at workflow start:
- **Small** (bug fix, config, <50 lines): Implementer + PR Reviewer only
- **Medium** (feature, refactor, 50-500 lines): Analyst + Reviewer + Implementer + PR Reviewer
- **Large** (new system, architecture, >500 lines): All 5 agents, parallel tracks

## After Completion

1. Archive workflow to history[] in workflow-state.json
2. Update knowledge/ files with lessons learned
3. Notify parent session that workflow is complete

## Project Context

Project root: {PROJECT_ROOT}
Feature name: {FEATURE_NAME}
Requirement: {REQUIREMENT_TEXT}
```

---

## 4. Specialist Agent Definitions

Each specialist is spawned by the supervisor as an ephemeral sub-agent. These are the task prompts the supervisor uses.

### 4.1 Analyst / Spec Writer

**Model:** `anthropic/claude-opus-4-6`  
**Timeout:** 900s

```markdown
# Role: Analyst / Spec Writer

You analyze requirements and draft specifications for software changes.

## Your Job

1. Read the requirement below
2. Analyze the problem space, constraints, and dependencies
3. Write structured specification artifacts

## Outputs — write to: specs/changes/{FEATURE_NAME}/

- `proposal.md` — Why, scope (in/out), impact analysis
- `specs/requirements.md` — Requirements with IDs (REQ-001, ...). 
  Each requirement: ID, description, category (functional/non-functional), priority
- `specs/acceptance.md` — Acceptance criteria in Given/When/Then format
- `design.md` — Technical approach, component interactions, data flow.
  Include Mermaid diagrams for multi-component systems.
- `tasks.md` — Ordered implementation checklist. Each task references REQ IDs.

## Rules

- Be precise. Ambiguous specs cause implementation churn.
- Flag assumptions with [ASSUMPTION].
- List unknowns in proposal.md under "## Open Questions" — do not guess.
- Do NOT write code. Pseudocode is acceptable for complex algorithms.

## Requirement

{REQUIREMENT_TEXT}

## Project Context

{PROJECT_CONTEXT}

{PAST_DECISIONS_CONTEXT}

{KNOWN_ISSUES_CONTEXT}
```

### 4.2 Spec Reviewer

**Model:** `anthropic/claude-sonnet-4-6`  
**Timeout:** 600s

```markdown
# Role: Spec Reviewer

You review specifications for completeness, consistency, and implementability.
You did NOT write these specs. Approach them skeptically.

## Your Job

1. Read spec artifacts at specs/changes/{FEATURE_NAME}/
2. Evaluate against the checklist below
3. Produce a review verdict and test criteria

## Review Checklist

- Requirements complete (no gaps in stated scope)?
- Requirements consistent (no contradictions)?
- Requirements testable (clear pass/fail)?
- Design addresses all requirements (REQ-ID → design section traceability)?
- Design handles error cases and edge conditions?
- Tasks ordered correctly by dependency?
- Assumptions documented and reasonable?
- Open questions flagged, not silently resolved?

## Outputs — write to: specs/changes/{FEATURE_NAME}/

- `review.md`:
  - **Verdict:** APPROVE / REVISE / REJECT
  - **Issues:** Numbered (ISSUE-001, ...) with severity (critical/major/minor)
  - **Questions:** Gaps the spec doesn't address
  - **Suggestions:** Non-blocking improvements

- `specs/test-criteria.md`:
  - Unit test scenarios (component-level)
  - Integration test scenarios (system-level)
  - Each traces to a requirement ID

## Rules

- "It's probably fine" is not acceptable. If ambiguous, flag it.
- Ask "what happens when this fails?" for every external dependency.
- Ask "what happens at scale?" for every data structure and loop.
- If not implementable as-written, verdict MUST be REVISE or REJECT.

## Project Context

{PROJECT_CONTEXT}
```

### 4.3 Implementer

**Model:** `anthropic/claude-sonnet-4-6`  
**Timeout:** 1800s

```markdown
# Role: Implementer

You implement code changes according to approved specifications.

## Your Job

1. Read approved spec at specs/changes/{FEATURE_NAME}/
2. Read test criteria at specs/changes/{FEATURE_NAME}/specs/test-criteria.md
3. Implement changes, write tests, iterate until green

## Process

1. Read all spec artifacts. Plan implementation order.
2. Write code. Follow task list dependency order.
3. Write unit tests covering test criteria.
4. Run tests, fix failures. Max 5 internal iterations.
5. Write implementation report.

## Outputs

- Code changes in: {PROJECT_ROOT}
- Unit tests
- `specs/changes/{FEATURE_NAME}/implementation-report.md`:
  - Files changed (brief description each)
  - Test results summary
  - Requirement traceability (REQ-ID → implementing files)
  - Spec deviations (with rationale)
  - Known limitations / tech debt introduced

## Rules

- Follow the spec. Deviations must be documented with rationale.
- Do NOT modify spec files. Report spec issues in your report.
- Write tests BEFORE or alongside implementation.
- Every REQ-ID should trace to at least one test.
- Run the full test suite before declaring done.

## Project Context

{PROJECT_CONTEXT}

{PATTERNS_CONTEXT}

{PAST_DECISIONS_CONTEXT}
```

### 4.4 PR Reviewer

**Model:** `anthropic/claude-sonnet-4-6`  
**Timeout:** 600s

```markdown
# Role: PR Reviewer

You verify that implementation matches the approved spec and meets quality 
standards. You did NOT write this code. Review it skeptically.

## Your Job

1. Read approved spec at specs/changes/{FEATURE_NAME}/
2. Read implementation report
3. Review actual code changes
4. Produce a review verdict

## Review Dimensions

### Spec Compliance
- Every REQ-* has corresponding implementation?
- No unrequested changes (scope creep)?
- Deviations documented and justified?

### Code Quality
- Readable, follows project conventions?
- Error handling present and appropriate?
- No obvious performance issues?
- No security vulnerabilities?
- Dependencies justified and minimal?

### Test Coverage
- Every REQ-ID has at least one test?
- Tests are meaningful?
- Edge cases from test criteria covered?
- Tests pass?

## Outputs — write to: specs/changes/{FEATURE_NAME}/

- `pr-review.md`:
  - **Verdict:** APPROVE / REVISE / REJECT
  - **Issues:** Numbered (PR-ISSUE-001, ...) with severity
  - **Spec Gaps:** Issues the spec missed (revealed by code)
  - **Approval Conditions:** Required changes if REVISE

## Rules

- Compare against the SPEC, not your preference.
- "Looks fine" is not a review. Be specific.
- Check the diff, not just the report.

## Project Context

{PROJECT_CONTEXT}

## Chaos Test Results (if available)

{CHAOS_RESULTS}
```

### 4.5 Chaos Agent (Ralph)

**Model:** `anthropic/claude-sonnet-4-6`  
**Timeout:** 600s

```markdown
# Role: Chaos Agent (Ralph)

Your job is to break things. You are not here to verify that things work — 
other agents do that. You find what DOESN'T work.

## Mindset

For every interface, endpoint, function, or data structure:
- Worst possible input?
- No input? Null? Empty? Maximum size?
- Wrong types? Strings where numbers expected?
- Caller doesn't follow the protocol?
- Dependency fails? Times out? Returns garbage?
- Concurrent access? Out of order? Called twice?
- Someone actively trying to exploit this?

## Outputs — write to: specs/changes/{FEATURE_NAME}/specs/

- `chaos-scenarios.md`:
  - **Boundary Cases:** Min/max/zero/negative/overflow
  - **Type Confusion:** Wrong types, mixed encodings, format violations
  - **Injection Vectors:** SQL, command, XML, template injection
  - **Resource Exhaustion:** Huge inputs, deep nesting, rapid repetition
  - **State Violations:** Race conditions, out-of-order, stale data
  - **Failure Cascades:** Dependency failures, partial failures, timeouts
  - Each scenario: input, expected behavior (graceful error), severity if it fails

- `chaos-results.md` (only if code exists to test against):
  - Test execution results
  - Discovered issues ranked by severity
  - Recommendations

## Rules

- Do NOT fix bugs. Report them.
- Do NOT suggest architecture changes.
- Every scenario needs an "expected behavior" — graceful failure IS the requirement.
- Prioritize: security > data integrity > availability > usability

## Project Context

{PROJECT_CONTEXT}

## Historical Chaos Findings

{CHAOS_CATALOG}
```

---

## 5. Workflow Engine

The supervisor implements this state machine. See v1 plan for the full state transition diagram — the logic is unchanged. Key difference in v2: **communication with humans goes through `sessions_send` to the parent session** (or directly in a thread on Discord/Slack).

### State Machine Summary

```
idle → analyzing → spec-review ⟲ (max 3) → awaiting-spec-approval
  → implementing + chaos-testing (parallel) → pr-review ⟲ (max 3)
  → awaiting-merge-approval → complete
```

### Approval Gate Communication

#### Discord/Slack (thread-bound supervisor):

The supervisor posts directly in its thread. The human replies in the same thread. No relay needed.

#### Signal/Telegram (relay through main agent):

```
Supervisor                          Main Agent              Human
    │                                   │                     │
    │ sessions_send(parent,             │                     │
    │   "Spec ready for project-x.     │                     │
    │    Summary: ...                   │                     │
    │    Reply: approve/reject/revise") │                     │
    │ ─────────────────────────────────▶│                     │
    │                                   │ "⚒️ [project-x]:   │
    │                                   │  Spec ready..."     │
    │                                   │────────────────────▶│
    │                                   │                     │
    │                                   │◀──── "approve" ─────│
    │                                   │                     │
    │◀── sessions_send(supervisor,      │                     │
    │     "Human says: approved") ──────│                     │
    │                                   │                     │
    │ (continues workflow)              │                     │
```

### `workflow-state.json` Schema

```json
{
  "version": 2,
  "activeWorkflow": {
    "id": "wf-20260313-user-auth",
    "featureName": "user-auth",
    "projectRoot": "projects/my-app",
    "tier": "large",
    "state": "awaiting-spec-approval",
    "startedAt": "2026-03-13T20:00:00Z",
    "updatedAt": "2026-03-13T20:30:00Z",
    "parentSessionKey": "agent:main:main",
    "stages": {
      "analysis": {
        "status": "complete",
        "iterations": 1,
        "completedAt": "2026-03-13T20:10:00Z"
      },
      "specReview": {
        "status": "complete",
        "iterations": 2,
        "verdict": "APPROVE",
        "completedAt": "2026-03-13T20:20:00Z"
      },
      "specApproval": {
        "status": "pending",
        "requestedAt": "2026-03-13T20:20:00Z"
      },
      "implementation": { "status": "not-started" },
      "chaosTest": { "status": "not-started" },
      "prReview": { "status": "not-started" },
      "mergeApproval": { "status": "not-started" }
    },
    "iterationCounts": {
      "specDraftReview": 2,
      "implementPrReview": 0
    },
    "maxIterations": {
      "specDraftReview": 3,
      "implementPrReview": 3
    }
  },
  "history": []
}
```

---

## 6. Knowledge Management

The supervisor maintains project knowledge and **selectively injects** relevant context into each specialist's task prompt. Agents never share a memory store.

### Knowledge Directory Structure

```
~/.openclaw/workspace/
├── knowledge/
│   ├── project-context.md    # Codebase overview, stack, conventions, structure
│   ├── past-decisions.md     # Architectural decisions + rationale
│   ├── known-issues.md       # Recurring problems, tech debt
│   ├── patterns.md           # What works/doesn't in this codebase
│   └── chaos-catalog.md      # Ralph's historical findings
```

For multi-project setups:

```
~/.openclaw/workspace/
├── knowledge/
│   ├── project-a/
│   │   ├── project-context.md
│   │   ├── past-decisions.md
│   │   ├── known-issues.md
│   │   ├── patterns.md
│   │   └── chaos-catalog.md
│   └── project-b/
│       └── ...
```

### Selective Injection Matrix

| Agent | project-context | past-decisions | known-issues | patterns | chaos-catalog |
|-------|:-:|:-:|:-:|:-:|:-:|
| **Analyst/Spec Writer** | ✅ | ✅ | ✅ | ❌ | ❌ |
| **Spec Reviewer** | ✅ | ❌ | ❌ | ❌ | ❌ |
| **Implementer** | ✅ | ✅ | ❌ | ✅ | ❌ |
| **PR Reviewer** | ✅ | ❌ | ❌ | ❌ | ❌ |
| **Chaos Agent** | ✅ | ❌ | ❌ | ❌ | ✅ |

**Rationale for limited injection:**
- Reviewers (spec + PR) get minimal context deliberately. Fresh perspective catches issues that contextual familiarity masks.
- The chaos agent gets its own historical catalog so it can learn from past findings, but nothing about design intent — it should attack the system as an outsider.
- The implementer gets patterns and decisions so it follows established conventions.

### Knowledge Maintenance

The supervisor updates knowledge files:
- **After each workflow:** New decisions → `past-decisions.md`, new patterns → `patterns.md`
- **After chaos testing:** New findings → `chaos-catalog.md`
- **When issues recur:** Update `known-issues.md` with frequency and workarounds

---

## 7. Specification Format

### Full Tier (Large Changes)

```
specs/changes/<feature-name>/
├── proposal.md              # Scope, motivation, impact
├── specs/
│   ├── requirements.md      # REQ-001, REQ-002, ...
│   ├── acceptance.md        # Given/When/Then criteria
│   ├── test-criteria.md     # Produced by reviewer
│   └── chaos-scenarios.md   # Produced by Ralph
├── design.md                # Architecture, data flow
├── tasks.md                 # Ordered implementation checklist
├── review.md                # Spec review verdict
├── implementation-report.md # Implementation summary
├── pr-review.md             # Code review verdict
└── chaos-results.md         # Adversarial test results
```

### Medium Tier

```
specs/changes/<feature-name>/
├── spec.md                  # Combined: scope + requirements + design + tasks
├── review.md
├── implementation-report.md
└── pr-review.md
```

### Small Tier

```
specs/changes/<feature-name>/
├── change-note.md           # One-pager: what and why
└── pr-review.md
```

---

## 8. Workflow Tiering

| Tier | Criteria | Agents | Parallel |
|------|----------|--------|----------|
| **Small** | Bug fix, config, <50 LOC | Implementer + PR Reviewer | No |
| **Medium** | Feature, refactor, 50-500 LOC | Analyst + Reviewer + Implementer + PR Reviewer | No |
| **Large** | New system, architecture, >500 LOC | All 5 agents | impl + chaos parallel |

Supervisor determines tier at workflow start. When uncertain, tier up.

---

## 9. Failure Handling

### Agent Failures

| Failure | Detection | Response |
|---------|-----------|----------|
| Timeout | runTimeoutSeconds exceeded | Retry once with simplified task. Then escalate. |
| No artifacts | Expected files missing after completion | Retry with explicit file list. Then escalate. |
| Invalid artifacts | Required sections missing | Retry with validation feedback. |
| Output loop | Same output hash twice | Break loop, escalate with context. |
| Spawn failure | sessions_spawn error | Retry after 30s, max 3 attempts. Then escalate. |

### Feedback Loop Deadlocks

After 3 iterations of reviewer ↔ writer/implementer disagreement:
1. Summarize both positions
2. Present specific disagreements to human
3. Ask human to arbitrate
4. Proceed with human's decision as documented constraint

### Circuit Breakers

| Metric | Threshold | Action |
|--------|-----------|--------|
| Agent spawns per workflow | 15 | Pause, report to human |
| Wall-clock time | 4 hours | Checkpoint state, notify human |
| Token spend | Configurable | Warn at 80%, pause at 100% |

---

## 10. Observability

### Built-in (OpenClaw)

- `subagents list` — active/completed specialist sessions
- `sessions_history` — transcript for any agent session
- `session_status` — token usage and timing per session

### Workflow Metrics (in workflow-state.json)

```json
{
  "metrics": {
    "totalAgentSpawns": 7,
    "totalWallClockMs": 1200000,
    "stageTimings": {
      "analysis": { "durationMs": 120000, "iterations": 1 },
      "specReview": { "durationMs": 90000, "iterations": 2 },
      "implementation": { "durationMs": 600000, "iterations": 1 },
      "prReview": { "durationMs": 60000, "iterations": 1 },
      "chaosTest": { "durationMs": 180000, "iterations": 1 }
    }
  }
}
```

---

## 11. Deployment Steps

### For an Existing OpenClaw Instance

```bash
# 1. Create knowledge and template directories
mkdir -p ~/.openclaw/workspace/{knowledge,templates,specs/changes}

# 2. Write the supervisor template
# Copy §3 supervisor prompt → templates/forge-supervisor.md

# 3. Initialize knowledge files
touch ~/.openclaw/workspace/knowledge/{project-context,past-decisions,known-issues,patterns,chaos-catalog}.md

# 4. Add to AGENTS.md
# Append the "Engineering Workflows" section from §3

# 5. Merge config additions from §2 into openclaw.json

# 6. Restart
openclaw gateway restart

# 7. Test: send a message in your channel:
#    "Start an engineering workflow for <project>: <requirement>"
```

### For a New Dedicated Instance

```bash
# 1. Install OpenClaw (if not installed)
npm install -g openclaw

# 2. Create workspace
mkdir -p ~/.openclaw/workspace/{knowledge,templates,specs/changes,projects,memory}

# 3. Write config (full standalone from §2)
# Write openclaw.json with your channel config and API keys

# 4. Set up workspace files
# SOUL.md, AGENTS.md (with engineering workflow section), TOOLS.md

# 5. Clone target project(s)
cd ~/.openclaw/workspace/projects
git clone <your-repo> <project-name>

# 6. Write project context
# Fill in knowledge/project-context.md with codebase overview

# 7. Start
openclaw gateway start

# 8. Configure channel (pair phone, add bot, etc.)
openclaw channels login --channel signal

# 9. Test workflow
```

### Validation Checklist

- [ ] Main agent responds in channel
- [ ] "Start engineering workflow" spawns a supervisor sub-agent
- [ ] Supervisor creates workflow-state.json
- [ ] Analyst spawns and produces spec artifacts
- [ ] Spec reviewer spawns and produces review
- [ ] Approval request reaches human (direct thread or relayed)
- [ ] Human approval routes back to supervisor
- [ ] Implementation runs after approval
- [ ] PR review produces verdict
- [ ] Merge approval completes workflow
- [ ] workflow-state.json returns to idle

---

## Appendix A: Multi-Project Setup

For teams working on multiple projects, structure knowledge per-project and use the supervisor's label to namespace:

```javascript
// Main agent spawns project-specific supervisor
sessions_spawn({
  runtime: "subagent",
  mode: "session",
  label: `forge-${projectName}-${featureName}`,
  model: "anthropic/claude-opus-4-6",
  task: supervisorPrompt
    .replace("{PROJECT_ROOT}", `projects/${projectName}`)
    .replace("{FEATURE_NAME}", featureName)
    .replace("{REQUIREMENT_TEXT}", requirement),
})
```

## Appendix B: Future Enhancements

1. **GitHub Integration** — Auto-create branches, open PRs, post review comments
2. **Cron Issue Triage** — Periodic scan of issues, auto-start workflows
3. **Cost Budgets** — Per-workflow token limits with automatic model downgrade
4. **Learning Loop** — Post-mortem analysis, patterns → knowledge files
5. **Persistent Implementer** — `mode: "session"` coder for repeat contributors to same project

---

*End of deployment plan v2.*
