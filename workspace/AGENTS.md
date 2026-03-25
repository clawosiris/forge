# AGENTS.md

## Every Session

1. Read `SOUL.md`
2. Check for active engineering workflows: `subagents(action=list)`
3. Read `memory/` for recent context

## Engineering Workflows

When asked to start an engineering workflow (or build/implement/develop a feature), 
spawn a Forge supervisor sub-agent.

### Spawning a Workflow

1. Identify the project name and feature/requirement
2. Read the supervisor template: `templates/forge-supervisor.md`
3. Replace placeholders: `{PROJECT_ROOT}`, `{FEATURE_NAME}`, `{REQUIREMENT_TEXT}`
4. Spawn:

```
sessions_spawn({
  runtime: "subagent",
  mode: "session",
  label: "forge-<project>-<feature>",
  model: "anthropic/claude-opus-4-6",
  task: "<populated supervisor template>",
  // Discord/Slack only:
  // thread: true,
})
```

5. Confirm to the human that the workflow has started.

### Routing Messages (Signal/Telegram — no threads)

When you receive a message that references an active engineering workflow:
- Check active supervisors: `subagents(action=list)`
- Forward the message: `sessions_send(label="forge-<project>-<feature>", message="Human says: <message>")`

When a supervisor sends you a message (approval request, status update, completion):
- Relay to the human in chat
- Prefix with: `⚒️ [<project>/<feature>]:` for clarity

### Routing Messages (Discord/Slack — thread-bound)

No relay needed. The supervisor has its own thread and the human interacts directly.
Add `thread: true` to the `sessions_spawn` call.

### Checking Status

When asked about workflow status:
- `subagents(action=list)` shows active supervisor sessions
- `sessions_send(label="forge-<project>-<feature>", message="Report current status")` for details

### Multiple Workflows

Multiple supervisors can run in parallel (different projects or features). 
Each has a unique label. Use `subagents(action=list)` to see all active workflows.

## Memory

Write important context to `memory/YYYY-MM-DD.md` files.
Extract durable lessons to `MEMORY.md`.

## Knowledge (Project Intelligence)

Project knowledge uses a two-tier system:

- **Tier 1 — Summary files** (`.md`): Compact, synthesized overviews. Injected into agent prompts.
- **Tier 2 — Structured data** (`.json`): Atomic timestamped records. Loaded when detail is needed.

Summary files are auto-generated from structured data after each workflow. See `knowledge/README.md` for schemas and retrieval rules.

## Temp Files

Use `./tmp/` for temporary files (downloads, build artifacts, scratch work).

**Clean up after yourself:**
- Delete temp files when the task that created them is done
- Don't leave build artifacts, downloaded archives, or intermediate files
- If you extract something, delete the archive after
- If you download something to inspect, delete it after

The `tmp/` directory gets swept automatically (files older than 3 days are deleted), but don't rely on that — clean up as you go.

## Safety

- Don't exfiltrate private data
- Destructive operations require confirmation
- When in doubt, ask
