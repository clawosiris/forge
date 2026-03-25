# Ansible Deployment

This directory deploys the Fleet Manager as a rootless Podman quadlet and builds the Forge sibling container image on the target host.

## Files

- `requirements.yml` installs `containers.podman`
- `inventory/hosts.yml.example` is a starter inventory
- `vault.yml.example` shows the vaulted secret variables
- `deploy.yml` runs the `fleet_manager` role

## Usage

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
ansible-vault encrypt vault.yml
ansible-playbook -i inventory/hosts.yml deploy.yml --ask-vault-pass
```

The role:
- installs Podman
- enables lingering and `podman.socket` for the target user
- copies the container build contexts
- builds the fleet-manager and forge-instance images
- rotates Podman secrets from vaulted vars
- provisions a persistent `fleet-manager-state` volume
- writes the quadlet and OpenClaw config
- starts `fleet-manager.service`
