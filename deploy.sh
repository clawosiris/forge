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
STARTUP_GRACE_SECONDS="${STARTUP_GRACE_SECONDS:-12}"

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
  ./deploy.sh --recreate-secrets
  ./deploy.sh --help

Environment:
  PODMAN_SOCKET              Default: /run/user/<uid>/podman/podman.sock
  FLEET_MANAGER_IMAGE        Default: localhost/openclaw-fleet-manager:latest
  FORGE_INSTANCE_IMAGE       Default: localhost/openclaw-forge:latest
  FLEET_MANAGER_CONTAINER    Default: fleet-manager
  FLEET_MANAGER_NETWORK      Default: forge-fleet
  FLEET_MANAGER_PORT         Default: 18799
  FLEET_MANAGER_STATE_VOLUME Default: fleet-manager-state
  STARTUP_GRACE_SECONDS      Default: 12 (post-start health check)

Secrets:
  The deploy script will reuse existing podman secrets if they exist.
  Only missing secrets will be prompted for.

  The gateway token will be auto-generated if not provided and not in
  the secrets store. The generated token is displayed (first 8 chars)
  for reference.

  To force recreation of all secrets, use --recreate-secrets or set
  RECREATE_SECRETS=1 in the environment.

  Secrets read from the environment or prompted interactively:
    ANTHROPIC_API_KEY     (required, prompted if missing)
    OPENAI_API_KEY        (required, prompted if missing)
    OPENCLAW_GATEWAY_TOKEN (auto-generated if not provided)
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

secret_exists() {
  local secret_name="$1"
  podman secret inspect "${secret_name}" >/dev/null 2>&1
}

generate_token() {
  # Generate a secure random token (32 bytes = 64 hex chars)
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    head -c 32 /dev/urandom | xxd -p | tr -d '\n'
  fi
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
  local secrets_needed=()
  local secrets_exist=()

  # Check which secrets already exist
  if secret_exists anthropic-api-key; then
    secrets_exist+=("anthropic-api-key")
  else
    secrets_needed+=("anthropic-api-key")
  fi

  if secret_exists openai-api-key; then
    secrets_exist+=("openai-api-key")
  else
    secrets_needed+=("openai-api-key")
  fi

  if secret_exists gateway-token; then
    secrets_exist+=("gateway-token")
  else
    secrets_needed+=("gateway-token")
  fi

  # Report existing secrets
  if [[ ${#secrets_exist[@]} -gt 0 ]]; then
    ok "Using existing secrets: ${secrets_exist[*]}"
  fi

  # If all secrets exist, we're done
  if [[ ${#secrets_needed[@]} -eq 0 ]]; then
    ok "All secrets already exist"
    return 0
  fi

  log "Missing secrets: ${secrets_needed[*]}"

  # Prompt and create only missing secrets
  for secret in "${secrets_needed[@]}"; do
    case "${secret}" in
      anthropic-api-key)
        prompt_secret ANTHROPIC_API_KEY "Anthropic API key"
        secret_upsert anthropic-api-key "${ANTHROPIC_API_KEY}"
        ;;
      openai-api-key)
        prompt_secret OPENAI_API_KEY "OpenAI API key"
        secret_upsert openai-api-key "${OPENAI_API_KEY}"
        ;;
      gateway-token)
        if [[ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
          # Use provided token
          :
        else
          # Generate a new token if not provided
          log "Generating new gateway token"
          OPENCLAW_GATEWAY_TOKEN="$(generate_token)"
          ok "Generated gateway token (first 8 chars): ${OPENCLAW_GATEWAY_TOKEN:0:8}..."
        fi
        secret_upsert gateway-token "${OPENCLAW_GATEWAY_TOKEN}"
        ;;
    esac
  done

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

generate_quadlet() {
  local quadlet_dir="${HOME}/.config/containers/systemd"
  local quadlet_file="${quadlet_dir}/${FLEET_MANAGER_CONTAINER}.container"
  
  mkdir -p "${quadlet_dir}"
  
  log "Generating quadlet: ${quadlet_file}"
  cat > "${quadlet_file}" <<EOF
[Unit]
Description=Forge Fleet Manager
After=network-online.target

[Container]
ContainerName=${FLEET_MANAGER_CONTAINER}
HostName=${FLEET_MANAGER_CONTAINER}
Image=${FLEET_MANAGER_IMAGE}
Network=${FLEET_MANAGER_NETWORK}
PublishPort=127.0.0.1:${FLEET_MANAGER_PORT}:${FLEET_MANAGER_PORT}

Environment=FLEET_REPO_ROOT=${FLEET_MANAGER_REPO_MOUNT}
Environment=FLEET_HOST_REPO_ROOT=${SCRIPT_DIR}
Environment=FLEET_STATE_VOLUME=${FLEET_MANAGER_STATE_VOLUME}
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/host_user_systemd/bus

Volume=${PODMAN_SOCKET}:/run/podman/podman.sock:Z
Volume=${SCRIPT_DIR}:${FLEET_MANAGER_REPO_MOUNT}:ro,Z
Volume=${SCRIPT_DIR}/fleet-manager/containers/fleet-manager/workspace:${FLEET_MANAGER_REPO_MOUNT}/workspace:Z
Volume=${FLEET_MANAGER_STATE_VOLUME}:/home/node/.fleet-manager:Z
Volume=${HOME}/.config/containers/systemd:/host-quadlets:Z
Volume=/run/user/$(id -u)/bus:/run/host_user_systemd/bus:ro

Secret=anthropic-api-key,type=env,target=ANTHROPIC_API_KEY
Secret=openai-api-key,type=env,target=OPENAI_API_KEY
Secret=gateway-token,type=env,target=GATEWAY_AUTH_TOKEN

[Service]
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

  ok "Generated quadlet: ${quadlet_file}"
}

start_fleet_manager() {
  generate_quadlet
  
  log "Reloading systemd user units"
  systemctl --user daemon-reload
  
  log "Starting fleet-manager service"
  systemctl --user start "${FLEET_MANAGER_CONTAINER}.service"
  
  ok "Fleet Manager service started"
}

verify_startup() {
  log "Waiting ${STARTUP_GRACE_SECONDS}s for startup health check"
  sleep "${STARTUP_GRACE_SECONDS}"

  local service_status container_status
  service_status="$(systemctl --user is-active "${FLEET_MANAGER_CONTAINER}.service" 2>/dev/null || true)"
  container_status="$(podman inspect --format '{{.State.Status}}' "${FLEET_MANAGER_CONTAINER}" 2>/dev/null || true)"

  if [[ "${service_status}" != "active" ]] || [[ "${container_status}" != "running" ]]; then
    warn "Fleet Manager failed startup check (service: ${service_status:-unknown}, container: ${container_status:-unknown})"
    echo "--- systemd service status ---"
    systemctl --user status "${FLEET_MANAGER_CONTAINER}.service" --no-pager || true
    echo "--- container logs ---"
    podman logs --tail 80 "${FLEET_MANAGER_CONTAINER}" 2>&1 || true
    fail "Fleet Manager is not running after startup grace period"
  fi

  ok "Startup health check passed"
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

recreate_all_secrets() {
  log "Removing existing secrets for recreation"
  for secret in anthropic-api-key openai-api-key gateway-token; do
    if secret_exists "${secret}"; then
      podman secret rm "${secret}" >/dev/null 2>&1 || true
    fi
  done

  prompt_secret ANTHROPIC_API_KEY "Anthropic API key"
  prompt_secret OPENAI_API_KEY "OpenAI API key"

  # Generate gateway token if not provided
  if [[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
    log "Generating new gateway token"
    OPENCLAW_GATEWAY_TOKEN="$(generate_token)"
    ok "Generated gateway token (first 8 chars): ${OPENCLAW_GATEWAY_TOKEN:0:8}..."
  fi

  secret_upsert anthropic-api-key "${ANTHROPIC_API_KEY}"
  secret_upsert openai-api-key "${OPENAI_API_KEY}"
  secret_upsert gateway-token "${OPENCLAW_GATEWAY_TOKEN}"
  ok "All secrets recreated"
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
    --recreate-secrets)
      require_cmd podman
      recreate_all_secrets
      exit 0
      ;;
    "")
      ;;
    *)
      fail "Unknown option: ${1}"
      ;;
  esac

  # Check if RECREATE_SECRETS is set
  if [[ "${RECREATE_SECRETS:-}" == "1" ]]; then
    FORCE_RECREATE_SECRETS=1
  fi

  check_prereqs
  remove_existing_container

  if [[ "${FORCE_RECREATE_SECRETS:-}" == "1" ]]; then
    recreate_all_secrets
  else
    create_secrets
  fi

  build_images
  ensure_network
  start_fleet_manager
  verify_startup

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
