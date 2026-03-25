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

is_port_listening() {
  local port="$1"
  if ss -ltn "( sport = :${port} )" | tail -n +2 | grep -q .; then
    printf 'listening'
  else
    printf 'closed'
  fi
}

last_activity_for_workspace() {
  local workspace="$1"
  if [[ -d "$workspace" ]]; then
    find "$workspace" -type f -printf '%TY-%Tm-%TdT%TH:%TM:%TS\n' 2>/dev/null | sort -r | head -n 1
  fi
}

systemd_state_for_user() {
  local user="$1"
  local uid
  uid="$(id -u "$user" 2>/dev/null || true)"
  if [[ -z "$uid" ]]; then
    printf 'missing-user'
    return 0
  fi

  if sudo -u "$user" XDG_RUNTIME_DIR="/run/user/${uid}" systemctl --user is-active openclaw.service >/dev/null 2>&1; then
    printf 'active'
  else
    printf 'inactive'
  fi
}

print_instance() {
  local name="$1"
  local instance_json="$2"
  local user port workspace status systemd_state port_state last_activity

  user="$(jq -r '.user' <<<"${instance_json}")"
  port="$(jq -r '.port' <<<"${instance_json}")"
  workspace="$(jq -r '.workspace' <<<"${instance_json}")"
  status="$(jq -r '.status' <<<"${instance_json}")"
  systemd_state="$(systemd_state_for_user "$user")"
  port_state="$(is_port_listening "$port")"
  last_activity="$(last_activity_for_workspace "$workspace")"
  if [[ -z "$last_activity" ]]; then
    last_activity="$(jq -r '.lastActivity // "unknown"' <<<"${instance_json}")"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$name" \
    "$status" \
    "$systemd_state" \
    "$port_state" \
    "$port" \
    "$user" \
    "$last_activity"
}

main() {
  local name="${1:-}"

  require_cmd jq
  require_cmd ss
  require_cmd sudo
  require_cmd systemctl
  ensure_state_file

  echo -e "NAME\tSTATUS\tUNIT\tLISTEN\tPORT\tUSER\tLAST_ACTIVITY"

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
