#!/usr/bin/env bash
set -euo pipefail

# Delete one web-ha pod and verify that Kubernetes recreates it automatically.

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
OUT_DIR="${ROOT_DIR}/evidencias/testing"
OUT_FILE="${OUT_DIR}/11_web-ha_recuperacion_pod.txt"

mkdir -p "${OUT_DIR}"
: > "${OUT_FILE}"

echo "--- initial deployment ---" | tee -a "${OUT_FILE}"
kubectl -n testing get deployment web-ha -o wide 2>&1 | tee -a "${OUT_FILE}"

echo "--- pods before deletion ---" | tee -a "${OUT_FILE}"
kubectl -n testing get pods -l app=web-ha -o wide 2>&1 | tee -a "${OUT_FILE}"

POD="$(kubectl -n testing get pod -l app=web-ha -o jsonpath='{.items[0].metadata.name}')"

echo "--- deleted pod: ${POD} ---" | tee -a "${OUT_FILE}"
kubectl -n testing delete pod "${POD}" 2>&1 | tee -a "${OUT_FILE}"

echo "--- rollout status ---" | tee -a "${OUT_FILE}"
kubectl -n testing rollout status deployment/web-ha --timeout=180s 2>&1 | tee -a "${OUT_FILE}"

echo "--- pods after recovery ---" | tee -a "${OUT_FILE}"
kubectl -n testing get pods -l app=web-ha -o wide 2>&1 | tee -a "${OUT_FILE}"

echo "--- final deployment ---" | tee -a "${OUT_FILE}"
kubectl -n testing get deployment web-ha -o wide 2>&1 | tee -a "${OUT_FILE}"
