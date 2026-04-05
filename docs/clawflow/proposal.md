# Proposal: ClawFlow Integration for OpenSpec Dev Workflow

## Problem

The multi-agent development workflow (OpenSpec → Codex → Review) spans multiple
sessions and has two hard synchronization points where execution must pause for
human review. Without persistent state:

- Session restarts lose context ("what PR was I waiting on?")
- No way to run multiple features in parallel without manual tracking
- Handoffs between phases rely on conversational memory, which is fragile
- "Where are we on X?" requires reconstructing state from chat history

## Solution

Introduce a lightweight ClawFlow implementation backed by JSON files in
`flows/active/`. A small `flow` CLI manages lifecycle state. The workflow doc is
updated to call `flow` commands at each phase transition.

## What Changes

1. `flows/` directory structure in workspace
2. `flows/bin/flow` — Node.js CLI for flow state management
3. `workflows/openspec-development.md` — updated to use flow commands
4. HEARTBEAT.md — add "check waiting flows" to periodic checks

## What Doesn't Change

- The three-phase structure (Spec → Implement → Review)
- How Codex is invoked (acpx + codex exec)
- Human approval gates
- OpenSpec file conventions in repos

## Design Decisions

- **Backing store**: workspace JSON files (not SQLite, not Trilium)
  - Human-readable, manually editable when flows get stuck
  - Zero new dependencies
  - Consistent with existing MEMORY.md / heartbeat-state.json patterns
- **Resume trigger**: human-driven ("proceed", "spec merged")
  - Matches current behavior, formalizes it with `flow resume`
  - GitHub webhook auto-resume is a future improvement
- **Scope**: Osiris workspace only (not a general ClawFlow runtime)
