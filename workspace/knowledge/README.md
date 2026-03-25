# Knowledge Directory

Project knowledge files that the supervisor selectively injects into specialist agents.

## Structure

Knowledge is stored in two formats:

- **Summary files** (`.md`) — synthesized, human-readable overviews. Compact context for agents.
- **Atomic facts** (`.json`) — timestamped, structured records. Detail on demand.

## Tiered Retrieval

Agents should consume knowledge in tiers to minimize context size:

1. **Summary first:** Inject the `.md` summary file (compact, synthesized)
2. **Detail on demand:** If an agent needs decision history or specific rationale, read from the `.json` file

This keeps agent prompts small while preserving full traceability.

## Files

### Summary Files (Tier 1 — always injected)

| File | Purpose | Injected Into |
|------|---------|---------------|
| `project-context.md` | Codebase overview, stack, conventions | All agents |
| `patterns.md` | Synthesized: what works/fails (auto-updated from decisions.json) | Implementer |
| `chaos-catalog.md` | Synthesized: adversarial findings (auto-updated from chaos-findings.json) | Chaos Agent (Ralph) |
| `known-issues.md` | Recurring problems, tech debt | Analyst |
| `compliance.md` | License, SBOM, and regulatory requirements | Implementer |

### Structured Data (Tier 2 — loaded when detail needed)

| File | Purpose | Schema |
|------|---------|--------|
| `decisions.json` | Atomic timestamped architectural decisions | [decisions.schema.json](../../docs/schemas/decisions.schema.json) |
| `chaos-findings.json` | Atomic timestamped adversarial findings | [chaos-findings.schema.json](../../docs/schemas/chaos-findings.schema.json) |

### Legacy File (backward compatibility)

| File | Purpose | Note |
|------|---------|------|
| `past-decisions.md` | Flat markdown decisions | Superseded by `decisions.json` + `patterns.md`. Kept for existing deployments during migration. |

## Decision Schema

```json
{
  "id": "proj-001",
  "decision": "Use SQLite for local state instead of Redis",
  "context": "Needed persistent state for job queue; evaluated Redis vs SQLite vs filesystem",
  "rationale": "Simpler deployment, no external dependency, sufficient throughput for single-node",
  "category": "architecture|api|testing|tooling|ci|dependencies|security|performance",
  "timestamp": "2026-03-24",
  "workflow": "feature-xyz",
  "issueRef": "#42",
  "status": "active|superseded",
  "supersededBy": null
}
```

## Chaos Finding Schema

```json
{
  "id": "chaos-001",
  "finding": "Mock server accepts connections after shutdown signal",
  "severity": "low|medium|high|critical",
  "category": "race-condition|resource-leak|error-handling|security|data-integrity|edge-case",
  "timestamp": "2026-03-24",
  "workflow": "feature-xyz",
  "resolution": "Added graceful shutdown with connection draining",
  "status": "active|resolved|wont-fix"
}
```

## Synthesis

Summary files are regenerated from structured data:

- **Post-workflow:** After each workflow completes, the supervisor appends new records to the JSON files, then regenerates the corresponding summary `.md` file from active records only.
- **Periodic:** On a configurable cadence (e.g., weekly or every N workflows), full rewrite of summary files from all active records.

When a new decision contradicts an earlier one, mark the old decision as `"status": "superseded"` and set `"supersededBy"` to the new decision's ID.

## Multi-Project Setup

For multiple projects, create subdirectories:

```
knowledge/
├── project-a/
│   ├── project-context.md
│   ├── decisions.json
│   ├── chaos-findings.json
│   ├── patterns.md
│   ├── chaos-catalog.md
│   └── ...
└── project-b/
    └── ...
```

For single-project deployments, the flat layout (no subdirectory) is the default.

## Source Material for Extraction

Decisions should be extracted from:
- **Journal entries** (`journal/YYYY-MM-DD.md`) — especially the "Design Decisions" section
- **Spec documents** (`spec/<feature>/openspec.md`) — the "Design Decisions" section
- **PR discussions** — review comments that led to changes
- **Human directives** — captured in journal, these often contain implicit decisions
