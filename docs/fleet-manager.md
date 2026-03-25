# Fleet Manager

Fleet Manager is the operational control plane for running multiple Forge instances on one host with rootless Podman.

## Architecture

- `fleet-manager` is a rootless Podman container bound to `127.0.0.1:18799`
- The host's Podman socket is mounted into the container at `/run/podman/podman.sock`
- Forge instances run as sibling containers on the `forge-fleet` network
- Credentials are delivered with Podman secrets mounted into `/run/secrets`
- Persistent state lives in named Podman volumes plus `~/.fleet-manager/instances.json`

## Layout

```text
fleet-manager/containers/
├── fleet-manager/
│   ├── Dockerfile
│   ├── config/openclaw.json5
│   └── workspace/
└── forge-instance/
    ├── Dockerfile
    ├── config/openclaw.json5
    └── workspace/

skills/fleet-manager/
├── SKILL.md
├── schemas/instances.json
├── scripts/
│   ├── provision.sh
│   ├── status.sh
│   └── teardown.sh
└── templates/forge-instance.json5
```

## Secrets

Create the required Podman secrets before provisioning instances:

```bash
echo "$ANTHROPIC_API_KEY" | podman secret create anthropic-api-key -
echo "$OPENAI_API_KEY" | podman secret create openai-api-key -
echo "$OPENCLAW_GATEWAY_TOKEN" | podman secret create gateway-token -
```

The managed OpenClaw config resolves those secrets from `/run/secrets` via:

```json5
secrets: {
  providers: {
    container: {
      source: "file",
      path: "/run/secrets",
      mode: "dir"
    }
  }
}
```

## Commands

From the repo root:

```bash
skills/fleet-manager/scripts/provision.sh <name>
skills/fleet-manager/scripts/status.sh [name]
skills/fleet-manager/scripts/teardown.sh --archive <name>
skills/fleet-manager/scripts/teardown.sh <name>
```

## Provisioning Behavior

`provision.sh` performs these steps:

1. Validate the instance name and reserve the next free host port.
2. Ensure the `forge-fleet` network exists.
3. Render a container-specific `openclaw.json5` under `~/.fleet-manager/instances/<name>/`.
4. Create named workspace and data volumes.
5. Seed the workspace volume from the repo's `workspace/` scaffold.
6. Start a Forge sibling container with the config bind-mounted and secrets attached.
7. Record the instance in `~/.fleet-manager/instances.json`.

## Teardown Behavior

`teardown.sh` uses `podman stop`, `podman rm`, and `podman volume rm` instead of deleting Unix users.

With `--archive`, it also:
- snapshots the workspace volume to `~/.fleet-manager/archives/<name>-workspace-<timestamp>.tar.gz`
- snapshots the data volume to `~/.fleet-manager/archives/<name>-data-<timestamp>.tar.gz`
- marks the state entry as `archived`

## State Shape

```json
{
  "instances": {
    "client-a": {
      "container": "forge-client-a",
      "image": "localhost/openclaw-forge:latest",
      "port": 18800,
      "configPath": "/home/openclaw/.fleet-manager/instances/client-a/openclaw.json5",
      "workspaceVolume": "forge-workspace-client-a",
      "dataVolume": "forge-data-client-a",
      "status": "running",
      "createdAt": "2026-03-25T15:06:00-04:00",
      "lastActivity": "2026-03-25T15:06:00-04:00"
    }
  },
  "nextPort": 18801
}
```

The repo seed file is [`skills/fleet-manager/schemas/instances.json`](../skills/fleet-manager/schemas/instances.json).
