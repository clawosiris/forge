# TOOLS.md

## Fleet Paths

- State file: `~/.openclaw/fleet/instances.json`
- Archives: `~/.openclaw/fleet/archives/`
- Skill root: `~/workspace/skills/fleet-manager`

## Runtime

- Podman socket: `/run/podman/podman.sock`
- `CONTAINER_HOST=unix:///run/podman/podman.sock`
- Managed network: `forge-fleet`

## Images

- Fleet Manager: `forge-fleet-manager:latest`
- Forge instances: `openclaw-forge:latest`
