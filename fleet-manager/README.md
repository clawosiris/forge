# Fleet Manager

Fleet Manager is a standalone OpenClaw deployment that manages multiple Forge instances as sibling rootless Podman containers.

## What It Does

- Provisions new Forge instances from a reusable container image
- Tracks assigned ports and metadata in `~/.fleet-manager/fleet/instances.json`
- Exposes a dedicated gateway on port `18799`
- Uses the host Podman socket to stop, start, inspect, archive, and destroy sibling containers

## Quick Start

```bash
cd fleet-manager
./deploy.sh
```

Required host characteristics:

- Rootless Podman with `systemctl --user enable --now podman.socket`
- A writable state directory at `~/.fleet-manager`
- `ANTHROPIC_API_KEY` exported for instance provisioning

## Layout

```text
fleet-manager/
├── Dockerfile
├── docker-compose.yml
├── config/openclaw.json5
├── deploy.sh
├── forge-instance/
│   ├── Dockerfile
│   └── entrypoint.sh
└── workspace/skills/fleet-manager/
    ├── SKILL.md
    ├── schemas/instances.schema.json
    └── scripts/
```

## Provisioning Flow

1. Fleet Manager allocates the next free port in `18800-18899`.
2. It creates `forge-<name>` and `forge-<name>-data`.
3. It launches `openclaw-forge:latest` on the shared `forge-fleet` network.
4. It writes instance metadata back to `~/.fleet-manager/fleet/instances.json`.

## Lifecycle Commands

- `provision <name> [--channel ...] [--model ...]`
- `status [name]`
- `list`
- `pause <name>`
- `resume <name>`
- `logs <name> [--tail N]`
- `archive <name>`
- `destroy <name>`

See [`../docs/fleet-manager/architecture.md`](../docs/fleet-manager/architecture.md) and [`../docs/fleet-manager/operations.md`](../docs/fleet-manager/operations.md) for the full design and operator runbook.
