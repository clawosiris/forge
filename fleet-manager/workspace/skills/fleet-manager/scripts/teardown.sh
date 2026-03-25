#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_bin jq
require_bin podman

usage() {
  cat <<'EOT'
usage: teardown.sh (--archive|--destroy) <name>
EOT
}

MODE="${1:-}"
NAME="${2:-}"

if [[ -z "${MODE}" || -z "${NAME}" ]]; then
  usage
  exit 1
fi

case "${MODE}" in
  --archive|--destroy) ;;
  *)
    usage
    exit 1
    ;;
esac

validate_name "${NAME}"
ensure_state

if ! instance_exists "${NAME}"; then
  echo "unknown instance: ${NAME}" >&2
  exit 1
fi

CONTAINER="$(instance_field "${NAME}" "container")"
VOLUME="$(instance_field "${NAME}" "volume")"
PORT="$(instance_field "${NAME}" "port")"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
ARCHIVE_PATH=""

if container_exists "${CONTAINER}"; then
  if [[ "$(container_state "${CONTAINER}")" == "running" ]]; then
    podman stop "${CONTAINER}" >/dev/null
  fi
  podman rm "${CONTAINER}" >/dev/null
fi

if [[ "${MODE}" == "--archive" ]]; then
  require_archive_host_dir
  mkdir -p "${HOST_STATE_DIR}/archives"
  ARCHIVE_PATH="${HOST_STATE_DIR}/archives/${NAME}-${TIMESTAMP}.tar.gz"

  podman run --rm \
    -v "${VOLUME}:/source:ro" \
    -v "${HOST_STATE_DIR}/archives:/archive:Z" \
    docker.io/library/alpine:3.20 \
    sh -lc "tar czf \"/archive/${NAME}-${TIMESTAMP}.tar.gz\" -C /source ."

  if podman volume exists "${VOLUME}"; then
    podman volume rm "${VOLUME}" >/dev/null
  fi

  update_instance_status "${NAME}" "archived" "${TIMESTAMP}"

  jq -n \
    --arg name "${NAME}" \
    --arg status "archived" \
    --arg archivePath "${ARCHIVE_PATH}" \
    --arg archivedAt "${TIMESTAMP}" \
    --argjson port "${PORT}" \
    '{
      name: $name,
      status: $status,
      port: $port,
      archivePath: $archivePath,
      archivedAt: $archivedAt
    }'
  exit 0
fi

if podman volume exists "${VOLUME}"; then
  podman volume rm "${VOLUME}" >/dev/null
fi

remove_instance "${NAME}"

jq -n \
  --arg name "${NAME}" \
  --arg status "destroyed" \
  --arg destroyedAt "${TIMESTAMP}" \
  --arg volume "${VOLUME}" \
  --arg container "${CONTAINER}" \
  --argjson port "${PORT}" \
  '{
    name: $name,
    status: $status,
    container: $container,
    volume: $volume,
    port: $port,
    destroyedAt: $destroyedAt
  }'
