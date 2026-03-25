#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_bin jq
require_bin podman

ensure_state

TARGET="${1:-}"

instance_status_json() {
  local name="$1"
  local container port state last_log state_status port_status volume model channel created_at stored_activity recorded_status

  if ! instance_exists "${name}"; then
    echo "unknown instance: ${name}" >&2
    exit 1
  fi

  container="$(instance_field "${name}" "container")"
  port="$(instance_field "${name}" "port")"
  volume="$(instance_field "${name}" "volume")"
  model="$(instance_field "${name}" "model")"
  channel="$(instance_field "${name}" "channel")"
  created_at="$(instance_field "${name}" "createdAt")"
  stored_activity="$(instance_field "${name}" "lastActivity")"
  recorded_status="$(instance_field "${name}" "status")"

  state="$(container_state "${container}")"
  last_log="$(last_log_timestamp "${container}")"

  if [[ "${recorded_status}" == "archived" && "${state}" == "missing" ]]; then
    state_status="archived"
  elif [[ "${state}" == "running" ]]; then
    state_status="running"
  elif [[ "${state}" == "exited" ]]; then
    state_status="stopped"
  else
    state_status="${state}"
  fi

  if [[ "${state}" == "running" ]] && port_open "${container}" 18789; then
    port_status="open"
  else
    port_status="closed"
  fi

  jq -n \
    --arg name "${name}" \
    --arg container "${container}" \
    --arg volume "${volume}" \
    --arg model "${model}" \
    --arg channel "${channel}" \
    --arg status "${state_status}" \
    --arg portHealth "${port_status}" \
    --arg createdAt "${created_at}" \
    --arg lastActivity "${last_log:-$stored_activity}" \
    --arg lastLogTimestamp "${last_log}" \
    --argjson port "${port}" \
    '{
      name: $name,
      container: $container,
      volume: $volume,
      port: $port,
      status: $status,
      portHealth: $portHealth,
      model: $model,
      channel: $channel,
      createdAt: $createdAt,
      lastActivity: $lastActivity,
      lastLogTimestamp: $lastLogTimestamp
    }'
}

if [[ -n "${TARGET}" ]]; then
  instance_status_json "${TARGET}"
  exit 0
fi

jq -r '.instances | keys[]?' "${STATE_FILE}" | while read -r name; do
  instance_status_json "${name}"
done | jq -s '{
  instances: .,
  summary: {
    total: length,
    running: (map(select(.status == "running")) | length),
    stopped: (map(select(.status == "stopped")) | length)
  }
}'
