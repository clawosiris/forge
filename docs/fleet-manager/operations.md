# Fleet Manager Operations Guide

## Host Preparation

1. Install Podman and `jq`.
2. Enable the rootless socket:

```bash
systemctl --user enable --now podman.socket
```

3. Export the required secrets:

```bash
export ANTHROPIC_API_KEY=...
export OPENAI_API_KEY=...
export OPENCLAW_GATEWAY_TOKEN=...
```

## Deployment

```bash
cd fleet-manager
./deploy.sh
```

## Common Operations

### Provision

```bash
~/.fleet-manager/workspace/skills/fleet-manager/scripts/provision.sh client-a --channel signal --model opus
```

### Status and list

```bash
~/.fleet-manager/workspace/skills/fleet-manager/scripts/status.sh
~/.fleet-manager/workspace/skills/fleet-manager/scripts/status.sh client-a
```

### Pause and resume

```bash
podman stop forge-client-a
podman start forge-client-a
```

### Logs

```bash
podman logs --tail 200 forge-client-a
```

### Archive

```bash
~/.fleet-manager/workspace/skills/fleet-manager/scripts/teardown.sh --archive client-a
```

### Destroy

```bash
~/.fleet-manager/workspace/skills/fleet-manager/scripts/teardown.sh --destroy client-a
```

## Recovery

- If Fleet Manager restarts, state persists in `~/.fleet-manager`
- If `instances.json` disagrees with Podman, reconcile by inspecting containers with the `fleet.managed=true` label and then updating the state file through the scripts
- Archived instances can be restored by creating a fresh volume and untarring the archived snapshot into it

## Known Constraints

- Archive operations require `FLEET_MANAGER_HOST_STATE_DIR` so the helper container can write tarballs onto the host filesystem
- Health checks are TCP-based; if OpenClaw later exposes a stable health endpoint, switch `status.sh` to probe that instead
- The current implementation assumes a single host; multi-host orchestration would need remote Podman or SSH transport
