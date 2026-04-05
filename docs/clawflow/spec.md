# Spec: ClawFlow Dev Workflow

## Flow File Schema

Location: `flows/active/<flowId>.json`
On finish/fail: moved to `flows/done/<flowId>.json`

Flow IDs use repo/branch-scoped parallel format:

```
{repo-slug}--{branch-slug}-{date}
```

- `repo-slug` comes from `owner/repo` with slashes replaced by dashes
- `branch-slug` comes from the branch name with slashes replaced by dashes
- Example: `clawosiris-forge--feat-clawflow-integration-2026-04-05`

```json
{
  "flowId": "clawosiris-forge--feat-clawflow-integration-2026-04-05",
  "goal": "implement X in owner/repo",
  "ownerSessionKey": "main",
  "currentStep": "wait_for_spec_pr_review",
  "state": "waiting",
  "outputs": {
    "repo": "owner/repo",
    "branch": "feat/x",
    "issue_number": 42,
    "spec_pr_url": "https://github.com/.../pull/10",
    "impl_pr_url": null,
    "codex_session_id": null
  },
  "waitReason": "spec_pr_review",
  "waitTarget": "https://github.com/.../pull/10",
  "createdAt": "2026-04-05T11:00:00Z",
  "updatedAt": "2026-04-05T11:05:00Z"
}
```

### State Values
- `running` — actively being processed
- `waiting` — blocked on external input (human, CI, external API)
- `done` — completed successfully
- `failed` — aborted

### Standard Step Names
- `created`
- `create_spec_pr`
- `wait_for_spec_pr_review`
- `implement`
- `wait_for_codex`
- `wait_for_ci_and_review`
- `review`
- `finished`
- `failed`

### Standard Output Keys
| Key | Type | When set |
|---|---|---|
| `repo` | string | creation |
| `branch` | string | creation |
| `issue_number` | number | creation |
| `spec_pr_url` | string | after spec PR created |
| `spec_path` | string | after spec PR merged (path in repo) |
| `impl_pr_url` | string | after codex pushes |
| `codex_session_id` | string | when codex spawned |
| `merged_at` | string (ISO) | on merge |

### Standard Wait Reasons
- `spec_pr_review` — waiting for human to review/merge OpenSpec PR
- `ci_and_review` — waiting for CI to pass and impl PR to be reviewed
- `external` — generic external wait (use `waitTarget` for context)

## CLI Contract

```
flow create --goal "<text>" --repo <owner/repo> --branch <branch> [--meta '<json>'] [--owner-session <key>]
  → stdout: {"flowId":"...","path":"..."}

flow list [--state running|waiting|done|failed]
  → human-readable table

flow show <flowId>
  → pretty JSON

flow set-output <flowId> <key> <value>
  → "set <key> on <flowId>"

flow wait <flowId> --reason <reason> [--target <url>]
  → "<flowId> → waiting (<reason>)"

flow resume <flowId> --step <step>
  → "<flowId> → running (step: <step>)"

flow finish <flowId>
  → "<flowId> → done (archived)"

flow fail <flowId> [--reason <text>]
  → "<flowId> → failed: <reason> (archived)"
```

All commands exit 0 on success, 1 on error. Errors to stderr.

## Directory Layout

```
workspace/
  flows/
    bin/
      flow              ← CLI (Node.js, executable)
    active/
      <flowId>.json     ← in-flight flows
    done/
      <flowId>.json     ← archived flows (read-only reference)
```

## Heartbeat Integration

During periodic heartbeat checks, scan `flows/active/` for waiting flows:

```bash
flow list --state waiting
```

If any flows are waiting and significant time has passed (or Daniel asks "status on X"),
surface them with current `waitReason` and `waitTarget`.
