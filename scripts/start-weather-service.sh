#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-devops-lite}"
KIND_CONTEXT="kind-${CLUSTER_NAME}"
IMAGE_NAME="${IMAGE_NAME:-weather-live-stream:local}"
LOCAL_PORT="${LOCAL_PORT:-5035}"
FALLBACK_LOCAL_PORT="${FALLBACK_LOCAL_PORT:-5037}"
APP_DEPLOYMENT="${APP_DEPLOYMENT:-weather-live-stream}"
PROXY_DEPLOYMENT="${PROXY_DEPLOYMENT:-weather-nginx}"
SERVICE_NAME="${SERVICE_NAME:-weather-nginx}"
LEGACY_SERVICE_NAME="${LEGACY_SERVICE_NAME:-weather-live-stream}"
SERVICE_PORT="${SERVICE_PORT:-80}"
PORT_FORWARD_LOG_SET="${PORT_FORWARD_LOG+x}"
PORT_FORWARD_PID_FILE_SET="${PORT_FORWARD_PID_FILE+x}"
PORT_FORWARD_SESSION_SET="${PORT_FORWARD_SESSION+x}"
PORT_FORWARD_LOG="${PORT_FORWARD_LOG:-/tmp/weather-live-stream-port-forward.log}"
PORT_FORWARD_PID_FILE="${PORT_FORWARD_PID_FILE:-/tmp/weather-live-stream-port-forward.pid}"
PORT_FORWARD_SESSION="${PORT_FORWARD_SESSION:-weather-live-stream-port-forward}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command docker
require_command kind
require_command kubectl
require_command lsof
require_command ps

wait_for_weather_endpoint() {
  for _ in {1..30}; do
    if curl -fsS "http://127.0.0.1:${LOCAL_PORT}/" >/dev/null 2>&1; then
      return 0
    fi

    sleep 1
  done

  return 1
}

port_owner_args() {
  local port="$1"
  local pid

  pid="$(lsof -nP -iTCP:"${port}" -sTCP:LISTEN -t 2>/dev/null | head -n 1 || true)"
  if [[ -n "${pid}" ]]; then
    ps -p "${pid}" -o args= 2>/dev/null || true
  fi
}

if command -v orb >/dev/null 2>&1; then
  orb start
fi

docker info >/dev/null

if ! kind get clusters | grep -Fxq "${CLUSTER_NAME}"; then
  kind create cluster --name "${CLUSTER_NAME}" --config "${ROOT_DIR}/kind-devops.yaml"
fi

kubectl config use-context "${KIND_CONTEXT}" >/dev/null

docker build -t "${IMAGE_NAME}" "${ROOT_DIR}"
kind load docker-image "${IMAGE_NAME}" --name "${CLUSTER_NAME}"

kubectl apply -f "${ROOT_DIR}/k8s/otel-collector.yaml"
kubectl apply -f "${ROOT_DIR}/k8s/weather-live-stream.yaml"
kubectl apply -f "${ROOT_DIR}/k8s/weather-nginx.yaml"
if kubectl api-resources --api-group=monitoring.coreos.com | grep -q '^servicemonitors'; then
  kubectl apply -f "${ROOT_DIR}/k8s/weather-servicemonitor.yaml"
else
  echo "ServiceMonitor CRD not found; skipping Prometheus scrape manifest."
fi
kubectl rollout status deployment/otel-collector -n observability --timeout=5m
kubectl rollout restart deployment/"${APP_DEPLOYMENT}"
kubectl rollout restart deployment/"${PROXY_DEPLOYMENT}"
kubectl rollout status deployment/"${APP_DEPLOYMENT}" --timeout=5m
kubectl rollout status deployment/"${PROXY_DEPLOYMENT}" --timeout=5m

PIDS="$(lsof -nP -iTCP:"${LOCAL_PORT}" -sTCP:LISTEN -t 2>/dev/null || true)"

if [[ -n "${PIDS}" ]]; then
  for PID in ${PIDS}; do
    ARGS="$(ps -p "${PID}" -o args= 2>/dev/null || true)"

    if [[ "${ARGS}" == *kubectl* && "${ARGS}" == *port-forward* && "${ARGS}" == *"${SERVICE_NAME}"* ]]; then
      wait_for_weather_endpoint
      echo "Weather service is already reachable through Nginx at http://127.0.0.1:${LOCAL_PORT}/"
      exit 0
    fi

    if [[ "${ARGS}" == *kubectl* && "${ARGS}" == *port-forward* && "${ARGS}" == *"${LEGACY_SERVICE_NAME}"* ]]; then
      kill "${PID}"
      echo "Stopped legacy direct weather service port-forward on 127.0.0.1:${LOCAL_PORT} (PID ${PID})."
    fi
  done

  PIDS="$(lsof -nP -iTCP:"${LOCAL_PORT}" -sTCP:LISTEN -t 2>/dev/null || true)"

  if [[ -n "${PIDS}" ]]; then
    OWNER_ARGS="$(port_owner_args "${LOCAL_PORT}")"

    if [[ "${LOCAL_PORT}" == "5035" && "${OWNER_ARGS}" == *dcp* ]]; then
      echo "Port 5035 is already used by Aspire DCP; using Kubernetes fallback port ${FALLBACK_LOCAL_PORT}."
      LOCAL_PORT="${FALLBACK_LOCAL_PORT}"
      if [[ -z "${PORT_FORWARD_LOG_SET}" ]]; then
        PORT_FORWARD_LOG="/tmp/weather-live-stream-port-forward-${LOCAL_PORT}.log"
      fi
      if [[ -z "${PORT_FORWARD_PID_FILE_SET}" ]]; then
        PORT_FORWARD_PID_FILE="/tmp/weather-live-stream-port-forward-${LOCAL_PORT}.pid"
      fi
      if [[ -z "${PORT_FORWARD_SESSION_SET}" ]]; then
        PORT_FORWARD_SESSION="weather-live-stream-port-forward-${LOCAL_PORT}"
      fi

      if lsof -nP -iTCP:"${LOCAL_PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
        echo "Fallback port ${LOCAL_PORT} is already in use." >&2
        lsof -nP -iTCP:"${LOCAL_PORT}" -sTCP:LISTEN >&2
        exit 1
      fi
    else
      echo "Port ${LOCAL_PORT} is already in use by another process." >&2
      lsof -nP -iTCP:"${LOCAL_PORT}" -sTCP:LISTEN >&2
      exit 1
    fi
  fi
fi

rm -f "${PORT_FORWARD_LOG}" "${PORT_FORWARD_PID_FILE}"

if command -v screen >/dev/null 2>&1; then
  screen -S "${PORT_FORWARD_SESSION}" -X quit >/dev/null 2>&1 || true
  screen -dmS "${PORT_FORWARD_SESSION}" sh -c "kubectl --context '${KIND_CONTEXT}' port-forward svc/'${SERVICE_NAME}' '${LOCAL_PORT}:${SERVICE_PORT}' --address 127.0.0.1 >'${PORT_FORWARD_LOG}' 2>&1"
else
  nohup kubectl --context "${KIND_CONTEXT}" port-forward \
    svc/"${SERVICE_NAME}" "${LOCAL_PORT}:${SERVICE_PORT}" \
    --address 127.0.0.1 >"${PORT_FORWARD_LOG}" 2>&1 &
  echo "$!" >"${PORT_FORWARD_PID_FILE}"
fi

wait_for_weather_endpoint

echo "Weather service is running through Nginx at http://127.0.0.1:${LOCAL_PORT}/"
echo "Port-forward log: ${PORT_FORWARD_LOG}"
if [[ -f "${PORT_FORWARD_PID_FILE}" ]]; then
  echo "Port-forward PID file: ${PORT_FORWARD_PID_FILE}"
elif command -v screen >/dev/null 2>&1 && screen -ls | grep -q "[.]${PORT_FORWARD_SESSION}[[:space:]]"; then
  echo "Port-forward screen session: ${PORT_FORWARD_SESSION}"
fi
