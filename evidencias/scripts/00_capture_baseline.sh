#!/usr/bin/env bash
set -euo pipefail

# Capture the baseline state of the Kubernetes cluster before running functional tests.

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
OUT_DIR="${ROOT_DIR}/evidencias/testing"

mkdir -p "${OUT_DIR}"

date | tee "${OUT_DIR}/00_timestamp.txt"

kubectl get nodes -o wide 2>&1 | tee "${OUT_DIR}/01_nodes_base.txt"
kubectl get pods -A -o wide 2>&1 | tee "${OUT_DIR}/02_pods_base.txt"
kubectl get storageclass 2>&1 | tee "${OUT_DIR}/03_storageclass_base.txt"
kubectl get pods -n longhorn-system -o wide 2>&1 | tee "${OUT_DIR}/04_longhorn_pods_base.txt"
kubectl get pods -n tailscale -o wide 2>&1 | tee "${OUT_DIR}/05_tailscale_pods_base.txt"
kubectl get proxygroup -A 2>&1 | tee "${OUT_DIR}/06_proxygroup_base.txt"
kubectl get --raw='/readyz?verbose' 2>&1 | tee "${OUT_DIR}/07_apiserver_readyz.txt"
kubectl get --raw='/livez?verbose' 2>&1 | tee "${OUT_DIR}/08_apiserver_livez.txt"
