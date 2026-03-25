#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SKILL_DIR}/../.." && pwd)"

STATE_DIR="${FLEET_STATE_DIR:-$HOME/.fleet-manager}"
STATE_FILE="${FLEET_STATE_FILE:-${STATE_DIR}/instances.json}"
SCHEMA_FILE="${SKILL_DIR}/schemas/instances.json"
TEMPLATE_FILE="${SKILL_DIR}/templates/forge-instance.json5"
ARCHIVE_DIR="${STATE_DIR}/archives"

PORT_START="${FLEET_PORT_START:-18800}"
PORT_END="${FLEET_PORT_END:-18899}"
USER_PREFIX="${FLEET_USER_PREFIX:-forge-}"
WORKSPACE_BASE="${FLEET_WORKSPACE_BASE:-/home}"
OPENCLAW_BIN="${OPENCLAW_BIN:-$(command -v openclaw || true)}"

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
  cat <<'EOF'
Usage:
  provision.sh <name>

Environment:
  FLEET_STATE_DIR         Default: ~/.fleet-manager
  FLEET_STATE_FILE        Override state file path
  FLEET_PORT_START        Default: 18800
  FLEET_PORT_END          Default: 18899
  FLEET_USER_PREFIX       Default: forge-
  FLEET_WORKSPACE_BASE    Default: /home
  OPENCLAW_BIN            Override openclaw binary path

Optional secret inputs copied into the instance-local secrets store:
  OPENCLAW_GATEWAY_TOKEN
  ANTHROPIC_API_KEY
  OPENAI_API_KEY
  OPENCLAW_SIGNAL_ALLOW_FROM
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

ensure_state_file() {
  mkdir -p "${STATE_DIR}" "${ARCHIVE_DIR}"
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

write_secrets_file() {
  local secrets_file="$1"
  local gateway_token

  gateway_token="${OPENCLAW_GATEWAY_TOKEN:-}"
  if [[ -z "$gateway_token" ]]; then
    gateway_token="$(openssl rand -hex 32 2>/dev/null || od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"
  fi

  cat >"${secrets_file}" <<EOF
{
  "GATEWAY_AUTH_TOKEN": "${gateway_token}"$( [[ -n "${ANTHROPIC_API_KEY:-}" ]] && printf ',\n  "ANTHROPIC_API_KEY": %s' "$(jq -Rs . <<<"${ANTHROPIC_API_KEY}")" )$( [[ -n "${OPENAI_API_KEY:-}" ]] && printf ',\n  "OPENAI_API_KEY": %s' "$(jq -Rs . <<<"${OPENAI_API_KEY}")" )$( [[ -n "${OPENCLAW_SIGNAL_ALLOW_FROM:-}" ]] && printf ',\n  "SIGNAL_ALLOW_FROM": %s' "$(jq -Rs . <<<"${OPENCLAW_SIGNAL_ALLOW_FROM}")" )
}
EOF
}

render_config() {
  local destination="$1"
  local instance_name="$2"
  local port="$3"
  local workspace="$4"
  local user="$5"

  sed \
    -e "s|\${INSTANCE_NAME}|$(escape_sed_replacement "$instance_name")|g" \
    -e "s|\${PORT}|$(escape_sed_replacement "$port")|g" \
    -e "s|\${WORKSPACE}|$(escape_sed_replacement "$workspace")|g" \
    -e "s|\${USER}|$(escape_sed_replacement "$user")|g" \
    "${TEMPLATE_FILE}" > "${destination}"
}

install_unit() {
  local destination="$1"

  cat >"${destination}" <<EOF
[Unit]
Description=Forge instance
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=%h/.openclaw
Environment=HOME=%h
Environment=OPENCLAW_STATE_DIR=%h/.openclaw
ExecStart=${OPENCLAW_BIN} gateway start
ExecStop=${OPENCLAW_BIN} gateway stop
TimeoutStartSec=120
TimeoutStopSec=120

[Install]
WantedBy=default.target
EOF
}

record_instance() {
  local name="$1"
  local user="$2"
  local port="$3"
  local workspace="$4"
  local now="$5"
  local next_port="$6"
  local tmp

  tmp="$(mktemp)"
  jq \
    --arg name "$name" \
    --arg user "$user" \
    --arg workspace "$workspace" \
    --arg status "running" \
    --arg created_at "$now" \
    --arg last_activity "$now" \
    --argjson port "$port" \
    --argjson next_port "$next_port" \
    '.instances[$name] = {
      user: $user,
      port: $port,
      workspace: $workspace,
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
  require_cmd ss
  require_cmd sudo
  require_cmd systemctl
  require_cmd loginctl
  [[ -n "${OPENCLAW_BIN}" ]] || fail "openclaw binary not found"
  [[ -f "${TEMPLATE_FILE}" ]] || fail "Template missing: ${TEMPLATE_FILE}"

  ensure_state_file
  state_has_name "$name" && fail "Instance already exists in state: ${name}"

  local port user home_dir openclaw_dir workspace unit_dir tmp_dir uid now next_port
  user="${USER_PREFIX}${name}"
  home_dir="${WORKSPACE_BASE}/${user}"
  openclaw_dir="${home_dir}/.openclaw"
  workspace="${openclaw_dir}/workspace"
  unit_dir="${home_dir}/.config/systemd/user"
  tmp_dir="$(mktemp -d)"

  if id "$user" >/dev/null 2>&1; then
    fail "Unix user already exists: ${user}"
  fi

  port="$(next_available_port)"
  now="$(date -Iseconds)"
  next_port=$((port + 1))

  log "Creating Unix user ${user}"
  sudo useradd --create-home --shell /bin/bash "$user"
  sudo loginctl enable-linger "$user" >/dev/null 2>&1 || warn "Could not enable linger for ${user}"

  log "Preparing instance directories"
  sudo install -d -o "$user" -g "$user" "${openclaw_dir}" "${workspace}" "${unit_dir}"
  sudo cp -a "${REPO_ROOT}/workspace/." "${workspace}/"
  sudo chown -R "$user:$user" "${workspace}"

  render_config "${tmp_dir}/openclaw.json" "$name" "$port" "$workspace" "$user"
  write_secrets_file "${tmp_dir}/secrets.json"
  install_unit "${tmp_dir}/openclaw.service"

  sudo install -o "$user" -g "$user" -m 0644 "${tmp_dir}/openclaw.json" "${openclaw_dir}/openclaw.json"
  sudo install -o "$user" -g "$user" -m 0600 "${tmp_dir}/secrets.json" "${openclaw_dir}/secrets.json"
  sudo install -o "$user" -g "$user" -m 0644 "${tmp_dir}/openclaw.service" "${unit_dir}/openclaw.service"

  uid="$(id -u "$user")"
  log "Starting systemd user unit for ${name}"
  sudo -u "$user" XDG_RUNTIME_DIR="/run/user/${uid}" systemctl --user daemon-reload
  sudo -u "$user" XDG_RUNTIME_DIR="/run/user/${uid}" systemctl --user enable --now openclaw.service

  record_instance "$name" "$user" "$port" "$workspace" "$now" "$next_port"

  ok "Provisioned ${name}"
  echo "user=${user}"
  echo "port=${port}"
  echo "workspace=${workspace}"
  echo "state=${STATE_FILE}"
}

main "$@"
