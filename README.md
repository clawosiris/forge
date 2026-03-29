# Forge — Multi-Agent Engineering Process for OpenClaw

A structured, multi-agent software development workflow that orchestrates specialized AI agents through analysis, specification, implementation, and review phases. Ships with a container-native Fleet Manager for running multiple Forge instances.

## Core Principles

### Model Diversity as Defense-in-Depth

Forge deliberately uses **different model families** for generation vs review:

| Phase | Model | Harness | Why |
|-------|-------|---------|-----|
| Analysis | Claude Opus 4.6 | Subagent | Deep reasoning for requirements |
| Spec Review | Claude Sonnet 4 | Subagent | Fresh perspective, minimal context |
| **Implementation** | **GPT-5.3-codex** | **Codex CLI/ACP** | Autonomous coding, edit→test→fix |
| **Code Review** | **Claude Sonnet 4** | **Claude Code CLI/ACP** | Careful analysis, GitHub integration |
| Chaos Testing | o3-mini | Subagent | Reasoning model for adversarial exploration |
| Security Audit | Claude Sonnet 4 | Subagent | Structured security checklist |

**Key rule:** Never call LLM APIs directly for implementation or review. Always route through the coding agent harnesses (Codex, Claude Code) which provide workspace isolation, file operations, and enforced constraints.

### Review Findings as GitHub Issues

PR review findings are filed as GitHub Issues with `review-finding` labels for tracking and resolution.

### Role Assignment via Issue Labels

Forge can assign workflow ownership to agent roles using `role:*` labels on the requirement issue (`role:analyst`, `role:implementer`, `role:pr-reviewer`, etc.).
The Supervisor updates one active role label per state transition and routes execution accordingly.

### Worklog for Extended Sessions

Agents maintain `worklog.md` files during implementation with progress tracking, enabling crash recovery and visibility.

### Evidence Bundles (Audit Artifact)

For High/Critical tier workflows, Forge generates an immutable `evidence-bundle.json` capturing:
- Spec/approval metadata
- AI usage flags (tool, model, scope)
- Human reviewer ID and approval timestamp
- Role separation verification
- CI control outcomes
- Finding lifecycle and closure evidence
- Bundle hash for integrity

## Agent Pipeline

```
Requirement → Analyst → Spec Review → [Human Gate] → Implementer (Codex)
    → CI Monitor → Chaos/Security (parallel) → PR Review (Claude Code) 
    → GitHub Issues → [Human Gate] → Release
```

See [`docs/agent-pipeline.md`](docs/agent-pipeline.md) for full documentation.

## Quick Start

```bash
git clone https://github.com/clawosiris/forge.git
cd forge
./deploy.sh
```

`deploy.sh` handles:
- Validates `podman`, `podman.socket`, and `systemd --user`
- Prompts for API keys and gateway token
- Creates Podman secrets
- Builds Fleet Manager and Forge instance images
- Starts Fleet Manager on `127.0.0.1:18799`

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

Fleet Manager provisions Forge instances as sibling Podman containers with credentials delivered through Podman secrets.

## Repo Layout

```
forge/
├── ansible/                    # Rootless Podman deployment role
├── config/                     # Configuration templates
├── docs/
│   ├── agent-pipeline.md       # Full pipeline documentation
│   ├── fleet-manager.md        # Runtime operations
│   └── rules/                  # Review checklist, escalation protocol
├── fleet-manager/containers/   # Container build contexts
├── journal/                    # Project journal entries
├── skills/fleet-manager/       # Provisioning scripts
└── workspace/
    └── templates/
        ├── forge-supervisor.md # Supervisor prompt
        └── agents/             # Agent role templates
            ├── analyst.md
            ├── chaos-ralph.md
            ├── code-reviewer.md
            ├── implementer.md
            ├── pr-reviewer.md
            ├── security-auditor.md
            └── spec-reviewer.md
```

## Operations

Provision, inspect, and destroy Forge instances:

```bash
skills/fleet-manager/scripts/provision.sh client-a
skills/fleet-manager/scripts/status.sh
skills/fleet-manager/scripts/teardown.sh --archive client-a
```

## Ansible Deployment

For repeatable remote deployment:

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
ansible-vault encrypt vault.yml
ansible-playbook -i inventory/hosts.yml deploy.yml --ask-vault-pass
```

See [`ansible/README.md`](ansible/README.md) for details.

## Agent Roster

| Role | Runtime | Model | Purpose |
|------|---------|-------|---------|
| Analyst | subagent | claude-opus-4-6 | Requirements → OpenSpec |
| Spec Reviewer | subagent | claude-sonnet-4 | Spec quality gate |
| **Implementer** | **Codex ACP** | **gpt-5.3-codex** | Code implementation |
| **PR Reviewer** | **Claude Code ACP** | **claude-sonnet-4** | Review → GitHub Issues |
| Chaos Ralph | subagent | o3-mini | Adversarial testing |
| Security Auditor | subagent | claude-sonnet-4 | Security checklist |

## Workflow Tiers

| Tier | Scope | Agents |
|------|-------|--------|
| Small | Bug fix, <50 LOC | Implementer + PR Reviewer |
| Medium | Feature, 50-500 LOC | + Analyst + Spec Reviewer |
| Large | Architecture, >500 LOC | + Chaos Ralph + Security Auditor |

## Circuit Breakers

| Limit | Threshold |
|-------|-----------|
| Agent spawns | Max 15/workflow |
| Wall-clock | Max 4 hours |
| Iterations | Max 3/loop |

## BSI/ANSSI Compliance

This workflow aligns with BSI/ANSSI recommendations for AI coding assistants:

- Human gates at spec approval and merge approval
- Different model families for generation vs review (defense-in-depth)
- Review findings tracked as GitHub Issues
- Structured security audit with anti-manipulation clause
- Worklog documentation for audit trail

See [Human Validation Proposal](https://codeberg.org/llnvd/pages/src/branch/main/content/gists/openclaw/human-validation-spec-test-driven-dev.md) for the full compliance framework.

## Documentation

- [Agent Pipeline](docs/agent-pipeline.md) — Full pipeline with model rationale
- [Fleet Manager](docs/fleet-manager.md) — Container operations
- [Supervisor Template](workspace/templates/forge-supervisor.md) — Orchestration prompt
- [Agent Templates](workspace/templates/agents/) — Role-specific prompts

## License

Apache 2.0 — See [LICENSE](LICENSE)
