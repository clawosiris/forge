# Forge — Multi-Agent Engineering Process for OpenClaw

A structured, multi-agent software development workflow that now ships with a container-native Fleet Manager for running multiple Forge instances as sibling Podman containers.

## Fleet Manager Architecture

```text
Host Machine
│
├── /run/user/1000/podman/podman.sock
│         │
│         ▼
│  ┌──────────────────────────────────────────────────────┐
│  │ Fleet Manager Container (:18799)                     │
│  │ - OpenClaw + fleet-manager skill                     │
│  │ - Podman socket mounted                              │
│  │ - Runs `podman` to manage siblings                   │
│  └──────────────────────┬───────────────────────────────┘
│                         │
│         ┌───────────────┼───────────────┐
│         ▼               ▼               ▼
│  ┌──────────┐    ┌──────────┐    ┌──────────┐
│  │ Forge A  │    │ Forge B  │    │ Forge C  │
│  │ :18801   │    │ :18802   │    │ :18803   │
│  └──────────┘    └──────────┘    └──────────┘
```

The old Unix-user-per-instance model is gone. Fleet Manager is now a rootless Podman container that provisions Forge instances as sibling containers, with credentials delivered through Podman secrets and persistent data stored in named volumes.

## Quick Start

```bash
git clone https://github.com/clawosiris/forge.git
cd forge
./deploy.sh
```

`deploy.sh` now:
- validates `podman`, `podman.socket`, and `systemd --user`
- prompts for API keys and gateway token if they are not exported
- creates Podman secrets
- builds the `fleet-manager` and `forge-instance` images
- creates the `forge-fleet` network
- starts the Fleet Manager container on `127.0.0.1:18799`

## Repo Layout

- `fleet-manager/containers/` contains the build contexts for the Fleet Manager and Forge instance images
- `skills/fleet-manager/` contains the provisioning, teardown, and status scripts used inside the manager container
- `ansible/` contains a rootless Podman deployment role using a quadlet
- `docs/fleet-manager.md` documents runtime operations and state

## Operations

Provision, inspect, and destroy Forge instances with the Fleet Manager skill:

```bash
skills/fleet-manager/scripts/provision.sh client-a
skills/fleet-manager/scripts/status.sh
skills/fleet-manager/scripts/teardown.sh --archive client-a
```

## Ansible

Use the included role when you want repeatable remote deployment instead of the local `deploy.sh` flow:

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
ansible-vault encrypt vault.yml
ansible-playbook -i inventory/hosts.yml deploy.yml --ask-vault-pass
```

More detail is in [`docs/fleet-manager.md`](docs/fleet-manager.md) and [`ansible/README.md`](ansible/README.md).
