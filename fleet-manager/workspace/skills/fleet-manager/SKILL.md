# Fleet Manager Skill

Use this skill whenever the operator asks to provision, inspect, pause, resume, archive, destroy, or list Forge instances.

## Command Surface

- `provision <name> [--channel signal|telegram|discord|none] [--model opus|sonnet]`
- `status [name]`
- `pause <name>`
- `resume <name>`
- `logs <name> [--tail N]`
- `archive <name>`
- `destroy <name>`
- `list`

## Rules

- Validate names against `^[a-z0-9-]+$`.
- Treat the state file and Podman labels as the source of truth.
- Use `archive` before `destroy` unless the operator explicitly wants full teardown.
- Never hand-edit `instances.json`; use the scripts so port allocation and timestamps stay coherent.

## Scripts

- Provision: `scripts/provision.sh <name> [--channel ...] [--model ...]`
- Status: `scripts/status.sh [name]`
- Pause: `podman stop forge-<name>`
- Resume: `podman start forge-<name>`
- Logs: `podman logs forge-<name> [--tail N]`
- Archive: `scripts/teardown.sh --archive <name>`
- Destroy: `scripts/teardown.sh --destroy <name>`
- List: `scripts/status.sh`

## Expected Outputs

- `provision.sh` prints a JSON object with the assigned port and container name.
- `status.sh` prints JSON for one instance or the entire fleet.
- `teardown.sh` prints JSON describing the archive path or destroyed resources.

## Operational Notes

- The Fleet Manager container must run with `CONTAINER_HOST=unix:///run/podman/podman.sock`.
- The Fleet Manager container should also be attached to the `forge-fleet` network so it can probe sibling containers directly.
- API keys are forwarded to provisioned instances from Fleet Manager environment variables.
