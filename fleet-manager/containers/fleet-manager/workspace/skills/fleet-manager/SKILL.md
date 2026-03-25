# Fleet Manager

Use this skill when the operator wants to provision, inspect, pause, resume, archive, or destroy Forge instances on a single host.

Phase 1 scope:
- Single host only: `tycho`
- Isolation model: dedicated Unix user per instance
- Managed port range: `18800-18899`
- Runtime state: `~/.fleet-manager/instances.json`
- Repo schema/template source: `skills/fleet-manager/schemas/instances.json`, `skills/fleet-manager/templates/forge-instance.json5`

## Prerequisites

- Run from a checkout of this repo.
- `jq`, `sudo`, `systemctl`, `loginctl`, `ss`, and `tar` must be available on the host.
- The operator must approve `sudo` use for provisioning and teardown.
- Export any secrets you want copied into the managed instance before provisioning:
  - `ANTHROPIC_API_KEY`
  - `OPENAI_API_KEY`
  - `OPENCLAW_SIGNAL_ALLOW_FROM`
  - `OPENCLAW_GATEWAY_TOKEN` (optional; generated if absent)

## Command Map

### `provision <name>`

Run:

```bash
skills/fleet-manager/scripts/provision.sh <name>
```

What it does:
- allocates the next free port
- creates Unix user `forge-<name>`
- creates `/home/forge-<name>/.openclaw/workspace`
- copies the Forge workspace scaffold
- renders `skills/fleet-manager/templates/forge-instance.json5` into the new user's OpenClaw config
- writes a per-instance `secrets.json`
- installs and starts `~/.config/systemd/user/openclaw.service`
- records the instance in `~/.fleet-manager/instances.json`

After provisioning:
- report the assigned port and workspace
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
- systemd user unit state
- whether the gateway port is listening
- latest workspace activity timestamp

### `pause <name>`

Run:

```bash
name="<name>"
state="${FLEET_STATE_FILE:-$HOME/.fleet-manager/instances.json}"
user="$(jq -r --arg name "$name" '.instances[$name].user // empty' "$state")"
uid="$(id -u "$user")"
sudo -u "$user" XDG_RUNTIME_DIR="/run/user/$uid" systemctl --user stop openclaw.service
tmp="$(mktemp)"
jq --arg name "$name" '.instances[$name].status = "paused"' "$state" > "$tmp" && mv "$tmp" "$state"
```

Only stop the gateway. Do not remove files or the user.

### `resume <name>`

Run:

```bash
name="<name>"
state="${FLEET_STATE_FILE:-$HOME/.fleet-manager/instances.json}"
user="$(jq -r --arg name "$name" '.instances[$name].user // empty' "$state")"
uid="$(id -u "$user")"
sudo -u "$user" XDG_RUNTIME_DIR="/run/user/$uid" systemctl --user start openclaw.service
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
- stops the instance
- archives the workspace to `~/.fleet-manager/archives/<name>-<timestamp>.tar.gz`
- removes the systemd user unit
- removes the Unix user and home directory
- keeps a state entry marked `archived`

### `destroy <name>`

Run:

```bash
skills/fleet-manager/scripts/teardown.sh <name>
```

What it does:
- stops the instance
- removes the systemd user unit
- removes the Unix user and home directory
- deletes the state entry

### `list`

Run:

```bash
skills/fleet-manager/scripts/status.sh
```

Treat the all-instances status view as the list command for Phase 1.

## Guardrails

- Reject names that are not lowercase alphanumeric plus `-`.
- Do not reuse a name that already exists in state.
- Refuse provisioning if the next port would exceed `18899`.
- Ask before running archive/destroy.
- If `status.sh` reports the unit as inactive but the state says `running`, call that out explicitly instead of silently fixing it.
