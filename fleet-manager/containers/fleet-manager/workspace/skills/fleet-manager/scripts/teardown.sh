#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

STATE_DIR="${FLEET_STATE_DIR:-$HOME/.fleet-manager}"
STATE_FILE="${FLEET_STATE_FILE:-${STATE_DIR}/instances.json}"
SCHEMA_FILE="${SKILL_DIR}/schemas/instances.json"
ARCHIVE_DIR="${STATE_DIR}/archives"
FORGE_INSTANCE_IMAGE="${FORGE_INSTANCE_IMAGE:-localhost/openclaw-forge:latest}"

# Host quadlet directory (mounted into fleet-manager container)
HOST_QUADLET_DIR="${FLEET_HOST_QUADLET_DIR:-/host-quadlets}"

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
  teardown.sh [--archive] <name>

Options:
  --archive    Snapshot workspace and state volumes before teardown
USAGE
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
  INSTANCE_CONTAINER="$(jq -r '.container' <<<"${INSTANCE_JSON}")"
  INSTANCE_WORKSPACE_VOLUME="$(jq -r '.workspaceVolume' <<<"${INSTANCE_JSON}")"
  INSTANCE_DATA_VOLUME="$(jq -r '.dataVolume' <<<"${INSTANCE_JSON}")"
  INSTANCE_CONFIG_PATH="$(jq -r '.configPath' <<<"${INSTANCE_JSON}")"
}

archive_volume() {
  local volume_name="$1"
  local archive_name="$2"
  local archive_path="${ARCHIVE_DIR}/${archive_name}"

  log "Archiving volume ${volume_name}" >&2
  podman run --rm \
    -v "${volume_name}:/data:Z" \
    -v "${ARCHIVE_DIR}:/archive:Z" \
    --entrypoint /bin/bash \
    "${FORGE_INSTANCE_IMAGE}" \
    -lc "tar -C /data -czf \"/archive/${archive_name}\" ."

  echo "${archive_path}"
}

remove_container() {
  local container_name="$1"
  local service_name="${container_name}.service"
  local quadlet_file="${HOST_QUADLET_DIR}/${container_name}.container"

  # Stop via systemd if service exists
  if systemctl --user is-active "${service_name}" >/dev/null 2>&1; then
    log "Stopping service ${service_name}"
    systemctl --user stop "${service_name}" || warn "Could not stop ${service_name}"
  fi

  # Remove quadlet file
  if [[ -f "${quadlet_file}" ]]; then
    log "Removing quadlet ${quadlet_file}"
    rm -f "${quadlet_file}"
    systemctl --user daemon-reload
  fi

  # Clean up container if it still exists
  if podman container exists "${container_name}"; then
    podman stop -t 30 "${container_name}" >/dev/null 2>&1 || warn "Could not stop ${container_name}"
    podman rm -f "${container_name}" >/dev/null 2>&1 || warn "Could not remove ${container_name}"
  fi
}

remove_volume() {
  local volume_name="$1"
  if podman volume exists "${volume_name}"; then
    podman volume rm "${volume_name}" >/dev/null 2>&1 || warn "Could not remove volume ${volume_name}"
  fi
}

update_state_archived() {
  local name="$1"
  local now="$2"
  local archive_workspace="$3"
  local archive_data="$4"
  local tmp
  tmp="$(mktemp)"
  jq \
    --arg name "$name" \
    --arg now "$now" \
    --arg workspace_archive "$archive_workspace" \
    --arg data_archive "$archive_data" \
    '.instances[$name].status = "archived"
      | .instances[$name].lastActivity = $now
      | .instances[$name].workspaceArchive = $workspace_archive
      | .instances[$name].dataArchive = $data_archive' \
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
  require_cmd podman
  require_cmd tar

  ensure_state_file
  load_instance "$name"

  local now archive_workspace="" archive_data=""
  now="$(date -Iseconds)"

  if (( archive )); then
    archive_workspace="$(archive_volume "${INSTANCE_WORKSPACE_VOLUME}" "${name}-workspace-$(date +%Y%m%dT%H%M%S).tar.gz")"
    archive_data="$(archive_volume "${INSTANCE_DATA_VOLUME}" "${name}-data-$(date +%Y%m%dT%H%M%S).tar.gz")"
    ok "Workspace archive: ${archive_workspace}"
    ok "Data archive: ${archive_data}"
  fi

  remove_container "${INSTANCE_CONTAINER}"
  remove_volume "${INSTANCE_WORKSPACE_VOLUME}"
  remove_volume "${INSTANCE_DATA_VOLUME}"

  if [[ -f "${INSTANCE_CONFIG_PATH}" ]]; then
    rm -f "${INSTANCE_CONFIG_PATH}"
    rmdir "$(dirname "${INSTANCE_CONFIG_PATH}")" 2>/dev/null || true
  fi

  if (( archive )); then
    update_state_archived "$name" "$now" "$archive_workspace" "$archive_data"
    ok "Archived ${name}"
  else
    remove_state_entry "$name"
    ok "Destroyed ${name}"
  fi
}

main "$@"
