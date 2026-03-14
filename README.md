# Forge — Multi-Agent Engineering Process for OpenClaw

A structured, multi-agent software development workflow that separates cognitive concerns: creative agents write specs and code, critical agents review them, and adversarial agents break assumptions.

## Architecture

```
Your OpenClaw Instance
  │
  │ "start engineering workflow for project-x: add user auth"
  │
  ├── Supervisor (Forge)          persistent sub-agent, manages pipeline
  │     ├── Analyst / Spec Writer   drafts specs from requirements
  │     ├── Spec Reviewer           validates specs, produces test criteria
  │     ├── Implementer             writes code + tests
  │     ├── PR Reviewer             reviews code against spec
  │     └── Chaos Agent (Ralph)     adversarial testing, breaks assumptions
  │
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
| `docs/deployment-plan.md` | Full architecture documentation |

## Workflow Tiers

Not every change needs the full pipeline:

| Tier | When | Agents Used |
|------|------|-------------|
| **Small** | Bug fix, config, <50 LOC | Implementer + PR Reviewer |
| **Medium** | Feature, refactor, 50-500 LOC | + Analyst + Spec Reviewer |
| **Large** | New system, architecture, >500 LOC | + Chaos Agent (parallel) |

## Requirements

- [OpenClaw](https://github.com/openclaw/openclaw) installed
- Docker (for container sandboxing)
- API keys: Anthropic (primary), OpenAI (fallback)
- At least one messaging channel configured (Signal, Discord, Telegram, etc.)

## Documentation

See [`docs/deployment-plan.md`](docs/deployment-plan.md) for the full architecture, state machine, failure handling, and observability details.

## License

MIT
