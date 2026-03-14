# HEARTBEAT.md

## Check Active Workflows
- If any forge-* sub-agent sessions have been running longer than 30 minutes
  without progress, alert.
- If workflow-state.json shows a non-idle state older than 2 hours without
  a pending human approval, alert.
