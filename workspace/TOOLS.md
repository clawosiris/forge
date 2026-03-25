# TOOLS.md

## Engineering Workflow

- Supervisor template: `templates/forge-supervisor.md`
- Agent templates: `templates/agents/`
- Knowledge base: `knowledge/`
- Specs output: `specs/changes/<feature>/`

## Thinking Levels

Configured via `thinkingDefault` in agent params or defaults.

| Level | Use Case | Latency | Cost |
|-------|----------|---------|------|
| `off` | Simple tasks, quick responses | Fastest | Lowest |
| `low` | Routine assistant work | Fast | Low |
| `medium` | Reviews, design discussions | Moderate | Medium |
| `high` | Novel problems, deep analysis | Slow | High |
| `adaptive` | **Recommended** — scales with complexity | Variable | Optimized |

Adaptive is recommended for supervisor/architect roles: quick on routine
coordination ("merged", "looks good"), deeper reasoning on architecture
decisions and code reviews.

## Reasoning vs Thinking

- **Thinking** (`thinkingDefault`): How much reasoning the model does internally
- **Reasoning** (`/reasoning` command): Whether you *see* that reasoning

Reasoning is observational — it doesn't change behavior, just visibility.
Useful for debugging logic or understanding conclusions.

## Model Selection

For supervisor/architect roles with Codex doing implementation:

- **Opus 4.5** with adaptive thinking is sufficient
- Opus 4.6 offers marginal gains at higher cost
- The thinking level matters more than the .1 version bump

For sub-agents/specialists:

- **Sonnet 4** for most tasks (cost-effective)
- **Haiku 4.5** for heartbeats and lightweight checks

## Safe Bins (Sandboxed Agents)

When running in sandbox mode, exec is restricted to allowlisted binaries:

```
# Text processing
head, tail, grep, sed, awk, sort, uniq, wc, tr, cut

# File operations  
ls, find, mkdir, cp, mv, rm, basename, dirname, xargs, touch, chmod, cat, tee

# Development tools
git, gh, jq, curl

# Build tools
make, cargo, rustc, python3, pip, node, npm, npx

# Utilities
date, sleep, echo, printf, mktemp, realpath, test, which

# Coding agents
codex
```

Add project-specific tools to `tools.sandbox.exec.safeBins` in config.
