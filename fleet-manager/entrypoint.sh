#!/usr/bin/env bash
set -euo pipefail

OPENCLAW_HOME="${OPENCLAW_HOME:-/home/openclaw/.openclaw}"
OPENCLAW_CONFIG="${OPENCLAW_CONFIG:-${OPENCLAW_HOME}/openclaw.json5}"
TEMPLATE_ROOT="/opt/fleet-manager"

mkdir -p \
  "${OPENCLAW_HOME}" \
  "${OPENCLAW_HOME}/workspace" \
  "${OPENCLAW_HOME}/fleet/archives" \
  "${OPENCLAW_HOME}/fleet/logs"

if [[ ! -f "${OPENCLAW_CONFIG}" ]]; then
  cp "${TEMPLATE_ROOT}/openclaw.json5" "${OPENCLAW_CONFIG}"
fi

if [[ ! -f "${OPENCLAW_HOME}/workspace/AGENTS.md" ]]; then
  cp -R "${TEMPLATE_ROOT}/workspace/." "${OPENCLAW_HOME}/workspace/"
fi

exec openclaw gateway start --config "${OPENCLAW_CONFIG}"
