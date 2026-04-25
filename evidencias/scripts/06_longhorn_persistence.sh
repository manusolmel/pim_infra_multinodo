cd ~/pim_infra_multinodo || exit 1

cat > evidencias/scripts/06_longhorn_persistence.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Create a Longhorn-backed PVC, write data, recreate the pod, and verify that the data persists.

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
OUT_DIR="${ROOT_DIR}/evidencias/testing"
OUT_FILE="${OUT_DIR}/14_longhorn_persistencia.txt"
MANIFEST_DIR="${ROOT_DIR}/manifests/testing"
PVC_MANIFEST="${MANIFEST_DIR}/longhorn-persistence-test.yaml"
READER_MANIFEST="${MANIFEST_DIR}/longhorn-persistence-reader.yaml"

mkdir -p "${OUT_DIR}" "${MANIFEST_DIR}"
: > "${OUT_FILE}"

echo "--- cleanup previous test resources ---" | tee -a "${OUT_FILE}"
kubectl -n testing delete pod longhorn-persistence-writer --ignore-not-found 2>&1 | tee -a "${OUT_FILE}"
kubectl -n testing delete pod longhorn-persistence-reader --ignore-not-found 2>&1 | tee -a "${OUT_FILE}"
kubectl -n testing delete pvc longhorn-persistence-test --ignore-not-found 2>&1 | tee -a "${OUT_FILE}"

echo "--- wait cleanup ---" | tee -a "${OUT_FILE}"
sleep 10

cat > "${PVC_MANIFEST}" <<'YAML'
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

echo "--- apply writer manifest ---" | tee -a "${OUT_FILE}"
kubectl apply -f "${PVC_MANIFEST}" 2>&1 | tee -a "${OUT_FILE}"

echo "--- wait writer pod ready ---" | tee -a "${OUT_FILE}"
kubectl -n testing wait pod/longhorn-persistence-writer \
  --for=condition=Ready \
  --timeout=180s 2>&1 | tee -a "${OUT_FILE}"

echo "--- wait for data file ---" | tee -a "${OUT_FILE}"
for i in $(seq 1 30); do
  if kubectl -n testing exec longhorn-persistence-writer -- test -f /data/test.txt 2>/dev/null; then
    break
  fi
  sleep 1
done

echo "--- initial data written in PVC ---" | tee -a "${OUT_FILE}"
kubectl -n testing exec longhorn-persistence-writer -- cat /data/test.txt 2>&1 | tee -a "${OUT_FILE}"

echo "--- pvc state after write ---" | tee -a "${OUT_FILE}"
kubectl -n testing get pvc longhorn-persistence-test -o wide 2>&1 | tee -a "${OUT_FILE}"

echo "--- writer pod state ---" | tee -a "${OUT_FILE}"
kubectl -n testing get pod longhorn-persistence-writer -o wide 2>&1 | tee -a "${OUT_FILE}"

echo "--- delete writer pod ---" | tee -a "${OUT_FILE}"
kubectl -n testing delete pod longhorn-persistence-writer 2>&1 | tee -a "${OUT_FILE}"

cat > "${READER_MANIFEST}" <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: longhorn-persistence-reader
  namespace: testing
spec:
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

echo "--- apply reader manifest ---" | tee -a "${OUT_FILE}"
kubectl apply -f "${READER_MANIFEST}" 2>&1 | tee -a "${OUT_FILE}"

echo "--- wait reader pod ready ---" | tee -a "${OUT_FILE}"
kubectl -n testing wait pod/longhorn-persistence-reader \
  --for=condition=Ready \
  --timeout=180s 2>&1 | tee -a "${OUT_FILE}"

echo "--- persisted data after pod recreation ---" | tee -a "${OUT_FILE}"
kubectl -n testing exec longhorn-persistence-reader -- cat /data/test.txt 2>&1 | tee -a "${OUT_FILE}"

echo "--- pvc final state ---" | tee -a "${OUT_FILE}"
kubectl -n testing get pvc longhorn-persistence-test -o wide 2>&1 | tee -a "${OUT_FILE}"

echo "--- longhorn volumes ---" | tee -a "${OUT_FILE}"
kubectl -n longhorn-system get volumes.longhorn.io 2>&1 | tee -a "${OUT_FILE}"

echo "--- final pods ---" | tee -a "${OUT_FILE}"
kubectl -n testing get pods -o wide | grep -E 'longhorn-persistence|NAME' 2>&1 | tee -a "${OUT_FILE}"

echo "--- cleanup command ---" | tee -a "${OUT_FILE}"
echo "kubectl -n testing delete pod longhorn-persistence-reader; kubectl -n testing delete pvc longhorn-persistence-test" | tee -a "${OUT_FILE}"
EOF

chmod +x evidencias/scripts/06_longhorn_persistence.sh