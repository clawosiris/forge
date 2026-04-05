# Pipelines

`openspec-dev.lobster` is a typed Lobster workflow file for the OpenSpec
development flow. The companion helper `openspec-dev-step.js` wraps the flow CLI
so each pipeline step stays declarative while still driving the phase
transitions. The workflow expects these environment variables:

- `FORGE_REPO`
- `FORGE_BRANCH`
- `FORGE_ISSUE`
- `FORGE_FEATURE`

The pipeline:

- creates the ClawFlow record
- pauses for approval before agent/spec work begins
- moves the flow through `create_spec_pr`, `implement`, and `review`
- pauses for approval again before the merge/finish stage

## Invocation

Run it with the required environment variables set:

```bash
FORGE_REPO=clawosiris/forge \
FORGE_BRANCH=feat/clawflow-integration \
FORGE_ISSUE=123 \
FORGE_FEATURE="ClawFlow integration" \
lobster run fleet-manager/pipelines/openspec-dev.lobster
```

Inside OpenClaw, the same file can be used as a Lobster workflow-file pipeline.
