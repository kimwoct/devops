#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-devops-lite}"
KIND_CONTEXT="kind-${CLUSTER_NAME}"
LOCAL_PORT="${LOCAL_PORT:-5035}"
FALLBACK_LOCAL_PORT="${FALLBACK_LOCAL_PORT:-5037}"
APP_DEPLOYMENT="${APP_DEPLOYMENT:-weather-live-stream}"
PROXY_DEPLOYMENT="${PROXY_DEPLOYMENT:-weather-nginx}"
SERVICE_NAME="${SERVICE_NAME:-weather-nginx}"
LEGACY_SERVICE_NAME="${LEGACY_SERVICE_NAME:-weather-live-stream}"
PORT_FORWARD_PID_FILE="${PORT_FORWARD_PID_FILE:-/tmp/weather-live-stream-port-forward.pid}"
PORT_FORWARD_SESSION="${PORT_FORWARD_SESSION:-weather-live-stream-port-forward}"
FALLBACK_PORT_FORWARD_SESSION="${FALLBACK_PORT_FORWARD_SESSION:-weather-live-stream-port-forward-${FALLBACK_LOCAL_PORT}}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command kubectl
require_command lsof
require_command ps

if command -v screen >/dev/null 2>&1; then
  for SESSION in "${PORT_FORWARD_SESSION}" "${FALLBACK_PORT_FORWARD_SESSION}"; do
    if screen -ls | grep -q "[.]${SESSION}[[:space:]]"; then
      screen -S "${SESSION}" -X quit
      echo "Stopped weather service port-forward screen session ${SESSION}."
    fi
  done
fi

if [[ -f "${PORT_FORWARD_PID_FILE}" ]]; then
  PID="$(cat "${PORT_FORWARD_PID_FILE}")"
  ARGS="$(ps -p "${PID}" -o args= 2>/dev/null || true)"

  if [[ "${ARGS}" == *kubectl* && "${ARGS}" == *port-forward* && ( "${ARGS}" == *"${SERVICE_NAME}"* || "${ARGS}" == *"${LEGACY_SERVICE_NAME}"* ) ]]; then
    kill "${PID}"
    echo "Stopped weather service port-forward from PID file (PID ${PID})."
  fi

  rm -f "${PORT_FORWARD_PID_FILE}"
fi

PORTS=("${LOCAL_PORT}")
if [[ "${LOCAL_PORT}" == "5035" && "${FALLBACK_LOCAL_PORT}" != "${LOCAL_PORT}" ]]; then
  PORTS+=("${FALLBACK_LOCAL_PORT}")
fi

for PORT in "${PORTS[@]}"; do
  PIDS="$(lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN -t 2>/dev/null || true)"

  for PID in ${PIDS}; do
    ARGS="$(ps -p "${PID}" -o args= 2>/dev/null || true)"

    if [[ "${ARGS}" == *kubectl* && "${ARGS}" == *port-forward* && ( "${ARGS}" == *"${SERVICE_NAME}"* || "${ARGS}" == *"${LEGACY_SERVICE_NAME}"* ) ]]; then
      kill "${PID}"
      echo "Stopped weather service port-forward on 127.0.0.1:${PORT} (PID ${PID})."
    else
      echo "Port ${PORT} is used by a non-weather-service process; leaving PID ${PID} running." >&2
    fi
  done
done

if ! kubectl config get-contexts -o name | grep -Fxq "${KIND_CONTEXT}"; then
  echo "Kubernetes context ${KIND_CONTEXT} was not found; nothing else to stop."
  exit 0
fi

for DEPLOYMENT in "${PROXY_DEPLOYMENT}" "${APP_DEPLOYMENT}"; do
  if kubectl --context "${KIND_CONTEXT}" get deployment "${DEPLOYMENT}" >/dev/null 2>&1; then
    kubectl --context "${KIND_CONTEXT}" scale deployment/"${DEPLOYMENT}" --replicas=0
    kubectl --context "${KIND_CONTEXT}" rollout status deployment/"${DEPLOYMENT}" --timeout=2m
    echo "Scaled deployment/${DEPLOYMENT} to 0 replicas."
  else
    echo "deployment/${DEPLOYMENT} was not found in ${KIND_CONTEXT}; nothing to scale."
  fi
done

if kubectl --context "${KIND_CONTEXT}" get deployment otel-collector -n observability >/dev/null 2>&1; then
  kubectl --context "${KIND_CONTEXT}" scale deployment/otel-collector -n observability --replicas=0
  kubectl --context "${KIND_CONTEXT}" rollout status deployment/otel-collector -n observability --timeout=2m
  echo "Scaled deployment/otel-collector in namespace observability to 0 replicas."
fi
