#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

STATE_DIR="${FLEET_STATE_DIR:-$HOME/.fleet-manager}"
STATE_FILE="${FLEET_STATE_FILE:-${STATE_DIR}/instances.json}"
SCHEMA_FILE="${SKILL_DIR}/schemas/instances.json"
ARCHIVE_DIR="${STATE_DIR}/archives"

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
  teardown.sh [--archive] <name>

Options:
  --archive    Snapshot workspace to ~/.fleet-manager/archives before teardown
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

load_instance() {
  local name="$1"
  INSTANCE_JSON="$(jq -c --arg name "$name" '.instances[$name] // empty' "${STATE_FILE}")"
  [[ -n "${INSTANCE_JSON}" ]] || fail "Instance not found in state: ${name}"
  INSTANCE_USER="$(jq -r '.user' <<<"${INSTANCE_JSON}")"
  INSTANCE_WORKSPACE="$(jq -r '.workspace' <<<"${INSTANCE_JSON}")"
}

archive_workspace() {
  local name="$1"
  local workspace="$2"
  local archive_path="${ARCHIVE_DIR}/${name}-$(date +%Y%m%dT%H%M%S).tar.gz"

  if [[ -d "$workspace" ]]; then
    log "Archiving ${workspace}" >&2
    sudo tar -C "$(dirname "$workspace")" -czf "$archive_path" "$(basename "$workspace")"
    echo "$archive_path"
  else
    warn "Workspace missing, skipping archive: ${workspace}" >&2
  fi
}

remove_unit_and_user() {
  local user="$1"
  local uid unit_dir
  uid="$(id -u "$user" 2>/dev/null || true)"
  unit_dir="/home/${user}/.config/systemd/user"

  if [[ -n "$uid" ]]; then
    sudo -u "$user" XDG_RUNTIME_DIR="/run/user/${uid}" systemctl --user disable --now openclaw.service >/dev/null 2>&1 || warn "Could not stop/disable openclaw.service for ${user}"
    sudo -u "$user" XDG_RUNTIME_DIR="/run/user/${uid}" systemctl --user daemon-reload >/dev/null 2>&1 || true
  fi

  if [[ -f "${unit_dir}/openclaw.service" ]]; then
    sudo rm -f "${unit_dir}/openclaw.service"
  fi

  if id "$user" >/dev/null 2>&1; then
    log "Removing Unix user ${user}"
    sudo userdel -r "$user" >/dev/null 2>&1 || sudo userdel "$user"
  fi
}

update_state_archived() {
  local name="$1"
  local now="$2"
  local tmp
  tmp="$(mktemp)"
  jq \
    --arg name "$name" \
    --arg now "$now" \
    '.instances[$name].status = "archived" | .instances[$name].lastActivity = $now' \
    "${STATE_FILE}" > "${tmp}"
  mv "${tmp}" "${STATE_FILE}"
}

remove_state_entry() {
  local name="$1"
  local tmp
  tmp="$(mktemp)"
  jq --arg name "$name" 'del(.instances[$name])' "${STATE_FILE}" > "${tmp}"
  mv "${tmp}" "${STATE_FILE}"
}

main() {
  local archive=0
  case "${1:-}" in
    --help|-h) usage; exit 0 ;;
    --archive) archive=1; shift ;;
  esac

  local name="${1:-}"
  [[ -n "$name" ]] || { usage; exit 1; }

  require_cmd jq
  require_cmd sudo
  require_cmd systemctl
  require_cmd tar

  ensure_state_file
  load_instance "$name"

  local now archive_path
  now="$(date -Iseconds)"

  if (( archive )); then
    archive_path="$(archive_workspace "$name" "${INSTANCE_WORKSPACE}")"
    [[ -n "${archive_path}" ]] && ok "Archive written to ${archive_path}"
  fi

  remove_unit_and_user "${INSTANCE_USER}"

  if (( archive )); then
    update_state_archived "$name" "$now"
    ok "Archived ${name}"
  else
    remove_state_entry "$name"
    ok "Destroyed ${name}"
  fi
}

main "$@"
