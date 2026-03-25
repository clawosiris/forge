# Fleet Manager Architecture

Fleet Manager packages Forge fleet operations into a dedicated OpenClaw instance that runs inside a rootless Podman container and manages Forge instances as sibling containers through the mounted Podman socket.

## Topology

```text
Host
├── /run/user/1000/podman/podman.sock
├── ~/.fleet-manager
└── Podman network: forge-fleet
    ├── fleet-manager:18799
    ├── forge-a:18789 -> host 18800
    ├── forge-b:18789 -> host 18801
    └── forge-c:18789 -> host 18802
```

## Components

### Fleet Manager container

- Image: `forge-fleet-manager:latest`
- Runs OpenClaw with a single `fleet-manager` agent
- Mounts the host Podman socket at `/run/podman/podman.sock`
- Mounts persistent state at `/home/openclaw/.openclaw`
- Uses `CONTAINER_HOST=unix:///run/podman/podman.sock`

### Forge instance containers

- Image: `openclaw-forge:latest`
- One named volume per instance for `~/.openclaw`
- One published port from `18800-18899`
- Labels:
  - `fleet.managed=true`
  - `fleet.name=<name>`
  - `fleet.channel=<channel>`
  - `fleet.model=<model>`

## State Model

The authoritative state file is `~/.fleet-manager/fleet/instances.json`.

- `instances.<name>.container`: sibling container name
- `instances.<name>.port`: host port mapped to the instance gateway
- `instances.<name>.volume`: named Podman volume
- `instances.<name>.status`: `running`, `stopped`, or `archived`
- `instances.<name>.lastActivity`: last known log timestamp or lifecycle event
- `nextPort`: next candidate port allocator

## Networking

- Fleet Manager and all Forge instances join the same Podman network: `forge-fleet`
- Fleet Manager checks instance liveness by opening TCP to `forge-<name>:18789`
- The operator talks to Fleet Manager via the exposed host port `18799`
- External clients talk to each Forge instance through the published host port recorded in the state file

## Secrets

- Fleet Manager reads provider credentials from its own environment
- Provisioned instances inherit `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, and `OPENCLAW_GATEWAY_TOKEN`
- For stronger isolation, replace env passthrough with Podman secrets later; the current layout is designed to make that swap straightforward

## Archive Semantics

`archive` stops and removes the container, snapshots the volume into `~/.fleet-manager/archives/`, removes the volume, and marks the instance as archived in the state file.

`destroy` removes the container, removes the volume, and deletes the entry from the state file.
