# Forge — Multi-Agent Engineering Process for OpenClaw

A structured, multi-agent software development workflow that separates cognitive concerns: creative agents write specs and code, critical agents review them, and adversarial agents break assumptions.

Fleet Manager Phase 1 is also included: a host-level operational skill for provisioning and managing multiple Forge instances on a single machine.

## Architecture

```
Your OpenClaw Instance
  │
  │ "start engineering workflow for project-x: add user auth"
  │
  ├── Supervisor (Forge)          persistent sub-agent, manages pipeline
  │     ├── Analyst / Spec Writer   drafts specs from requirements
  │     ├── Spec Reviewer           validates specs, produces test criteria
  │     ├── Implementer (Codex)     writes code + tests (task-spec driven)
  │     ├── PR Reviewer             reviews code against spec (diff-based)
  │     ├── Code Reviewer           holistic codebase quality review
  │     └── Chaos Agent (Ralph)     adversarial testing, breaks assumptions
  │
  ├── CI/CD Pipeline Monitor       polls CI, auto-diagnoses failures
  ├── GitHub Issue & PR Lifecycle   triage, track, close, review iterations
  └── Human approval gates at spec approval + merge
```

The supervisor runs as a **persistent sub-agent session** — your main OpenClaw agent stays general-purpose and spawns workflow supervisors on demand. Multiple workflows can run in parallel.

## Quick Start

```bash
# Clone
git clone https://github.com/clawosiris/forge.git
cd forge

# Deploy (new standalone instance with container sandboxing)
./deploy.sh

# Or add to an existing instance
./deploy.sh --addon
```

## What's Included

| File | Purpose |
|------|---------|
| `deploy.sh` | Deployment script with container sandboxing setup |
| `config/openclaw-standalone.json5` | Complete config for a fresh instance |
| `config/openclaw-addon.json5` | Merge guide for existing instances |
| `workspace/AGENTS.md` | Main agent instructions (includes workflow routing) |
| `workspace/SOUL.md` | Main agent persona |
| `workspace/templates/forge-supervisor.md` | Supervisor spawn template |
| `workspace/templates/agents/` | Specialist agent prompt templates |
| `workspace/knowledge/` | Project knowledge directory (populate per-project) |
| `skills/fleet-manager/` | Fleet provisioning skill, scripts, schema, and instance template |
| `docs/deployment-plan.md` | Full architecture documentation |
| `docs/fleet-manager.md` | Fleet Manager overview and pointers to the containerized deployment docs |

## Workflow Tiers

Not every change needs the full pipeline:

| Tier | When | Agents Used |
|------|------|-------------|
| **Small** | Bug fix, config, <50 LOC | Implementer + PR Reviewer |
| **Medium** | Feature, refactor, 50-500 LOC | + Analyst + Spec Reviewer |
| **Large** | New system, architecture, >500 LOC | + Chaos Agent + Code Reviewer (parallel) |

## Key Features

### CI/CD Pipeline Awareness (#1)
The supervisor monitors CI after implementation, auto-diagnoses failures, and spawns targeted fixes (max 3 attempts before escalating). PR review is gated on CI green.

### Code Review Agent (#2)
Dedicated holistic code reviewer (separate from PR reviewer) that analyzes the full codebase for quality, architecture, and security — not just the diff.

### Codex-First Implementation (#3)
Implementer uses a task-spec-driven pattern: write TASK.md → Codex `--full-auto` → validate → iterate. This produces the most reliable output.

### Spec-Implementation Drift Detection (#4)
After implementation, the supervisor compares what was built against the spec and produces a `spec-delta.md` flagging scope creep and gaps.

### License & Compliance (#5)
Optional compliance stage with SPDX header enforcement, dependency auditing, and SBOM generation. Driven by `knowledge/compliance.md`.

### Test Infrastructure as First-Class Artifact (#6)
Analyst produces `test-infrastructure.md` alongside the OpenSpec. Mock servers, fixtures, and test doubles get equal review rigor.

### Release Management (#7)
Optional release stage: version bump, tag, CHANGELOG, release workflow monitoring — all tracked in `workflow-state.json`.

### Cross-Repository Coordination (#8)
Track downstream impacts across repos. Supervisor creates follow-up issues in dependent repos and coordinates sequential cross-repo work.

### Formatting Pre-Commit Gate (#9)
Implementer runs formatter → linter → tests → docs before declaring complete. Eliminates trivial CI failures.

### Sandbox-Aware Test Design (#10)
Patterns for feature-gated tests, graceful PermissionDenied skips, and cwd-relative paths for container compatibility.

### GitHub Issue & PR Lifecycle (#11)
Full lifecycle management: issue triage, label-based state tracking, PR review iteration handling, and optional cron-based monitoring.

## Requirements

- [OpenClaw](https://github.com/openclaw/openclaw) installed
- Docker (for container sandboxing)
- API keys: Anthropic (primary), OpenAI (fallback)
- At least one messaging channel configured (Signal, Discord, Telegram, etc.)

## Documentation

See [`docs/deployment-plan.md`](docs/deployment-plan.md) for the full architecture, state machine, failure handling, and observability details.

## Fleet Manager

Forge now includes a container-oriented Fleet Manager package in [`fleet-manager/`](fleet-manager). It runs as its own OpenClaw instance, mounts the host rootless Podman socket, and provisions Forge instances as sibling containers on a shared `forge-fleet` network.

Core pieces:

- `fleet-manager/Dockerfile` builds the manager image
- `fleet-manager/forge-instance/Dockerfile` builds the image used for each managed Forge instance
- `fleet-manager/docker-compose.yml` wires the Podman socket, persistent state, and port `18799`
- `fleet-manager/workspace/skills/fleet-manager/` contains the lifecycle skill, state schema, and provisioning scripts
- `docs/fleet-manager/` documents architecture and operations

Quick start:

```bash
cd fleet-manager
./deploy.sh
```

Fleet operations are documented in [`docs/fleet-manager.md`](docs/fleet-manager.md).

## License

MIT
