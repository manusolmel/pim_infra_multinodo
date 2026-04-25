#!/usr/bin/env bash
set -euo pipefail

# Send HTTP requests while deleting one web-ha pod to check service continuity.

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
OUT_DIR="${ROOT_DIR}/evidencias/testing"
OUT_FILE="${OUT_DIR}/12_web-ha_continuidad_http.txt"

mkdir -p "${OUT_DIR}"
: > "${OUT_FILE}"

echo "--- initial state ---" | tee -a "${OUT_FILE}"
kubectl -n testing get deployment web-ha -o wide 2>&1 | tee -a "${OUT_FILE}"
kubectl -n testing get pods -l app=web-ha -o wide 2>&1 | tee -a "${OUT_FILE}"

echo "--- HTTP loop with status code ---" | tee -a "${OUT_FILE}"

(
  for i in $(seq 1 30); do
    printf "request %02d: " "$i"

    RESPONSE="$(curl -sS --max-time 3 \
      -w " HTTP_CODE=%{http_code} TIME=%{time_total}" \
      http://web-ha.mastodon-dominant.ts.net 2>&1 || true)"

    echo "${RESPONSE}" | tr '\n' ' '
    echo
    sleep 1
  done
) | tee -a "${OUT_FILE}" &

CURL_PID=$!

sleep 5

POD="$(kubectl -n testing get pod -l app=web-ha -o jsonpath='{.items[0].metadata.name}')"
echo "--- pod deleted during HTTP loop: ${POD} ---" | tee -a "${OUT_FILE}"
kubectl -n testing delete pod "${POD}" 2>&1 | tee -a "${OUT_FILE}"

wait "${CURL_PID}"

echo "--- final rollout ---" | tee -a "${OUT_FILE}"
kubectl -n testing rollout status deployment/web-ha --timeout=180s 2>&1 | tee -a "${OUT_FILE}"

echo "--- final state ---" | tee -a "${OUT_FILE}"
kubectl -n testing get pods -l app=web-ha -o wide 2>&1 | tee -a "${OUT_FILE}"
kubectl -n testing get deployment web-ha -o wide 2>&1 | tee -a "${OUT_FILE}"

echo "--- HTTP summary ---" | tee -a "${OUT_FILE}"
grep -o 'HTTP_CODE=[0-9]*' "${OUT_FILE}" | sort | uniq -c | tee -a "${OUT_FILE}" || true

echo "--- possible failures ---" | tee -a "${OUT_FILE}"
grep -Ei 'curl:|HTTP_CODE=000|timeout|failed|refused|unreachable|Could not' "${OUT_FILE}" | tee -a "${OUT_FILE}" || echo "No HTTP errors detected" | tee -a "${OUT_FILE}"
