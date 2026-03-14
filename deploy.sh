#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════
# Forge — Multi-Agent Engineering Process Deployment Script
# ═══════════════════════════════════════════════════════════════════════════
#
# Usage:
#   ./deploy.sh              Deploy as standalone instance
#   ./deploy.sh --addon      Show merge instructions for existing instance
#   ./deploy.sh --sandbox    Build sandbox image only
#   ./deploy.sh --check      Verify deployment
#   ./deploy.sh --help       Show this help
# ═══════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
WORKSPACE_DIR="${OPENCLAW_DIR}/workspace"
CONFIG_FILE="${OPENCLAW_DIR}/openclaw.json"
SANDBOX_IMAGE="openclaw-sandbox:bookworm-slim"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${BLUE}[forge]${NC} $*"; }
ok()    { echo -e "${GREEN}[  ok ]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
err()   { echo -e "${RED}[fail]${NC} $*"; }

# ─── Help ─────────────────────────────────────────────────────────────────

show_help() {
  cat <<'EOF'
Forge — Multi-Agent Engineering Process Deployment

Usage:
  ./deploy.sh              Deploy as standalone instance (fresh install)
  ./deploy.sh --addon      Show merge instructions for existing instance
  ./deploy.sh --sandbox    Build sandbox container image only
  ./deploy.sh --check      Verify deployment health
  ./deploy.sh --help       Show this help

Environment:
  OPENCLAW_STATE_DIR       OpenClaw state directory (default: ~/.openclaw)
  OPENCLAW_GATEWAY_TOKEN   Gateway auth token (generated if missing)
  ANTHROPIC_API_KEY        Required: Anthropic API key
  OPENAI_API_KEY           Optional: OpenAI fallback API key

Prerequisites:
  - Node.js 20+
  - Docker (for container sandboxing)
  - OpenClaw (installed globally via npm)

EOF
}

# ─── Prerequisites ────────────────────────────────────────────────────────

check_prereqs() {
  local missing=0

  if ! command -v node &>/dev/null; then
    err "Node.js not found. Install Node.js 20+."
    missing=1
  else
    local node_major
    node_major=$(node -e 'console.log(process.versions.node.split(".")[0])')
    if (( node_major < 20 )); then
      err "Node.js ${node_major} found, need 20+."
      missing=1
    else
      ok "Node.js $(node --version)"
    fi
  fi

  if ! command -v openclaw &>/dev/null; then
    err "OpenClaw not found. Install: npm install -g openclaw"
    missing=1
  else
    ok "OpenClaw $(openclaw --version 2>/dev/null || echo 'installed')"
  fi

  if ! command -v docker &>/dev/null; then
    err "Docker not found. Required for container sandboxing."
    missing=1
  else
    if docker info &>/dev/null; then
      ok "Docker $(docker --version | grep -oP '\d+\.\d+\.\d+')"
    else
      err "Docker installed but daemon not running."
      missing=1
    fi
  fi

  if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
    warn "ANTHROPIC_API_KEY not set. You'll need to configure it in openclaw.json or .env"
  else
    ok "ANTHROPIC_API_KEY set"
  fi

  return $missing
}

# ─── Sandbox Image ────────────────────────────────────────────────────────

build_sandbox() {
  log "Building sandbox container image..."

  if docker image inspect "$SANDBOX_IMAGE" &>/dev/null; then
    ok "Sandbox image already exists: $SANDBOX_IMAGE"
    read -rp "Rebuild? [y/N] " rebuild
    if [[ ! "$rebuild" =~ ^[yY]$ ]]; then
      return 0
    fi
  fi

  # Check if OpenClaw ships a sandbox setup script
  local openclaw_root
  openclaw_root="$(npm root -g)/openclaw"

  if [[ -x "${openclaw_root}/scripts/sandbox-setup.sh" ]]; then
    log "Using OpenClaw's sandbox-setup.sh..."
    bash "${openclaw_root}/scripts/sandbox-setup.sh"
  else
    log "Building sandbox image from inline Dockerfile..."
    docker build -t "$SANDBOX_IMAGE" -f - . <<'DOCKERFILE'
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl wget jq ca-certificates \
    build-essential python3 python3-pip python3-venv \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 20 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd -g 1000 sandbox && useradd -u 1000 -g sandbox -m sandbox
USER sandbox
WORKDIR /workspace

ENV LANG=C.UTF-8
DOCKERFILE
  fi

  ok "Sandbox image built: $SANDBOX_IMAGE"
}

# ─── Workspace Setup ──────────────────────────────────────────────────────

setup_workspace() {
  log "Setting up workspace at ${WORKSPACE_DIR}..."

  mkdir -p "${WORKSPACE_DIR}"/{templates/agents,knowledge,specs/changes,memory,projects}

  # Copy workspace files (don't overwrite existing)
  local src="${SCRIPT_DIR}/workspace"
  local files=(
    "AGENTS.md"
    "SOUL.md"
    "TOOLS.md"
    "MEMORY.md"
    "HEARTBEAT.md"
    "templates/forge-supervisor.md"
    "templates/agents/analyst.md"
    "templates/agents/spec-reviewer.md"
    "templates/agents/implementer.md"
    "templates/agents/pr-reviewer.md"
    "templates/agents/chaos-ralph.md"
    "knowledge/README.md"
    "knowledge/project-context.md"
    "knowledge/past-decisions.md"
    "knowledge/known-issues.md"
    "knowledge/patterns.md"
    "knowledge/chaos-catalog.md"
  )

  local copied=0
  local skipped=0
  for f in "${files[@]}"; do
    local dest="${WORKSPACE_DIR}/${f}"
    if [[ -f "$dest" ]]; then
      skipped=$((skipped + 1))
    else
      mkdir -p "$(dirname "$dest")"
      cp "${src}/${f}" "$dest"
      copied=$((copied + 1))
    fi
  done

  ok "Workspace: ${copied} files copied, ${skipped} already existed (not overwritten)"
}

# ─── Config Setup ─────────────────────────────────────────────────────────

setup_config() {
  log "Setting up configuration..."

  if [[ -f "$CONFIG_FILE" ]]; then
    warn "Config already exists: ${CONFIG_FILE}"
    warn "Backing up to ${CONFIG_FILE}.bak"
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
  fi

  # Generate gateway token if not set
  if [[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
    local token
    token=$(openssl rand -hex 32 2>/dev/null || head -c 64 /dev/urandom | xxd -p | tr -d '\n' | head -c 64)
    log "Generated gateway token. Add to your environment:"
    echo ""
    echo "  export OPENCLAW_GATEWAY_TOKEN=\"${token}\""
    echo ""
    echo "  # Or add to ~/.openclaw/.env:"
    echo "  echo 'OPENCLAW_GATEWAY_TOKEN=${token}' >> ~/.openclaw/.env"
    echo ""
    export OPENCLAW_GATEWAY_TOKEN="$token"
  fi

  # Copy config (JSON5 → json, OpenClaw reads both)
  cp "${SCRIPT_DIR}/config/openclaw-standalone.json5" "$CONFIG_FILE"

  ok "Config written to ${CONFIG_FILE}"
  warn "You MUST edit ${CONFIG_FILE} to set:"
  echo "    - channels.signal.allowFrom (your phone number)"
  echo "    - tools.elevated.allowFrom (same)"
  echo "    - agents.defaults.userTimezone (your timezone)"
  echo "    - API keys (env vars or inline)"
}

# ─── Addon Mode ───────────────────────────────────────────────────────────

show_addon() {
  cat <<EOF

${BLUE}═══ Forge Addon Mode ═══${NC}

To add Forge to your existing OpenClaw instance:

${YELLOW}1. Merge config changes:${NC}
   Review: ${SCRIPT_DIR}/config/openclaw-addon.json5
   Merge the marked sections into your ${CONFIG_FILE}

${YELLOW}2. Copy workspace files:${NC}
   cp -rn ${SCRIPT_DIR}/workspace/templates/ ${WORKSPACE_DIR}/templates/
   cp -rn ${SCRIPT_DIR}/workspace/knowledge/ ${WORKSPACE_DIR}/knowledge/
   mkdir -p ${WORKSPACE_DIR}/specs/changes

${YELLOW}3. Add to your AGENTS.md:${NC}
   Append the contents of ${SCRIPT_DIR}/workspace/AGENTS.md
   (the "Engineering Workflows" section) to your existing AGENTS.md

${YELLOW}4. Build sandbox image:${NC}
   ./deploy.sh --sandbox

${YELLOW}5. Restart:${NC}
   openclaw gateway restart

EOF
}

# ─── Health Check ─────────────────────────────────────────────────────────

check_deployment() {
  log "Checking deployment health..."
  local issues=0

  # Config
  if [[ -f "$CONFIG_FILE" ]]; then
    ok "Config exists: ${CONFIG_FILE}"
  else
    err "Config missing: ${CONFIG_FILE}"
    issues=$((issues + 1))
  fi

  # Workspace
  local required_files=(
    "AGENTS.md" "SOUL.md"
    "templates/forge-supervisor.md"
    "templates/agents/analyst.md"
    "templates/agents/spec-reviewer.md"
    "templates/agents/implementer.md"
    "templates/agents/pr-reviewer.md"
    "templates/agents/chaos-ralph.md"
  )
  for f in "${required_files[@]}"; do
    if [[ -f "${WORKSPACE_DIR}/${f}" ]]; then
      ok "Workspace: ${f}"
    else
      err "Missing: ${WORKSPACE_DIR}/${f}"
      issues=$((issues + 1))
    fi
  done

  # Directories
  for d in knowledge specs/changes memory projects; do
    if [[ -d "${WORKSPACE_DIR}/${d}" ]]; then
      ok "Directory: ${d}/"
    else
      err "Missing directory: ${WORKSPACE_DIR}/${d}/"
      issues=$((issues + 1))
    fi
  done

  # Sandbox image
  if docker image inspect "$SANDBOX_IMAGE" &>/dev/null; then
    ok "Sandbox image: ${SANDBOX_IMAGE}"
  else
    err "Sandbox image missing. Run: ./deploy.sh --sandbox"
    issues=$((issues + 1))
  fi

  # Gateway status
  if command -v openclaw &>/dev/null; then
    if openclaw gateway status &>/dev/null 2>&1; then
      ok "Gateway: running"
    else
      warn "Gateway: not running (start with: openclaw gateway start)"
    fi
  fi

  echo ""
  if (( issues == 0 )); then
    ok "All checks passed ✓"
  else
    err "${issues} issue(s) found"
  fi
  return $issues
}

# ─── Main ─────────────────────────────────────────────────────────────────

main() {
  case "${1:-}" in
    --help|-h)
      show_help
      exit 0
      ;;
    --addon)
      show_addon
      exit 0
      ;;
    --sandbox)
      check_prereqs || true
      build_sandbox
      exit 0
      ;;
    --check)
      check_deployment
      exit $?
      ;;
    "")
      # Full standalone deploy
      ;;
    *)
      err "Unknown option: $1"
      show_help
      exit 1
      ;;
  esac

  echo ""
  echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}  Forge — Multi-Agent Engineering Process          ${NC}"
  echo -e "${BLUE}  Standalone Deployment                            ${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
  echo ""

  log "Checking prerequisites..."
  if ! check_prereqs; then
    err "Prerequisites not met. Fix the issues above and re-run."
    exit 1
  fi
  echo ""

  build_sandbox
  echo ""

  setup_workspace
  echo ""

  setup_config
  echo ""

  echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}  Deployment complete!                             ${NC}"
  echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
  echo ""
  echo "Next steps:"
  echo ""
  echo "  1. Edit config:    \$EDITOR ${CONFIG_FILE}"
  echo "     - Set your phone number in allowFrom"
  echo "     - Set your timezone"
  echo "     - Configure API keys"
  echo ""
  echo "  2. Set gateway token in your environment:"
  echo "     export OPENCLAW_GATEWAY_TOKEN=\"...\""
  echo ""
  echo "  3. Link your channel:"
  echo "     openclaw channels login --channel signal"
  echo ""
  echo "  4. Start the gateway:"
  echo "     openclaw gateway start"
  echo ""
  echo "  5. Verify:"
  echo "     ./deploy.sh --check"
  echo ""
  echo "  6. Send a message in your channel:"
  echo "     \"Start an engineering workflow for my-project: add user authentication\""
  echo ""
}

main "$@"
