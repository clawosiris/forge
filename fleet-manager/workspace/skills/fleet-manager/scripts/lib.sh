#!/usr/bin/env bash
set -euo pipefail

STATE_ROOT="${OPENCLAW_HOME:-/home/openclaw/.openclaw}/fleet"
STATE_FILE="${FLEET_STATE_FILE:-${STATE_ROOT}/instances.json}"
ARCHIVE_DIR="${STATE_ROOT}/archives"
PORT_START="${FLEET_PORT_START:-18800}"
PORT_END="${FLEET_PORT_END:-18899}"
NETWORK_NAME="${FLEET_NETWORK_NAME:-forge-fleet}"
INSTANCE_IMAGE="${FORGE_INSTANCE_IMAGE:-openclaw-forge:latest}"
HOST_STATE_DIR="${FLEET_MANAGER_HOST_STATE_DIR:-}"

ensure_state() {
  mkdir -p "${STATE_ROOT}" "${ARCHIVE_DIR}"

  if [[ ! -f "${STATE_FILE}" ]]; then
    jq -n \
      --argjson start "${PORT_START}" \
      --argjson end "${PORT_END}" \
      '{
        instances: {},
        nextPort: $start,
        portRange: { start: $start, end: $end }
      }' > "${STATE_FILE}"
  fi
}

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required binary: $1" >&2
    exit 1
  }
}

validate_name() {
  local name="$1"
  [[ "${name}" =~ ^[a-z0-9-]+$ ]] || {
    echo "invalid instance name: ${name}" >&2
    exit 1
  }
}

instance_exists() {
  local name="$1"
  jq -e --arg name "${name}" '.instances[$name] != null' "${STATE_FILE}" >/dev/null
}

instance_field() {
  local name="$1"
  local field="$2"
  jq -r --arg name "${name}" --arg field "${field}" '.instances[$name][$field]' "${STATE_FILE}"
}

allocate_port() {
  local port
  port="$(jq -r '.nextPort' "${STATE_FILE}")"

  if [[ "${port}" -gt "${PORT_END}" ]]; then
    echo "port range exhausted (${PORT_START}-${PORT_END})" >&2
    exit 1
  fi

  while jq -e --argjson port "${port}" '.instances | to_entries[]? | select(.value.port == $port)' "${STATE_FILE}" >/dev/null; do
    port=$((port + 1))
    if [[ "${port}" -gt "${PORT_END}" ]]; then
      echo "port range exhausted (${PORT_START}-${PORT_END})" >&2
      exit 1
    fi
  done

  echo "${port}"
}

ensure_network() {
  if ! podman network exists "${NETWORK_NAME}"; then
    podman network create "${NETWORK_NAME}" >/dev/null
  fi
}

save_instance() {
  local name="$1"
  local payload="$2"
  local tmp
  tmp="$(mktemp)"
  jq --arg name "${name}" --argjson payload "${payload}" '.instances[$name] = $payload' "${STATE_FILE}" > "${tmp}"
  mv "${tmp}" "${STATE_FILE}"
}

remove_instance() {
  local name="$1"
  local tmp
  tmp="$(mktemp)"
  jq --arg name "${name}" 'del(.instances[$name])' "${STATE_FILE}" > "${tmp}"
  mv "${tmp}" "${STATE_FILE}"
}

set_next_port() {
  local port="$1"
  local tmp
  tmp="$(mktemp)"
  jq --argjson port "${port}" '.nextPort = $port' "${STATE_FILE}" > "${tmp}"
  mv "${tmp}" "${STATE_FILE}"
}

update_instance_status() {
  local name="$1"
  local status="$2"
  local last_activity="$3"
  local tmp
  tmp="$(mktemp)"
  jq \
    --arg name "${name}" \
    --arg status "${status}" \
    --arg lastActivity "${last_activity}" \
    '.instances[$name].status = $status | .instances[$name].lastActivity = $lastActivity' \
    "${STATE_FILE}" > "${tmp}"
  mv "${tmp}" "${STATE_FILE}"
}

container_exists() {
  local container="$1"
  podman container exists "${container}"
}

container_state() {
  local container="$1"
  podman inspect --format '{{.State.Status}}' "${container}" 2>/dev/null || echo "missing"
}

last_log_timestamp() {
  local container="$1"
  podman logs --timestamps --tail 200 "${container}" 2>/dev/null | tail -n 1 | awk '{print $1}'
}

port_open() {
  local host="$1"
  local port="$2"
  timeout 3 bash -lc ">/dev/tcp/${host}/${port}" >/dev/null 2>&1
}

require_archive_host_dir() {
  if [[ -z "${HOST_STATE_DIR}" ]]; then
    echo "FLEET_MANAGER_HOST_STATE_DIR must be set for archive operations" >&2
    exit 1
  fi
}
