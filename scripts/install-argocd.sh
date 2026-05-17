#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-devops-lite}"
KIND_CONTEXT="kind-${CLUSTER_NAME}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.13.3}"
REPO_URL="${REPO_URL:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command kubectl
require_command kind

if [[ -z "${REPO_URL}" ]]; then
  echo "Set REPO_URL to your Git repository URL before running this script." >&2
  exit 1
fi

kubectl config use-context "${KIND_CONTEXT}" >/dev/null

kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n "${ARGOCD_NAMESPACE}" -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
kubectl -n "${ARGOCD_NAMESPACE}" rollout status deployment/argocd-server --timeout=10m

sed "s|REPO_URL|${REPO_URL}|g" "${ROOT_DIR}/gitops/argocd/application.yaml" | kubectl apply -f -

cat <<EOF
Argo CD installed.

Port-forward:
  kubectl -n ${ARGOCD_NAMESPACE} port-forward svc/argocd-server 8080:443

Default login:
  username: admin
  password: first password from:
  kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d

Before syncing the app, confirm the image in:
  gitops/weather-live-stream/weather-app.yaml
EOF
