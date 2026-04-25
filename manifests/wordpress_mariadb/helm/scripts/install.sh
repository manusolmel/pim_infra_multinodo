#!/usr/bin/env bash
set -euo pipefail

RELEASE_NAME="${RELEASE_NAME:-wp}"
NAMESPACE="${NAMESPACE:-wordpress}"
CHART="${CHART:-bitnami/wordpress}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HELM_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
VALUES_FILE="${VALUES_FILE:-${HELM_DIR}/values.local.yaml}"

if [[ ! -f "${VALUES_FILE}" ]]; then
  echo "Missing values file: ${VALUES_FILE}" >&2
  echo "Create it from values.example.yaml and replace CHANGE_ME values." >&2
  exit 1
fi

helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1 || true
helm repo update

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

helm install "${RELEASE_NAME}" "${CHART}" \
  --namespace "${NAMESPACE}" \
  -f "${VALUES_FILE}" \
  -f "${HELM_DIR}/values-small-ha.yaml" \
  -f "${HELM_DIR}/node-affinity-workers.yaml" \
  --wait \
  --rollback-on-failure \
  --timeout 20m
