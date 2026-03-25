# Fleet Manager

Use this skill when the operator wants to provision, inspect, pause, resume, archive, or destroy Forge instances on a single host.

Phase 2 scope:
- Single host only
- Isolation model: rootless Podman containers
- Fleet Manager itself runs in a container with the host Podman socket mounted
- Managed port range: `18800-18899`
- Runtime state: `~/.fleet-manager/instances.json`
- Repo schema/template source: `skills/fleet-manager/schemas/instances.json`, `skills/fleet-manager/templates/forge-instance.json5`

## Prerequisites

- Run from a checkout of this repo, or from the Fleet Manager container with `FLEET_REPO_ROOT` set.
- `jq`, `podman`, and `ss` must be available.
- The forge instance image must already exist: `localhost/openclaw-forge:latest` unless overridden.
- Podman secrets must already exist before provisioning:
  - `anthropic-api-key`
  - `openai-api-key`
  - `gateway-token`

## Command Map

### `provision <name>`

Run:

```bash
skills/fleet-manager/scripts/provision.sh <name>
```

What it does:
- allocates the next free host port
- creates persistent workspace and state volumes
- renders the managed instance OpenClaw config
- seeds the workspace volume from this repo's `workspace/` scaffold
- starts a Forge sibling container with Podman secrets mounted into `/run/secrets`
- records the instance in `~/.fleet-manager/instances.json`

After provisioning:
- report the assigned port and container name
- tell the operator that channel bindings are still manual if they want per-instance messaging

### `status [name]`

Run:

```bash
skills/fleet-manager/scripts/status.sh
skills/fleet-manager/scripts/status.sh <name>
```

Report:
- instance name
- configured status from state
- runtime container state from `podman inspect`
- whether host ports are published
- container start timestamp

### `pause <name>`

Run:

```bash
name="<name>"
state="${FLEET_STATE_FILE:-$HOME/.fleet-manager/instances.json}"
container="$(jq -r --arg name "$name" '.instances[$name].container // empty' "$state")"
podman stop "$container"
tmp="$(mktemp)"
jq --arg name "$name" '.instances[$name].status = "paused"' "$state" > "$tmp" && mv "$tmp" "$state"
```

Only stop the container. Do not remove volumes or config.

### `resume <name>`

Run:

```bash
name="<name>"
state="${FLEET_STATE_FILE:-$HOME/.fleet-manager/instances.json}"
container="$(jq -r --arg name "$name" '.instances[$name].container // empty' "$state")"
podman start "$container"
tmp="$(mktemp)"
jq --arg name "$name" --arg now "$(date -Iseconds)" '.instances[$name].status = "running" | .instances[$name].lastActivity = $now' "$state" > "$tmp" && mv "$tmp" "$state"
```

Verify with:

```bash
skills/fleet-manager/scripts/status.sh <name>
```

### `archive <name>`

Run:

```bash
skills/fleet-manager/scripts/teardown.sh --archive <name>
```

What it does:
- archives the workspace and state volumes into `~/.fleet-manager/archives/`
- stops and removes the instance container
- removes the named volumes
- keeps a state entry marked `archived`

### `destroy <name>`

Run:

```bash
skills/fleet-manager/scripts/teardown.sh <name>
```

What it does:
- stops and removes the instance container
- removes the named volumes
- removes the rendered config
- deletes the state entry

### `list`

Run:

```bash
skills/fleet-manager/scripts/status.sh
```

Treat the all-instances status view as the list command for Phase 2.

## Guardrails

- Reject names that are not lowercase alphanumeric plus `-`.
- Do not reuse a name that already exists in state.
- Refuse provisioning if the next port would exceed `18899`.
- Ask before running archive/destroy.
- If state says `running` but `podman inspect` says otherwise, call that out explicitly instead of silently fixing it.
