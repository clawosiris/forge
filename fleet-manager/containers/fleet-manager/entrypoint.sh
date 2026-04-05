#!/usr/bin/env bash
set -euo pipefail

node /app/webhook/pr-merged.js &
exec openclaw gateway
