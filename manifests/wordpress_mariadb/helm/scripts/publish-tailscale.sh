#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-wordpress}"
SERVICE_NAME="${SERVICE_NAME:-wp-wordpress}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HELM_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

kubectl patch svc "${SERVICE_NAME}" -n "${NAMESPACE}" \
  --type=merge \
  -p "$(cat "${HELM_DIR}/service-tailscale-patch.json")"

kubectl wait svc "${SERVICE_NAME}" -n "${NAMESPACE}" \
  --for=condition=TailscaleIngressSvcConfigured=true \
  --timeout=180s

kubectl get svc "${SERVICE_NAME}" -n "${NAMESPACE}" -o wide
