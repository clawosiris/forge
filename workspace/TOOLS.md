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

## Secrets Management

Secrets are handled via **SecretRef** — resolved at runtime, never exposed to agents.

```bash
# Audit for plaintext secrets
openclaw secrets audit

# Interactive setup
openclaw secrets configure

# Reload without restart
openclaw secrets reload
```

**SecretRef syntax:**
```json5
token: { "$secret": "local:GATEWAY_AUTH_TOKEN" }
apiKey: { "$secret": "op:OpenClaw/Anthropic/api-key" }
```

See `docs/security/secrets-management.md` for full details.

## Temp File Cleanup

Agents should clean up temp files after use. As a safety net, a system cron
sweeps files older than 3 days:

```bash
# Add to system crontab (crontab -e) or deploy.sh
# Runs daily at 4 AM
0 4 * * * find ~/.openclaw/workspace*/tmp -type f -mtime +3 -delete 2>/dev/null; find ~/.openclaw/workspace*/tmp -type d -empty -delete 2>/dev/null
```

Or add via OpenClaw cron (see config example in `openclaw-standalone.json5`).

**Key principle:** Sandboxed agents cannot access secrets because:
1. `tools.fs.workspaceOnly: true` — no access to `~/.openclaw/`
2. `tools.exec.security: "allowlist"` — can't run arbitrary commands
3. Secrets resolved by gateway, not injected into agent context
