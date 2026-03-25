#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINERS_DIR="${SCRIPT_DIR}/fleet-manager/containers"
FLEET_MANAGER_CONTEXT="${CONTAINERS_DIR}/fleet-manager"
FORGE_INSTANCE_CONTEXT="${CONTAINERS_DIR}/forge-instance"

PODMAN_SOCKET="${PODMAN_SOCKET:-/run/user/$(id -u)/podman/podman.sock}"
FLEET_MANAGER_IMAGE="${FLEET_MANAGER_IMAGE:-localhost/openclaw-fleet-manager:latest}"
FORGE_INSTANCE_IMAGE="${FORGE_INSTANCE_IMAGE:-localhost/openclaw-forge:latest}"
FLEET_MANAGER_CONTAINER="${FLEET_MANAGER_CONTAINER:-fleet-manager}"
FLEET_MANAGER_NETWORK="${FLEET_MANAGER_NETWORK:-forge-fleet}"
FLEET_MANAGER_PORT="${FLEET_MANAGER_PORT:-18799}"
FLEET_MANAGER_REPO_MOUNT="${FLEET_MANAGER_REPO_MOUNT:-/opt/forge-fleet-manager}"
FLEET_MANAGER_STATE_VOLUME="${FLEET_MANAGER_STATE_VOLUME:-fleet-manager-state}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${BLUE}[deploy]${NC} $*"; }
ok()    { echo -e "${GREEN}[  ok ]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
fail()  { echo -e "${RED}[fail]${NC} $*" >&2; exit 1; }

show_help() {
  cat <<'USAGE'
Usage:
  ./deploy.sh
  ./deploy.sh --check
  ./deploy.sh --help

Environment:
  PODMAN_SOCKET              Default: /run/user/<uid>/podman/podman.sock
  FLEET_MANAGER_IMAGE        Default: localhost/openclaw-fleet-manager:latest
  FORGE_INSTANCE_IMAGE       Default: localhost/openclaw-forge:latest
  FLEET_MANAGER_CONTAINER    Default: fleet-manager
  FLEET_MANAGER_NETWORK      Default: forge-fleet
  FLEET_MANAGER_PORT         Default: 18799
  FLEET_MANAGER_STATE_VOLUME Default: fleet-manager-state

Secrets read from the environment or prompted interactively:
  ANTHROPIC_API_KEY
  OPENAI_API_KEY
  OPENCLAW_GATEWAY_TOKEN
USAGE
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

check_prereqs() {
  require_cmd podman
  require_cmd systemctl
  require_cmd loginctl

  [[ -S "${PODMAN_SOCKET}" ]] || fail "Podman socket not found: ${PODMAN_SOCKET}"

  if ! systemctl --user show-environment >/dev/null 2>&1; then
    fail "systemd --user is unavailable for $(whoami)"
  fi

  ok "Podman socket: ${PODMAN_SOCKET}"
  ok "systemd --user is available"
}

prompt_secret() {
  local var_name="$1"
  local prompt="$2"
  local current_value="${!var_name:-}"

  if [[ -n "${current_value}" ]]; then
    return 0
  fi

  read -rsp "${prompt}: " current_value
  echo ""
  [[ -n "${current_value}" ]] || fail "${var_name} is required"
  printf -v "$var_name" '%s' "$current_value"
  export "$var_name"
}

remove_existing_container() {
  if podman container exists "${FLEET_MANAGER_CONTAINER}"; then
    podman rm -f "${FLEET_MANAGER_CONTAINER}" >/dev/null
    ok "Removed existing container ${FLEET_MANAGER_CONTAINER}"
  fi
}

secret_upsert() {
  local secret_name="$1"
  local secret_value="$2"

  if podman secret inspect "${secret_name}" >/dev/null 2>&1; then
    podman secret rm "${secret_name}" >/dev/null
  fi

  printf '%s' "${secret_value}" | podman secret create "${secret_name}" - >/dev/null
}

create_secrets() {
  prompt_secret ANTHROPIC_API_KEY "Anthropic API key"
  prompt_secret OPENAI_API_KEY "OpenAI API key"
  prompt_secret OPENCLAW_GATEWAY_TOKEN "Gateway token"

  log "Creating podman secrets"
  secret_upsert anthropic-api-key "${ANTHROPIC_API_KEY}"
  secret_upsert openai-api-key "${OPENAI_API_KEY}"
  secret_upsert gateway-token "${OPENCLAW_GATEWAY_TOKEN}"
  ok "Secrets created"
}

build_images() {
  log "Building ${FLEET_MANAGER_IMAGE}"
  podman build -t "${FLEET_MANAGER_IMAGE}" "${FLEET_MANAGER_CONTEXT}"

  log "Building ${FORGE_INSTANCE_IMAGE}"
  podman build -t "${FORGE_INSTANCE_IMAGE}" "${FORGE_INSTANCE_CONTEXT}"

  ok "Images built"
}

ensure_network() {
  if ! podman network exists "${FLEET_MANAGER_NETWORK}"; then
    podman network create "${FLEET_MANAGER_NETWORK}" >/dev/null
    ok "Created network ${FLEET_MANAGER_NETWORK}"
  else
    ok "Network ${FLEET_MANAGER_NETWORK} already exists"
  fi
}

start_fleet_manager() {
  log "Starting fleet-manager container"
  podman run -d \
    --name "${FLEET_MANAGER_CONTAINER}" \
    --hostname "${FLEET_MANAGER_CONTAINER}" \
    --network "${FLEET_MANAGER_NETWORK}" \
    -p "127.0.0.1:${FLEET_MANAGER_PORT}:${FLEET_MANAGER_PORT}" \
    -e "FLEET_REPO_ROOT=${FLEET_MANAGER_REPO_MOUNT}" \
    -v "${PODMAN_SOCKET}:/run/podman/podman.sock:Z" \
    -v "${SCRIPT_DIR}:${FLEET_MANAGER_REPO_MOUNT}:ro,Z" \
    -v "${FLEET_MANAGER_STATE_VOLUME}:/home/openclaw/.fleet-manager:Z" \
    --secret anthropic-api-key,target=ANTHROPIC_API_KEY \
    --secret openai-api-key,target=OPENAI_API_KEY \
    --secret gateway-token,target=GATEWAY_AUTH_TOKEN \
    "${FLEET_MANAGER_IMAGE}" >/dev/null

  ok "Fleet Manager started"
}

check_deployment() {
  require_cmd podman

  podman image inspect "${FLEET_MANAGER_IMAGE}" >/dev/null 2>&1 || fail "Missing image ${FLEET_MANAGER_IMAGE}"
  podman image inspect "${FORGE_INSTANCE_IMAGE}" >/dev/null 2>&1 || fail "Missing image ${FORGE_INSTANCE_IMAGE}"
  podman secret inspect anthropic-api-key >/dev/null 2>&1 || fail "Missing podman secret anthropic-api-key"
  podman secret inspect openai-api-key >/dev/null 2>&1 || fail "Missing podman secret openai-api-key"
  podman secret inspect gateway-token >/dev/null 2>&1 || fail "Missing podman secret gateway-token"
  podman network exists "${FLEET_MANAGER_NETWORK}" || fail "Missing network ${FLEET_MANAGER_NETWORK}"
  podman volume exists "${FLEET_MANAGER_STATE_VOLUME}" || fail "Missing state volume ${FLEET_MANAGER_STATE_VOLUME}"
  podman container exists "${FLEET_MANAGER_CONTAINER}" || fail "Missing container ${FLEET_MANAGER_CONTAINER}"

  local status
  status="$(podman inspect --format '{{.State.Status}}' "${FLEET_MANAGER_CONTAINER}")"
  [[ "${status}" == "running" ]] || fail "Container ${FLEET_MANAGER_CONTAINER} is ${status}"

  ok "Fleet Manager container is running"
  echo "endpoint=http://127.0.0.1:${FLEET_MANAGER_PORT}"
}

main() {
  case "${1:-}" in
    --help|-h)
      show_help
      exit 0
      ;;
    --check)
      check_deployment
      exit 0
      ;;
    "")
      ;;
    *)
      fail "Unknown option: ${1}"
      ;;
  esac

  check_prereqs
  remove_existing_container
  create_secrets
  build_images
  ensure_network
  start_fleet_manager

  echo ""
  ok "Deployment complete"
  echo "fleet_manager_image=${FLEET_MANAGER_IMAGE}"
  echo "forge_instance_image=${FORGE_INSTANCE_IMAGE}"
  echo "container=${FLEET_MANAGER_CONTAINER}"
  echo "endpoint=http://127.0.0.1:${FLEET_MANAGER_PORT}"
  echo "podman_socket=${PODMAN_SOCKET}"
  echo "state_volume=${FLEET_MANAGER_STATE_VOLUME}"
}

main "$@"
