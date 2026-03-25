# Secrets Management

OpenClaw separates secrets from agent context using **SecretRef** — a reference-based system that resolves secrets at runtime without exposing them in prompts, logs, or agent memory.

## Why This Matters

Agents can read files, inspect environment variables, and explore the filesystem. Without proper secrets handling:

- `cat ~/.bashrc` could leak API keys
- `env` could expose tokens
- Agent context might include plaintext credentials
- Logs could capture sensitive values

SecretRef solves this by:
1. Storing secrets in a separate provider (file, env, 1Password, etc.)
2. Resolving references at runtime only when needed
3. Never injecting plaintext into agent-visible context
4. Redacting values in config dumps and logs

## Configuration

### secrets.providers

Define where secrets are stored:

```json5
secrets: {
  providers: {
    // File-based (recommended for local dev)
    local: {
      source: "file",
      path: "~/.openclaw/secrets.json",
      mode: "json",
    },
    // Environment variables
    env: {
      source: "env",
    },
    // 1Password (production recommended)
    op: {
      source: "1password",
      account: "my.1password.com",
      vault: "OpenClaw",
    },
  },
}
```

### SecretRef Syntax

Reference secrets using `$secret`:

```json5
// Full syntax: provider:key
token: { "$secret": "local:GATEWAY_AUTH_TOKEN" }

// Short syntax: uses default provider
token: { "$secret": "GATEWAY_AUTH_TOKEN" }

// 1Password with item path
apiKey: { "$secret": "op:OpenClaw/Anthropic/api-key" }
```

## Secrets File Format

For file-based providers (`~/.openclaw/secrets.json`):

```json
{
  "GATEWAY_AUTH_TOKEN": "your-gateway-token",
  "ANTHROPIC_API_KEY": "sk-ant-...",
  "OPENAI_API_KEY": "sk-...",
  "BRAVE_SEARCH_API_KEY": "BSA...",
  "GITHUB_TOKEN": "ghp_..."
}
```

**Important:** This file should be:
- Owned by your user only: `chmod 600 ~/.openclaw/secrets.json`
- Excluded from backups that sync to cloud
- Never committed to git

## CLI Commands

```bash
# Interactive setup wizard
openclaw secrets configure

# Find plaintext secrets in config
openclaw secrets audit

# Reload secrets at runtime (no restart needed)
openclaw secrets reload

# Apply a generated migration plan
openclaw secrets apply --plan secrets-plan.json
```

## What Gets Protected

With proper SecretRef usage, these are protected:

| Field | SecretRef Path |
|-------|----------------|
| Gateway auth token | `gateway.auth.token` |
| API keys | `auth.profiles.*.token`, `auth.profiles.*.key` |
| Bot tokens | `channels.telegram.botToken`, `channels.discord.token` |
| Webhook secrets | `tools.*.apiKey` |

## Agent Isolation

Even with secrets properly configured, sandboxed agents should have:

1. **No filesystem access outside workspace** — `tools.fs.workspaceOnly: true`
2. **Allowlisted exec only** — `tools.exec.security: "allowlist"`
3. **No access to secrets file** — workspace doesn't include `~/.openclaw/`

This defense-in-depth ensures that even if an agent tries to access secrets, it can't.

## Migration from Plaintext

If you have existing plaintext secrets:

```bash
# 1. Audit current state
openclaw secrets audit

# 2. Run interactive migration
openclaw secrets configure

# 3. Review generated plan
cat secrets-plan.json

# 4. Apply changes
openclaw secrets apply --plan secrets-plan.json

# 5. Verify
openclaw secrets audit  # Should show 0 plaintext
```

## Best Practices

1. **Never commit secrets** — Add `secrets.json` to `.gitignore`
2. **Use 1Password in production** — Better audit trail and rotation
3. **Rotate regularly** — Especially after any security incident
4. **Audit on deploy** — Run `openclaw secrets audit` in CI
5. **Separate per-environment** — Dev/staging/prod should have different secrets
