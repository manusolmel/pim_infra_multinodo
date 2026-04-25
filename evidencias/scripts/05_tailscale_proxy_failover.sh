#!/usr/bin/env bash
set -euo pipefail

# Delete one Tailscale ingress proxy while sending HTTP traffic to validate ingress failover.

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
OUT_DIR="${ROOT_DIR}/evidencias/testing"
OUT_FILE="${OUT_DIR}/13_tailscale_proxy_failover.txt"

mkdir -p "${OUT_DIR}"
: > "${OUT_FILE}"

echo "--- initial Tailscale state ---" | tee -a "${OUT_FILE}"
kubectl -n tailscale get pods -o wide 2>&1 | tee -a "${OUT_FILE}"
kubectl get proxygroup -A 2>&1 | tee -a "${OUT_FILE}"

echo "--- initial web-ha state ---" | tee -a "${OUT_FILE}"
kubectl -n testing get svc web-ha -o wide 2>&1 | tee -a "${OUT_FILE}"
kubectl -n testing get pods -l app=web-ha -o wide 2>&1 | tee -a "${OUT_FILE}"

echo "--- HTTP loop against private FQDN ---" | tee -a "${OUT_FILE}"

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

PROXY="$(kubectl -n tailscale get pods -o name | grep '^pod/ingress-proxies-' | head -n1 | cut -d/ -f2)"

echo "--- proxy deleted during HTTP loop: ${PROXY} ---" | tee -a "${OUT_FILE}"
kubectl -n tailscale delete pod "${PROXY}" 2>&1 | tee -a "${OUT_FILE}"

wait "${CURL_PID}"

echo "--- wait for ProxyGroup recovery ---" | tee -a "${OUT_FILE}"
kubectl wait proxygroup ingress-proxies \
  --for=condition=ProxyGroupReady=true \
  --timeout=180s 2>&1 | tee -a "${OUT_FILE}"

echo "--- final Tailscale state ---" | tee -a "${OUT_FILE}"
kubectl -n tailscale get pods -o wide 2>&1 | tee -a "${OUT_FILE}"
kubectl get proxygroup -A 2>&1 | tee -a "${OUT_FILE}"

echo "--- final web-ha check ---" | tee -a "${OUT_FILE}"
curl -sS --max-time 5 \
  -w " HTTP_CODE=%{http_code} TIME=%{time_total}\n" \
  http://web-ha.mastodon-dominant.ts.net 2>&1 | tee -a "${OUT_FILE}" || true

echo "--- HTTP summary ---" | tee -a "${OUT_FILE}"
grep -o 'HTTP_CODE=[0-9]*' "${OUT_FILE}" | sort | uniq -c | tee -a "${OUT_FILE}" || true

echo "--- possible failures ---" | tee -a "${OUT_FILE}"
grep -Ei 'curl:|HTTP_CODE=000|timeout|failed|refused|unreachable|Could not' "${OUT_FILE}" | tee -a "${OUT_FILE}" || echo "No HTTP errors detected" | tee -a "${OUT_FILE}"
