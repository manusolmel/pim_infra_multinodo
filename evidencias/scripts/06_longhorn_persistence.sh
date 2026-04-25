#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
OUT_DIR="${ROOT_DIR}/evidencias/testing"
OUT_FILE="${OUT_DIR}/14_longhorn_persistencia.txt"
MANIFEST_DIR="${ROOT_DIR}/manifests/testing"
WRITER_MANIFEST="${MANIFEST_DIR}/longhorn-persistence-test.yaml"
READER_MANIFEST="${MANIFEST_DIR}/longhorn-persistence-reader.yaml"

mkdir -p "${OUT_DIR}" "${MANIFEST_DIR}"
: > "${OUT_FILE}"

log() {
  echo "$@" | tee -a "${OUT_FILE}"
}

run() {
  "$@" 2>&1 | tee -a "${OUT_FILE}"
}

log "--- cleanup previous test resources ---"
run kubectl -n testing delete pod longhorn-persistence-writer --ignore-not-found
run kubectl -n testing delete pod longhorn-persistence-reader --ignore-not-found
run kubectl -n testing delete pvc longhorn-persistence-test --ignore-not-found

log "--- wait cleanup ---"
kubectl -n testing wait pod/longhorn-persistence-writer --for=delete --timeout=60s 2>/dev/null || true
kubectl -n testing wait pod/longhorn-persistence-reader --for=delete --timeout=60s 2>/dev/null || true
sleep 15

cat > "${WRITER_MANIFEST}" <<'YAML'
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
      image: nginx:stable-alpine
      command:
        - /bin/sh
        - -c
        - |
          echo "longhorn-persistence-test $(date -Iseconds)" > /data/test.txt
          sync
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

log "--- apply writer manifest ---"
run kubectl apply -f "${WRITER_MANIFEST}"

log "--- wait writer pod ready ---"
run kubectl -n testing wait pod/longhorn-persistence-writer --for=condition=Ready --timeout=240s

WRITER_NODE="$(kubectl -n testing get pod longhorn-persistence-writer -o jsonpath='{.spec.nodeName}')"
log "--- writer node: ${WRITER_NODE} ---"

log "--- wait for data file ---"
for i in $(seq 1 30); do
  if kubectl -n testing exec longhorn-persistence-writer -- test -f /data/test.txt 2>/dev/null; then
    break
  fi
  sleep 1
done

log "--- initial data written in PVC ---"
INITIAL_DATA="$(kubectl -n testing exec longhorn-persistence-writer -- cat /data/test.txt)"
log "${INITIAL_DATA}"

log "--- pvc state after write ---"
run kubectl -n testing get pvc longhorn-persistence-test -o wide

log "--- writer pod state ---"
run kubectl -n testing get pod longhorn-persistence-writer -o wide

log "--- delete writer pod ---"
run kubectl -n testing delete pod longhorn-persistence-writer
kubectl -n testing wait pod/longhorn-persistence-writer --for=delete --timeout=120s 2>/dev/null || true

cat > "${READER_MANIFEST}" <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: longhorn-persistence-reader
  namespace: testing
spec:
  nodeName: ${WRITER_NODE}
  restartPolicy: Never
  containers:
    - name: reader
      image: nginx:stable-alpine
      command:
        - /bin/sh
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

log "--- apply reader manifest on same node ---"
run kubectl apply -f "${READER_MANIFEST}"

log "--- wait reader pod ready ---"
run kubectl -n testing wait pod/longhorn-persistence-reader --for=condition=Ready --timeout=240s

log "--- persisted data after pod recreation ---"
PERSISTED_DATA="$(kubectl -n testing exec longhorn-persistence-reader -- cat /data/test.txt)"
log "${PERSISTED_DATA}"

log "--- data comparison ---"
if [ "${INITIAL_DATA}" = "${PERSISTED_DATA}" ]; then
  log "RESULT: persisted data matches initial data"
else
  log "RESULT: persisted data does not match initial data"
  exit 1
fi

log "--- pvc final state ---"
run kubectl -n testing get pvc longhorn-persistence-test -o wide

log "--- longhorn volumes ---"
run kubectl -n longhorn-system get volumes.longhorn.io

log "--- final pods ---"
kubectl -n testing get pods -o wide | grep -E 'longhorn-persistence|NAME' 2>&1 | tee -a "${OUT_FILE}"

log "--- cleanup command ---"
log "kubectl -n testing delete pod longhorn-persistence-reader --ignore-not-found"
log "kubectl -n testing delete pvc longhorn-persistence-test --ignore-not-found"
