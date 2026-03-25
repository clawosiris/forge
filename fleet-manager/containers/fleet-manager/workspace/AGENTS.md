# Fleet Manager Workspace

- Use `skills/fleet-manager/` to provision, inspect, pause, resume, archive, and destroy Forge instances.
- Manage sibling Forge runtimes through the mounted Podman socket at `/run/podman/podman.sock`.
- Treat `~/.fleet-manager/instances.json` as the source of truth for allocated ports, container names, and volume names.
