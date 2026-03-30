#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="${FLEET_REPO_ROOT:-$(cd "${SKILL_DIR}/../.." && pwd)}"
HOST_REPO_ROOT="${FLEET_HOST_REPO_ROOT:-${REPO_ROOT}}"

STATE_DIR="${FLEET_STATE_DIR:-$HOME/.fleet-manager}"
STATE_FILE="${FLEET_STATE_FILE:-${STATE_DIR}/instances.json}"
SCHEMA_FILE="${SKILL_DIR}/schemas/instances.json"
TEMPLATE_FILE="${SKILL_DIR}/templates/forge-instance.json5"
INSTANCE_DIR="${STATE_DIR}/instances"
ARCHIVE_DIR="${STATE_DIR}/archives"

# For sibling container mounts via host podman socket
STATE_VOLUME="${FLEET_STATE_VOLUME:-fleet-manager-state}"
# Mount path inside forge instances (using node user)
STATE_MOUNT_PATH="${FLEET_STATE_MOUNT_PATH:-/home/node/.fleet-manager}"

# Host quadlet directory (mounted into fleet-manager container)
HOST_QUADLET_DIR="${FLEET_HOST_QUADLET_DIR:-/host-quadlets}"

# Use host-spawn to run systemctl on the host
HOSTCTL="host-spawn systemctl --user"

PORT_START="${FLEET_PORT_START:-18800}"
PORT_END="${FLEET_PORT_END:-18899}"
PODMAN_NETWORK="${FLEET_PODMAN_NETWORK:-forge-fleet}"
CONTAINER_PREFIX="${FLEET_CONTAINER_PREFIX:-forge-}"
WORKSPACE_VOLUME_PREFIX="${FLEET_WORKSPACE_VOLUME_PREFIX:-forge-workspace-}"
DATA_VOLUME_PREFIX="${FLEET_DATA_VOLUME_PREFIX:-forge-data-}"
FORGE_INSTANCE_IMAGE="${FORGE_INSTANCE_IMAGE:-localhost/openclaw-forge:latest}"
SECRET_ANTHROPIC="${FLEET_SECRET_ANTHROPIC:-anthropic-api-key}"
SECRET_OPENAI="${FLEET_SECRET_OPENAI:-openai-api-key}"
SECRET_GATEWAY="${FLEET_SECRET_GATEWAY:-gateway-token}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[fleet]${NC} $*"; }
ok()   { echo -e "${GREEN}[  ok ]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
fail() { echo -e "${RED}[fail]${NC} $*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage:
  provision.sh <name>

Environment:
  FLEET_STATE_DIR                 Default: ~/.fleet-manager
  FLEET_STATE_FILE                Override state file path
  FLEET_PORT_START                Default: 18800
  FLEET_PORT_END                  Default: 18899
  FLEET_PODMAN_NETWORK            Default: forge-fleet
  FLEET_CONTAINER_PREFIX          Default: forge-
  FLEET_WORKSPACE_VOLUME_PREFIX   Default: forge-workspace-
  FLEET_DATA_VOLUME_PREFIX        Default: forge-data-
  FORGE_INSTANCE_IMAGE            Default: localhost/openclaw-forge:latest

Required podman secrets:
  anthropic-api-key
  openai-api-key
  gateway-token
USAGE
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

ensure_state_file() {
  mkdir -p "${STATE_DIR}" "${INSTANCE_DIR}" "${ARCHIVE_DIR}"
  if [[ ! -f "${STATE_FILE}" ]]; then
    cp "${SCHEMA_FILE}" "${STATE_FILE}"
  fi
}

valid_name() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,31}$ ]]
}

escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[&|]/\\&/g'
}

state_has_name() {
  jq -e --arg name "$1" '.instances[$name] != null' "${STATE_FILE}" >/dev/null
}

port_in_use() {
  local port="$1"
  ss -ltn "( sport = :${port} )" | tail -n +2 | grep -q .
}

next_available_port() {
  local port
  port="$(jq -r '.nextPort' "${STATE_FILE}")"
  if [[ ! "$port" =~ ^[0-9]+$ ]]; then
    port="${PORT_START}"
  fi

  while (( port <= PORT_END )); do
    if ! jq -e --argjson port "$port" '.instances | to_entries[]? | select(.value.port == $port)' "${STATE_FILE}" >/dev/null && ! port_in_use "$port"; then
      printf '%s\n' "$port"
      return 0
    fi
    port=$((port + 1))
  done

  fail "No free ports left in range ${PORT_START}-${PORT_END}"
}

ensure_network() {
  if ! podman network exists "${PODMAN_NETWORK}"; then
    log "Creating podman network ${PODMAN_NETWORK}"
    podman network create "${PODMAN_NETWORK}" >/dev/null
  fi
}

ensure_secret() {
  local secret_name="$1"
  podman secret inspect "${secret_name}" >/dev/null 2>&1 || fail "Missing podman secret: ${secret_name}"
}

ensure_image() {
  podman image inspect "${FORGE_INSTANCE_IMAGE}" >/dev/null 2>&1 || fail "Missing image ${FORGE_INSTANCE_IMAGE}. Build it with ./deploy.sh first."
}

render_config() {
  local destination="$1"
  local instance_name="$2"
  local port="$3"

  sed \
    -e "s|\${INSTANCE_NAME}|$(escape_sed_replacement "$instance_name")|g" \
    -e "s|\${PORT}|$(escape_sed_replacement "$port")|g" \
    "${TEMPLATE_FILE}" > "${destination}"
}

seed_workspace_volume() {
  local volume_name="$1"
  # Use HOST_REPO_ROOT for podman volume mounts (host paths required)
  podman run --rm \
    -v "${volume_name}:/dest:Z" \
    -v "${HOST_REPO_ROOT}/workspace:/src:ro,Z" \
    --entrypoint /bin/bash \
    "${FORGE_INSTANCE_IMAGE}" \
    -lc 'shopt -s dotglob nullglob; cp -a /src/. /dest/'
}

record_instance() {
  local name="$1"
  local container_name="$2"
  local port="$3"
  local config_path="$4"
  local workspace_volume="$5"
  local data_volume="$6"
  local now="$7"
  local next_port="$8"
  local tmp

  tmp="$(mktemp)"
  jq \
    --arg name "$name" \
    --arg container "$container_name" \
    --arg image "${FORGE_INSTANCE_IMAGE}" \
    --arg config_path "$config_path" \
    --arg workspace_volume "$workspace_volume" \
    --arg data_volume "$data_volume" \
    --arg status "running" \
    --arg created_at "$now" \
    --arg last_activity "$now" \
    --argjson port "$port" \
    --argjson next_port "$next_port" \
    '.instances[$name] = {
      container: $container,
      image: $image,
      port: $port,
      configPath: $config_path,
      workspaceVolume: $workspace_volume,
      dataVolume: $data_volume,
      status: $status,
      createdAt: $created_at,
      lastActivity: $last_activity
    } | .nextPort = $next_port' \
    "${STATE_FILE}" > "${tmp}"
  mv "${tmp}" "${STATE_FILE}"
}

main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
  fi

  local name="${1:-}"
  [[ -n "$name" ]] || { usage; exit 1; }
  valid_name "$name" || fail "Invalid name: ${name}"

  require_cmd jq
  require_cmd podman
  require_cmd ss
  [[ -f "${TEMPLATE_FILE}" ]] || fail "Template missing: ${TEMPLATE_FILE}"

  ensure_state_file
  state_has_name "$name" && fail "Instance already exists in state: ${name}"
  ensure_image
  ensure_network
  ensure_secret "${SECRET_ANTHROPIC}"
  ensure_secret "${SECRET_OPENAI}"
  ensure_secret "${SECRET_GATEWAY}"

  local port now next_port container_name workspace_volume data_volume config_dir config_path
  port="$(next_available_port)"
  now="$(date -Iseconds)"
  next_port=$((port + 1))
  container_name="${CONTAINER_PREFIX}${name}"
  workspace_volume="${WORKSPACE_VOLUME_PREFIX}${name}"
  data_volume="${DATA_VOLUME_PREFIX}${name}"
  config_dir="${INSTANCE_DIR}/${name}"
  config_path="${config_dir}/openclaw.json5"

  podman container exists "${container_name}" && fail "Container already exists: ${container_name}"

  mkdir -p "${config_dir}"
  render_config "${config_path}" "$name" "$port"

  log "Creating persistent volumes"
  podman volume create "${workspace_volume}" >/dev/null
  podman volume create "${data_volume}" >/dev/null

  log "Seeding workspace volume ${workspace_volume}"
  seed_workspace_volume "${workspace_volume}"

  # Config path inside the state volume (relative to mount point)
  local config_subpath="instances/${name}/openclaw.json5"
  local quadlet_file="${HOST_QUADLET_DIR}/${container_name}.container"
  local service_name="${container_name}.service"

  log "Generating quadlet: ${quadlet_file}"
  cat > "${quadlet_file}" <<EOF
[Unit]
Description=Forge Instance: ${name}
After=network-online.target

[Container]
ContainerName=${container_name}
HostName=${container_name}
Image=${FORGE_INSTANCE_IMAGE}
Network=${PODMAN_NETWORK}
PublishPort=127.0.0.1:${port}:${port}

Environment=OPENCLAW_CONFIG=${STATE_MOUNT_PATH}/${config_subpath}

Volume=${workspace_volume}:/home/node/.openclaw/workspace:Z
Volume=${data_volume}:/home/node/.local/share/openclaw:Z
Volume=${STATE_VOLUME}:${STATE_MOUNT_PATH}:Z

Secret=${SECRET_ANTHROPIC},type=env,target=ANTHROPIC_API_KEY
Secret=${SECRET_OPENAI},type=env,target=OPENAI_API_KEY
Secret=${SECRET_GATEWAY},type=env,target=GATEWAY_AUTH_TOKEN

[Service]
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

  log "Reloading systemd user units"
  ${HOSTCTL} daemon-reload

  log "Starting service ${service_name}"
  ${HOSTCTL} start "${service_name}"

  # Verify startup
  sleep 2
  local status
  status="$(${HOSTCTL} is-active "${service_name}" 2>/dev/null || true)"
  if [[ "${status}" != "active" ]]; then
    warn "Service ${service_name} failed to start (status: ${status})"
    echo "--- systemd service status ---"
    ${HOSTCTL} status "${service_name}" --no-pager || true
    echo "--- container logs ---"
    podman logs --tail 50 "${container_name}" 2>&1 || true
    fail "Forge instance ${name} failed to start"
  fi

  record_instance "$name" "$container_name" "$port" "$config_path" "$workspace_volume" "$data_volume" "$now" "$next_port"

  ok "Provisioned ${name}"
  echo "container=${container_name}"
  echo "port=${port}"
  echo "workspace_volume=${workspace_volume}"
  echo "data_volume=${data_volume}"
  echo "config=${config_path}"
  echo "state=${STATE_FILE}"
}

main "$@"
