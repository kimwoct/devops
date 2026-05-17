#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-devops-lite}"
KIND_CONTEXT="kind-${CLUSTER_NAME}"
LOCAL_PORT="${LOCAL_PORT:-5050}"
SERVICE_NAME="${SERVICE_NAME:-linux-smoke}"
SERVICE_PORT="${SERVICE_PORT:-80}"
PORT_FORWARD_LOG="${PORT_FORWARD_LOG:-/tmp/linux-smoke-port-forward.log}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command kubectl
require_command lsof
require_command ps

kubectl config use-context "${KIND_CONTEXT}" >/dev/null
kubectl apply -f "${ROOT_DIR}/k8s/linux-smoke.yaml"
kubectl rollout status deployment/"${SERVICE_NAME}" --timeout=2m

PIDS="$(lsof -nP -iTCP:"${LOCAL_PORT}" -sTCP:LISTEN -t 2>/dev/null || true)"
if [[ -n "${PIDS}" ]]; then
  echo "Port ${LOCAL_PORT} is already in use." >&2
  lsof -nP -iTCP:"${LOCAL_PORT}" -sTCP:LISTEN >&2
  exit 1
fi

screen -S "${SERVICE_NAME}-port-forward" -X quit >/dev/null 2>&1 || true
screen -dmS "${SERVICE_NAME}-port-forward" sh -c \
  "kubectl --context '${KIND_CONTEXT}' port-forward svc/'${SERVICE_NAME}' '${LOCAL_PORT}:${SERVICE_PORT}' --address 127.0.0.1 >'${PORT_FORWARD_LOG}' 2>&1"

for _ in {1..30}; do
  if curl -fsS "http://127.0.0.1:${LOCAL_PORT}/" >/dev/null 2>&1; then
    echo "linux-smoke is running at http://127.0.0.1:${LOCAL_PORT}/"
    echo "Port-forward log: ${PORT_FORWARD_LOG}"
    exit 0
  fi
  sleep 1
done

echo "linux-smoke did not become reachable." >&2
tail -80 "${PORT_FORWARD_LOG}" >&2 || true
exit 1
