# AGENTS.md Snippet for Group-Bound Agents

Add this section to AGENTS.md for agents that clone repos or do long-running work:

```markdown
## Temporary Files

Use `/var/tmp` instead of `/tmp` for cloning repos and long-running work:
- `/var/tmp` is disk-backed and survives reboots
- `/tmp` is tmpfs (RAM-backed) and cleared on reboot

\`\`\`bash
# Good
cd /var/tmp && git clone ...
WORK_DIR=$(mktemp -d -p /var/tmp)

# Avoid for large repos
cd /tmp && git clone ...
\`\`\`
```

## Rationale

On most Linux systems (including Fedora), `/tmp` is mounted as tmpfs (RAM-backed). This means:
- Large git clones consume RAM instead of disk
- Files are lost on reboot (problematic for long-running Codex tasks)
- Memory pressure can cause OOM issues

`/var/tmp` is disk-backed and persists across reboots, making it suitable for:
- Git clones of large repositories
- Codex/coding agent work directories
- Any task that may run for 20+ minutes
