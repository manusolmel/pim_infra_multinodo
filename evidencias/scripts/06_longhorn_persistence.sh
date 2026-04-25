#!/usr/bin/env bash
set -euo pipefail

# Create a Longhorn-backed PVC, write data, recreate the pod, and verify that the data persists.

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
OUT_DIR="${ROOT_DIR}/evidencias/testing"
OUT_FILE="${OUT_DIR}/14_longhorn_persistencia.txt"
MANIFEST_DIR="${ROOT_DIR}/manifests/testing"
MANIFEST_FILE="${MANIFEST_DIR}/longhorn-persistence-test.yaml"

mkdir -p "${OUT_DIR}" "${MANIFEST_DIR}"
: > "${OUT_FILE}"

cat > "${MANIFEST_FILE}" <<'YAML'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: longhorn-persistence-test
  namespace: testing
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: longhorn-persistence-writer
  namespace: testing
spec:
  restartPolicy: Never
  containers:
    - name: writer
      image: busybox:1.36
      command:
        - sh
        - -c
        - |
          echo "longhorn-persistence-test $(date -Iseconds)" > /data/test.txt
          cat /data/test.txt
          sleep 3600
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: longhorn-persistence-test
YAML

echo "--- apply persistence test manifest ---" | tee -a "${OUT_FILE}"
kubectl apply -f "${MANIFEST_FILE}" 2>&1 | tee -a "${OUT_FILE}"

echo "--- wait for writer pod ---" | tee -a "${OUT_FILE}"
kubectl -n testing wait pod/longhorn-persistence-writer \
  --for=condition=Ready \
  --timeout=180s 2>&1 | tee -a "${OUT_FILE}"

echo "--- initial data ---" | tee -a "${OUT_FILE}"
kubectl -n testing exec longhorn-persistence-writer -- cat /data/test.txt 2>&1 | tee -a "${OUT_FILE}"

echo "--- pvc state ---" | tee -a "${OUT_FILE}"
kubectl -n testing get pvc longhorn-persistence-test -o wide 2>&1 | tee -a "${OUT_FILE}"

echo "--- delete writer pod ---" | tee -a "${OUT_FILE}"
kubectl -n testing delete pod longhorn-persistence-writer 2>&1 | tee -a "${OUT_FILE}"

cat > "${MANIFEST_DIR}/longhorn-persistence-reader.yaml" <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: longhorn-persistence-reader
  namespace: testing
spec:
  restartPolicy: Never
  containers:
    - name: reader
      image: busybox:1.36
      command:
        - sh
        - -c
        - |
          cat /data/test.txt
          sleep 3600
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: longhorn-persistence-test
YAML

echo "--- apply reader pod ---" | tee -a "${OUT_FILE}"
kubectl apply -f "${MANIFEST_DIR}/longhorn-persistence-reader.yaml" 2>&1 | tee -a "${OUT_FILE}"

echo "--- wait for reader pod ---" | tee -a "${OUT_FILE}"
kubectl -n testing wait pod/longhorn-persistence-reader \
  --for=condition=Ready \
  --timeout=180s 2>&1 | tee -a "${OUT_FILE}"

echo "--- persisted data after pod recreation ---" | tee -a "${OUT_FILE}"
kubectl -n testing exec longhorn-persistence-reader -- cat /data/test.txt 2>&1 | tee -a "${OUT_FILE}"

echo "--- Longhorn volume state ---" | tee -a "${OUT_FILE}"
kubectl -n longhorn-system get volumes.longhorn.io 2>&1 | tee -a "${OUT_FILE}"

echo "--- cleanup note ---" | tee -a "${OUT_FILE}"
echo "To clean up: kubectl -n testing delete pod longhorn-persistence-reader; kubectl -n testing delete pvc longhorn-persistence-test" | tee -a "${OUT_FILE}"
