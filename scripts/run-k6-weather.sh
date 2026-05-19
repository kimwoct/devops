#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/load-env.sh"
load_project_env "${ROOT_DIR}"

BASE_URL="${BASE_URL:-http://127.0.0.1:${LOCAL_PORT:-5035}}"
VUS="${VUS:-20}"
DURATION="${DURATION:-1m}"

if ! command -v k6 >/dev/null 2>&1; then
  echo "Missing required command: k6" >&2
  echo "Install it with: brew install k6" >&2
  exit 1
fi

echo "Running k6 weather API test:"
echo "  BASE_URL=${BASE_URL}"
echo "  VUS=${VUS}"
echo "  DURATION=${DURATION}"

BASE_URL="${BASE_URL}" VUS="${VUS}" DURATION="${DURATION}" \
  k6 run "${ROOT_DIR}/tests/performance/weather-local.js"
