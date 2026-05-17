#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/load-env.sh"
load_project_env "${ROOT_DIR}"

if ! command -v ngrok >/dev/null 2>&1; then
  echo "Missing required command: ngrok" >&2
  echo "Install it with: brew install ngrok" >&2
  exit 1
fi

if [[ -z "${NGROK_AUTHTOKEN:-}" ]]; then
  echo "Set NGROK_AUTHTOKEN in ${ENV_FILE:-${ROOT_DIR}/.env.local} before running this script." >&2
  exit 1
fi

ngrok config add-authtoken "${NGROK_AUTHTOKEN}"
echo "ngrok authtoken saved to your local ngrok config."
