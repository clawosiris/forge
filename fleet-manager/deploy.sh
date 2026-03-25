#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

FLEET_HOME="${FLEET_MANAGER_HOST_STATE_DIR:-${HOME}/.fleet-manager}"
PODMAN_SOCKET="${PODMAN_SOCKET:-/run/user/$(id -u)/podman/podman.sock}"
NETWORK_NAME="${FLEET_NETWORK_NAME:-forge-fleet}"
FLEET_IMAGE="${FLEET_MANAGER_IMAGE:-forge-fleet-manager:latest}"
INSTANCE_IMAGE="${FORGE_INSTANCE_IMAGE:-openclaw-forge:latest}"
CONTAINER_NAME="${FLEET_MANAGER_CONTAINER_NAME:-fleet-manager}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { printf '%b\n' "${BLUE}[fleet-manager]${NC} $*"; }
ok()    { printf '%b\n' "${GREEN}[ok]${NC} $*"; }
warn()  { printf '%b\n' "${YELLOW}[warn]${NC} $*"; }
fail()  { printf '%b\n' "${RED}[fail]${NC} $*" >&2; }

check_prereqs() {
  local missing=0

  for bin in podman jq; do
    if ! command -v "${bin}" >/dev/null 2>&1; then
      fail "missing required binary: ${bin}"
      missing=1
    fi
  done

  if ! systemctl --user status >/dev/null 2>&1; then
    fail "systemd --user is not available"
    missing=1
  fi

  if [[ ! -S "${PODMAN_SOCKET}" ]]; then
    fail "podman socket not found: ${PODMAN_SOCKET}"
    warn "start it with: systemctl --user enable --now podman.socket"
    missing=1
  fi

  if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
    warn "ANTHROPIC_API_KEY is not set; new instances will not be usable until you provide it"
  fi

  if [[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
    warn "OPENCLAW_GATEWAY_TOKEN is not set; set one before exposing Fleet Manager"
  fi

  return "${missing}"
}

build_images() {
  log "Building Fleet Manager image"
  podman build -t "${FLEET_IMAGE}" -f "${SCRIPT_DIR}/Dockerfile" "${PROJECT_ROOT}"
  ok "built ${FLEET_IMAGE}"

  log "Building Forge instance image"
  podman build -t "${INSTANCE_IMAGE}" -f "${SCRIPT_DIR}/forge-instance/Dockerfile" "${PROJECT_ROOT}"
  ok "built ${INSTANCE_IMAGE}"
}

create_runtime() {
  mkdir -p "${FLEET_HOME}/fleet/archives" "${FLEET_HOME}/fleet/logs"

  if ! podman network exists "${NETWORK_NAME}"; then
    podman network create "${NETWORK_NAME}" >/dev/null
    ok "created podman network ${NETWORK_NAME}"
  else
    ok "podman network ${NETWORK_NAME} already exists"
  fi
}

start_container() {
  if podman container exists "${CONTAINER_NAME}"; then
    log "Replacing existing ${CONTAINER_NAME} container"
    if [[ "$(podman inspect --format '{{.State.Status}}' "${CONTAINER_NAME}")" == "running" ]]; then
      podman stop "${CONTAINER_NAME}" >/dev/null
    fi
    podman rm "${CONTAINER_NAME}" >/dev/null
  fi

  podman run -d \
    --name "${CONTAINER_NAME}" \
    --network "${NETWORK_NAME}" \
    -p 18799:18799 \
    -v "${PODMAN_SOCKET}:/run/podman/podman.sock" \
    -v "${FLEET_HOME}:/home/openclaw/.openclaw:Z" \
    -e "CONTAINER_HOST=unix:///run/podman/podman.sock" \
    -e "FLEET_MANAGER_HOST_STATE_DIR=${FLEET_HOME}" \
    -e "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}" \
    -e "OPENAI_API_KEY=${OPENAI_API_KEY:-}" \
    -e "OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN:-}" \
    --restart unless-stopped \
    "${FLEET_IMAGE}" >/dev/null

  ok "started ${CONTAINER_NAME}"
}

print_summary() {
  cat <<EOT

Fleet Manager is running.

Connection:
  URL: http://127.0.0.1:18799
  Auth token: ${OPENCLAW_GATEWAY_TOKEN:-<unset>}

State:
  Host state dir: ${FLEET_HOME}
  Podman socket: ${PODMAN_SOCKET}
  Network: ${NETWORK_NAME}

Next steps:
  1. Confirm the gateway is reachable on port 18799.
  2. Talk to the Fleet Manager agent and use the fleet-manager skill.
  3. Provision a Forge instance with:
     ${FLEET_HOME}/workspace/skills/fleet-manager/scripts/provision.sh client-a --channel none --model opus
EOT
}

main() {
  check_prereqs || exit 1
  build_images
  create_runtime
  start_container
  print_summary
}

main "$@"
