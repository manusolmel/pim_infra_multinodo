#!/usr/bin/env bash
set -euo pipefail

RELEASE_NAME="${RELEASE_NAME:-wp}"
NAMESPACE="${NAMESPACE:-wordpress}"

helm uninstall "${RELEASE_NAME}" -n "${NAMESPACE}" --wait --timeout 10m || true
kubectl delete namespace "${NAMESPACE}" --wait=true --timeout=10m || true
