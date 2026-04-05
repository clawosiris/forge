# Tasks: ClawFlow Dev Workflow

## Completed ✅

- [x] Design flow state schema
- [x] Choose backing store (workspace JSON files)
- [x] Implement `flows/bin/flow` CLI
  - [x] `create` — new flow with goal + meta
  - [x] `list` — all active flows, filterable by state
  - [x] `show` — full JSON for a flow
  - [x] `set-output` — persist key/value to flow outputs
  - [x] `wait` — transition to waiting state with reason + target
  - [x] `resume` — transition to running, set next step
  - [x] `finish` — archive to flows/done/
  - [x] `fail` — archive to flows/done/ with reason
- [x] Symlink `flow` to `~/.local/bin/flow`
- [x] Update `workflows/openspec-development.md`
- [x] Write OpenSpec docs (this set of files)
- [x] Feature 1: Parallel flow IDs
- [x] Feature 2: Webhook auto-resume
- [x] Feature 3: Lobster pipeline

## Remaining / Future

- [ ] Add "check waiting flows" to HEARTBEAT.md
- [ ] Update MEMORY.md with flow CLI notes
- [ ] `flow emit` command for mid-flow notifications (future)
- [ ] Index command: `flow find --repo owner/repo` (future)
