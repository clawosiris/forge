# Knowledge Directory

Project knowledge files that the supervisor selectively injects into specialist agents.

## Files

| File | Purpose | Injected Into |
|------|---------|---------------|
| `project-context.md` | Codebase overview, stack, conventions | All agents |
| `past-decisions.md` | Architectural decisions + rationale | Analyst, Implementer |
| `known-issues.md` | Recurring problems, tech debt | Analyst |
| `patterns.md` | What works/doesn't in the codebase | Implementer |
| `chaos-catalog.md` | Historical adversarial findings | Chaos Agent (Ralph) |

## Multi-Project Setup

For multiple projects, create subdirectories:

```
knowledge/
├── project-a/
│   ├── project-context.md
│   ├── past-decisions.md
│   └── ...
└── project-b/
    └── ...
```

## Maintenance

The supervisor updates these files after each workflow:
- New decisions → `past-decisions.md`
- New patterns → `patterns.md`
- Chaos findings → `chaos-catalog.md`
