#!/usr/bin/env bash
set -euo pipefail

RELEASE_NAME="${RELEASE_NAME:-wp}"
NAMESPACE="${NAMESPACE:-wordpress}"
SERVICE_NAME="${SERVICE_NAME:-wp-wordpress}"
PUBLIC_URL="${PUBLIC_URL:-http://wordpress.mastodon-dominant.ts.net}"

helm status "${RELEASE_NAME}" -n "${NAMESPACE}"

echo
kubectl get pods -n "${NAMESPACE}" -o wide

echo
kubectl get pvc -n "${NAMESPACE}" -o wide

echo
kubectl -n longhorn-system get volumes.longhorn.io

echo
kubectl -n longhorn-system get replicas.longhorn.io

echo
kubectl get svc "${SERVICE_NAME}" -n "${NAMESPACE}" -o wide

echo
curl -I --max-time 15 "${PUBLIC_URL}"
