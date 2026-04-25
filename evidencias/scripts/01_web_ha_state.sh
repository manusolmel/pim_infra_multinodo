#!/usr/bin/env bash
set -euo pipefail

# Capture the current state of the web-ha service used for availability tests.

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
OUT_DIR="${ROOT_DIR}/evidencias/testing"
OUT_FILE="${OUT_DIR}/09_web-ha_estado.txt"

mkdir -p "${OUT_DIR}"
: > "${OUT_FILE}"

echo "--- namespace ---" | tee -a "${OUT_FILE}"
kubectl get ns testing 2>&1 | tee -a "${OUT_FILE}"

echo "--- deployment ---" | tee -a "${OUT_FILE}"
kubectl -n testing get deployment web-ha -o wide 2>&1 | tee -a "${OUT_FILE}"

echo "--- service ---" | tee -a "${OUT_FILE}"
kubectl -n testing get svc web-ha -o wide 2>&1 | tee -a "${OUT_FILE}"

echo "--- pods ---" | tee -a "${OUT_FILE}"
kubectl -n testing get pods -l app=web-ha -o wide 2>&1 | tee -a "${OUT_FILE}"

echo "--- fqdn check ---" | tee -a "${OUT_FILE}"
curl -sS --max-time 5 \
  -w " HTTP_CODE=%{http_code} TIME=%{time_total}\n" \
  http://web-ha.mastodon-dominant.ts.net 2>&1 | tee -a "${OUT_FILE}"
