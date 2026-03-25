# Fleet Manager

Fleet Manager is now implemented as a dedicated, containerized Forge control plane under [`fleet-manager/`](../fleet-manager/). It runs as its own OpenClaw instance, mounts the host rootless Podman socket, and provisions Forge instances as sibling Podman containers.

## Current Architecture

- Fleet Manager container image: `forge-fleet-manager:latest`
- Forge instance image: `openclaw-forge:latest`
- Rootless Podman socket mounted at `/run/podman/podman.sock`
- Persistent state in `~/.fleet-manager/fleet/instances.json`
- Gateway ports `18800-18899` reserved for managed Forge instances
- Fleet Manager gateway exposed on `18799`

## Repo Layout

```text
fleet-manager/
├── Dockerfile
├── docker-compose.yml
├── config/openclaw.json5
├── deploy.sh
├── forge-instance/
│   ├── Dockerfile
│   ├── entrypoint.sh
│   └── openclaw.json5
└── workspace/skills/fleet-manager/
    ├── SKILL.md
    ├── schemas/instances.schema.json
    └── scripts/
```

## Commands

The Fleet Manager skill exposes:

- `provision <name> [--channel ...] [--model ...]`
- `status [name]`
- `list`
- `pause <name>`
- `resume <name>`
- `logs <name> [--tail N]`
- `archive <name>`
- `destroy <name>`

## State

Managed instances are tracked in `~/.fleet-manager/fleet/instances.json` with container, volume, port, status, model, channel, and activity metadata.

## Detailed Docs

- [`docs/fleet-manager/architecture.md`](fleet-manager/architecture.md)
- [`docs/fleet-manager/operations.md`](fleet-manager/operations.md)
- [`fleet-manager/README.md`](../fleet-manager/README.md)
