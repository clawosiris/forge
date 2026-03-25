#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

STATE_DIR="${FLEET_STATE_DIR:-$HOME/.fleet-manager}"
STATE_FILE="${FLEET_STATE_FILE:-${STATE_DIR}/instances.json}"
SCHEMA_FILE="${SKILL_DIR}/schemas/instances.json"

fail() { echo "[fail] $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

ensure_state_file() {
  mkdir -p "${STATE_DIR}"
  if [[ ! -f "${STATE_FILE}" ]]; then
    cp "${SCHEMA_FILE}" "${STATE_FILE}"
  fi
}

container_runtime_state() {
  local container_name="$1"
  if ! podman container exists "${container_name}"; then
    printf 'missing'
    return 0
  fi

  podman inspect --format '{{.State.Status}}' "${container_name}" 2>/dev/null || printf 'unknown'
}

container_port_state() {
  local container_name="$1"
  if ! podman container exists "${container_name}"; then
    printf 'missing'
    return 0
  fi

  if podman port "${container_name}" >/dev/null 2>&1; then
    printf 'published'
  else
    printf 'unpublished'
  fi
}

container_started_at() {
  local container_name="$1"
  if ! podman container exists "${container_name}"; then
    printf 'missing'
    return 0
  fi

  podman inspect --format '{{.State.StartedAt}}' "${container_name}" 2>/dev/null || printf 'unknown'
}

print_instance() {
  local name="$1"
  local instance_json="$2"
  local container_name port status runtime_state port_state started_at

  container_name="$(jq -r '.container' <<<"${instance_json}")"
  port="$(jq -r '.port' <<<"${instance_json}")"
  status="$(jq -r '.status' <<<"${instance_json}")"
  runtime_state="$(container_runtime_state "$container_name")"
  port_state="$(container_port_state "$container_name")"
  started_at="$(container_started_at "$container_name")"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$name" \
    "$status" \
    "$runtime_state" \
    "$port_state" \
    "$port" \
    "$container_name" \
    "$started_at"
}

main() {
  local name="${1:-}"

  require_cmd jq
  require_cmd podman
  ensure_state_file

  echo -e "NAME\tSTATUS\tRUNTIME\tPORTS\tPORT\tCONTAINER\tSTARTED_AT"

  if [[ -n "$name" ]]; then
    local instance_json
    instance_json="$(jq -c --arg name "$name" '.instances[$name] // empty' "${STATE_FILE}")"
    [[ -n "$instance_json" ]] || fail "Instance not found: ${name}"
    print_instance "$name" "$instance_json"
    exit 0
  fi

  jq -r '.instances | to_entries[]? | [.key, (.value | @json)] | @tsv' "${STATE_FILE}" |
    while IFS=$'\t' read -r instance_name instance_json; do
      print_instance "$instance_name" "$instance_json"
    done
}

main "$@"
