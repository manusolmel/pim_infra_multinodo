#!/usr/bin/env bash
set -euo pipefail

# Send repeated HTTP requests to web-ha to verify traffic distribution across replicas.

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
OUT_DIR="${ROOT_DIR}/evidencias/testing"
OUT_FILE="${OUT_DIR}/10_web-ha_balanceo.txt"

mkdir -p "${OUT_DIR}"
: > "${OUT_FILE}"

echo "--- repeated HTTP requests ---" | tee -a "${OUT_FILE}"

for i in $(seq 1 20); do
  echo "---- request ${i} ----" | tee -a "${OUT_FILE}"
  curl -sS --max-time 5 http://web-ha.mastodon-dominant.ts.net 2>&1 | tee -a "${OUT_FILE}"
  sleep 1
done

echo "--- backend summary ---" | tee -a "${OUT_FILE}"
grep "web-ha pod:" "${OUT_FILE}" | sort | uniq -c | tee -a "${OUT_FILE}" || true

echo "--- pods after test ---" | tee -a "${OUT_FILE}"
kubectl -n testing get pods -l app=web-ha -o wide 2>&1 | tee -a "${OUT_FILE}"
