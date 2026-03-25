#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_bin jq
require_bin podman

usage() {
  cat <<'EOT'
usage: provision.sh <name> [--channel signal|telegram|discord|none] [--model opus|sonnet]
EOT
}

NAME="${1:-}"
CHANNEL="none"
MODEL="opus"

if [[ -z "${NAME}" ]]; then
  usage
  exit 1
fi
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel)
      CHANNEL="${2:-}"
      shift 2
      ;;
    --model)
      MODEL="${2:-}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

validate_name "${NAME}"
ensure_state
ensure_network

if instance_exists "${NAME}"; then
  echo "instance already exists: ${NAME}" >&2
  exit 1
fi

case "${CHANNEL}" in
  signal|telegram|discord|none) ;;
  *)
    echo "invalid channel: ${CHANNEL}" >&2
    exit 1
    ;;
esac

case "${MODEL}" in
  opus|sonnet) ;;
  *)
    echo "invalid model: ${MODEL}" >&2
    exit 1
    ;;
esac

PORT="$(allocate_port)"
CONTAINER="forge-${NAME}"
VOLUME="forge-${NAME}-data"
CREATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if [[ "${MODEL}" == "opus" ]]; then
  MODEL_PRIMARY="anthropic/claude-opus-4-5"
else
  MODEL_PRIMARY="anthropic/claude-sonnet-4"
fi

podman volume create "${VOLUME}" >/dev/null

podman run -d \
  --name "${CONTAINER}" \
  --network "${NETWORK_NAME}" \
  -p "${PORT}:18789" \
  -v "${VOLUME}:/home/openclaw/.openclaw" \
  -e "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}" \
  -e "OPENAI_API_KEY=${OPENAI_API_KEY:-}" \
  -e "OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN:-}" \
  -e "FORGE_INSTANCE_NAME=${NAME}" \
  -e "FORGE_INSTANCE_MODEL=${MODEL}" \
  -e "FORGE_INSTANCE_MODEL_PRIMARY=${MODEL_PRIMARY}" \
  -e "FORGE_INSTANCE_CHANNEL=${CHANNEL}" \
  -e "OPENCLAW_GATEWAY_PORT=18789" \
  -e "OPENCLAW_GATEWAY_BIND=0.0.0.0" \
  --label "fleet.managed=true" \
  --label "fleet.name=${NAME}" \
  --label "fleet.channel=${CHANNEL}" \
  --label "fleet.model=${MODEL}" \
  "${INSTANCE_IMAGE}" >/dev/null

PAYLOAD="$(jq -n \
  --arg container "${CONTAINER}" \
  --argjson port "${PORT}" \
  --arg volume "${VOLUME}" \
  --arg status "running" \
  --arg model "${MODEL}" \
  --arg channel "${CHANNEL}" \
  --arg createdAt "${CREATED_AT}" \
  --arg lastActivity "${CREATED_AT}" \
  '{
    container: $container,
    port: $port,
    volume: $volume,
    status: $status,
    model: $model,
    channel: $channel,
    createdAt: $createdAt,
    lastActivity: $lastActivity
  }')"

save_instance "${NAME}" "${PAYLOAD}"
set_next_port "$((PORT + 1))"

jq -n \
  --arg name "${NAME}" \
  --arg container "${CONTAINER}" \
  --arg volume "${VOLUME}" \
  --arg channel "${CHANNEL}" \
  --arg model "${MODEL}" \
  --arg status "running" \
  --arg createdAt "${CREATED_AT}" \
  --arg lastActivity "${CREATED_AT}" \
  --argjson port "${PORT}" \
  '{
    name: $name,
    container: $container,
    volume: $volume,
    port: $port,
    channel: $channel,
    model: $model,
    status: $status,
    createdAt: $createdAt,
    lastActivity: $lastActivity
  }'
