# Fleet Manager

Fleet Manager is a Phase 1 operational skill for provisioning and managing multiple Forge instances from an existing OpenClaw deployment.

Current assumptions:
- single host: `tycho`
- isolation by Unix user, not containers
- lifecycle driven by a skill plus host shell scripts
- managed gateway ports in `18800-18899`

## Layout

```text
skills/fleet-manager/
├── SKILL.md
├── schemas/instances.json
├── scripts/
│   ├── provision.sh
│   ├── status.sh
│   └── teardown.sh
└── templates/forge-instance.json5
```

Runtime state lives outside the repo at `~/.fleet-manager/instances.json`.

## Commands

From the repo root:

```bash
skills/fleet-manager/scripts/provision.sh <name>
skills/fleet-manager/scripts/status.sh [name]
skills/fleet-manager/scripts/teardown.sh --archive <name>
skills/fleet-manager/scripts/teardown.sh <name>
```

The `pause`, `resume`, and `list` operations are described in [`skills/fleet-manager/SKILL.md`](../skills/fleet-manager/SKILL.md).

## Provisioning Behavior

`provision.sh` performs these steps:

1. Validate the instance name and reserve the next free port.
2. Create a dedicated Unix user `forge-<name>`.
3. Copy the Forge workspace scaffold into `/home/forge-<name>/.openclaw/workspace`.
4. Render a managed-instance OpenClaw config from `templates/forge-instance.json5`.
5. Write `/home/forge-<name>/.openclaw/secrets.json`.
6. Install `~/.config/systemd/user/openclaw.service`.
7. Enable lingering and start the user's `openclaw.service`.
8. Record the instance in `~/.fleet-manager/instances.json`.

## Sudo Requirement

These scripts require `sudo` because they create and delete Unix users, write files into other home directories, and control user-scoped systemd units.

Minimum host commands used:
- `useradd`
- `userdel`
- `loginctl enable-linger`
- `systemctl --user`
- `install`
- `cp`
- `tar`

## Secrets

The rendered instance config uses SecretRef for credentials and gateway auth. Phase 1 writes a per-instance local secrets file and expects operators to export values before provisioning when they want them copied:

- `OPENCLAW_GATEWAY_TOKEN`
- `ANTHROPIC_API_KEY`
- `OPENAI_API_KEY`
- `OPENCLAW_SIGNAL_ALLOW_FROM`

If `OPENCLAW_GATEWAY_TOKEN` is absent, the provisioning script generates one.

## State Schema

Runtime state shape:

```json
{
  "instances": {
    "client-a": {
      "user": "forge-client-a",
      "port": 18800,
      "workspace": "/home/forge-client-a/.openclaw/workspace",
      "status": "running",
      "createdAt": "2026-03-25T15:06:00-04:00",
      "lastActivity": "2026-03-25T15:06:00-04:00"
    }
  },
  "nextPort": 18801
}
```

The repo seed file is [`skills/fleet-manager/schemas/instances.json`](../skills/fleet-manager/schemas/instances.json).
