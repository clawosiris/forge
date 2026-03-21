# Group-Bound Agent Security Hardening

**Date:** 2026-03-21  
**Status:** Implemented  
**Agents Affected:** thoth, dev-grnbn, clawdev

## Problem Statement

Agents bound to Signal group chats have `exec` access, allowing them to run shell commands. This creates a credential exposure risk:

1. **Environment variables** — `env` command exposes API tokens
2. **Credential files** — `cat ~/.bashrc` or `cat ~/.config/gh/hosts.yml` leaks secrets
3. **Social engineering** — Group members could trick agents into revealing credentials

### Credentials at Risk

| Credential | Location | Risk Level |
|------------|----------|------------|
| `CLAUDE_CODE_OAUTH_TOKEN` | ~/.bashrc + env | HIGH |
| `FORGEJO_ACCESS_TOKEN` | ~/.bashrc + env | HIGH |
| GitHub OAuth | ~/.config/gh/hosts.yml | HIGH |
| NPM auth token | ~/.npmrc | MEDIUM |
| Claude credentials | ~/.claude/.credentials.json | HIGH |
| SSH private key | ~/.ssh/id_ed25519 | CRITICAL |

## Solution

Applied two-layer defense:

### 1. Exec Allowlist (`tools.exec.security: "allowlist"`)

Restrict shell commands to a curated safeBins list. Only commands the agent actually needs are permitted.

**Blocked commands:**
- `env`, `printenv` — environment variable exposure
- `bash`, `sh` — arbitrary shell execution
- `source`, `.` — script sourcing
- `eval` — arbitrary code execution
- `cat` — replaced with `read` tool (respects workspace restrictions)

**Allowed commands (per-agent):**

| Category | Commands |
|----------|----------|
| Text processing | head, tail, grep, sed, awk, sort, uniq, wc, tr, cut |
| File operations | ls, find, mkdir, cp, mv, rm, basename, dirname, xargs, touch, chmod |
| Development | git, gh, jq, curl |
| Utilities | date, sleep, echo, printf, tee, mktemp, realpath, test |
| thoth only | codex, pgrep |
| dev-grnbn only | poetry, python3, pip |

### 2. Filesystem Confinement (`tools.fs.workspaceOnly: true`)

Restrict `read`/`write`/`edit` tools to the agent's workspace directory only.

| Agent | Workspace |
|-------|-----------|
| thoth | /home/clawd/.openclaw/workspace-thoth |
| dev-grnbn | /home/clawd/.openclaw/workspace-dev-grnbn |
| clawdev | /home/clawd/.openclaw/workspace-clawdev |

## Configuration

```json
{
  "id": "thoth",
  "workspace": "/home/clawd/.openclaw/workspace-thoth",
  "model": "anthropic/claude-opus-4-6",
  "tools": {
    "elevated": { "enabled": false },
    "fs": { "workspaceOnly": true },
    "exec": {
      "security": "allowlist",
      "safeBins": [
        "head", "tail", "grep", "sed", "awk", "sort", "uniq", "wc", "tr", "cut",
        "ls", "find", "mkdir", "cp", "mv", "rm", "basename", "dirname", "xargs",
        "touch", "chmod", "git", "gh", "jq", "curl", "codex", "date", "sleep",
        "pgrep", "echo", "printf", "tee", "mktemp", "realpath", "test"
      ]
    }
  }
}
```

## Preserved Capabilities

The following capabilities remain unaffected:

- **OpenClaw tools:** `sessions_spawn`, `subagents`, `sessions_send`, `message`
- **File tools:** `read`, `write`, `edit` (within workspace)
- **GitHub operations:** `gh` CLI for PRs, issues, API calls
- **Git operations:** Full git functionality
- **Coding agents:** thoth can still invoke `codex` CLI

## Remaining Gaps

1. **Exec commands can still access files** — `grep pattern ~/.bashrc` would still work if grep is allowed. Consider removing grep or using more restrictive path validation.

2. **Git clone to arbitrary paths** — Agents can clone repos to /tmp. Consider workdir restrictions.

3. **curl to localhost** — Could potentially hit local services. Consider URL restrictions if needed.

4. **No container isolation** — These are process-level restrictions, not full sandboxing. Container sandbox (rolled back due to upstream issues) would provide stronger isolation.

## Audit History

- 2026-03-21 15:37 — Initial security audit identified credential exposure
- 2026-03-21 15:38 — Applied exec allowlist to thoth, dev-grnbn, clawdev
- 2026-03-21 15:42 — Added fs.workspaceOnly, removed cat from safeBins
