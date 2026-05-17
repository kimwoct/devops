#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/load-env.sh"
load_project_env "${ROOT_DIR}"

NGROK_LOCAL_URL="${NGROK_LOCAL_URL:-http://127.0.0.1:${LOCAL_PORT:-5035}}"
NGROK_BASIC_AUTH_ENABLED="${NGROK_BASIC_AUTH_ENABLED:-false}"

if ! command -v ngrok >/dev/null 2>&1; then
  echo "Missing required command: ngrok" >&2
  echo "Install it with: brew install ngrok" >&2
  exit 1
fi

if [[ "${NGROK_BASIC_AUTH_ENABLED}" == "true" ]]; then
  if [[ -z "${NGROK_BASIC_AUTH_USER:-}" || -z "${NGROK_BASIC_AUTH_PASSWORD:-}" ]]; then
    echo "Set NGROK_BASIC_AUTH_USER and NGROK_BASIC_AUTH_PASSWORD in ${ENV_FILE:-${ROOT_DIR}/.env.local}." >&2
    exit 1
  fi

  POLICY_FILE="$(mktemp /tmp/weather-ngrok-basic-auth.XXXXXX.yml)"
  chmod 600 "${POLICY_FILE}"
  cat >"${POLICY_FILE}" <<EOF
on_http_request:
  - actions:
      - type: basic-auth
        config:
          credentials:
            - ${NGROK_BASIC_AUTH_USER}:${NGROK_BASIC_AUTH_PASSWORD}
EOF

  echo "Starting ngrok for ${NGROK_LOCAL_URL} with basic auth from local env."
  trap 'rm -f "${POLICY_FILE}"' EXIT
  if [[ -n "${NGROK_URL:-}" ]]; then
    ngrok http "${NGROK_LOCAL_URL}" --url "${NGROK_URL}" --traffic-policy-file "${POLICY_FILE}"
    exit $?
  fi

  ngrok http "${NGROK_LOCAL_URL}" --traffic-policy-file "${POLICY_FILE}"
  exit $?
fi

echo "Starting ngrok for ${NGROK_LOCAL_URL}."
if [[ -n "${NGROK_URL:-}" ]]; then
  ngrok http "${NGROK_LOCAL_URL}" --url "${NGROK_URL}"
  exit $?
fi

ngrok http "${NGROK_LOCAL_URL}"
