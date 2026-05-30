#!/bin/bash
# HPA demo: generate CPU load → scale 2→5 pods → stop load → scale back to 2.
# Run on the k3s EC2 node after: export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
set -euo pipefail

API_URL="${API_URL:-http://127.0.0.1:30080}"
API_KEY="${API_KEY:-datavault-dev-key}"
LOAD_WORKERS="${LOAD_WORKERS:-24}"
LOAD_DURATION="${LOAD_DURATION:-300}"
NAMESPACE="${NAMESPACE:-default}"

echo "=== HPA stress demo (DataVault API) ==="
echo "API: ${API_URL}  workers: ${LOAD_WORKERS}  duration: ${LOAD_DURATION}s"
echo

preflight() {
  echo "--- Preflight ---"
  if ! kubectl top pods -n "${NAMESPACE}" -l app=datavault-api &>/dev/null; then
    echo "ERROR: metrics-server not ready. Check: kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server"
    exit 1
  fi
  if ! kubectl get hpa datavault-api-hpa -n "${NAMESPACE}" &>/dev/null; then
    echo "ERROR: HPA not found. Run: kubectl apply -f k8s/hpa.yaml"
    exit 1
  fi
  curl -sf "${API_URL}/health" >/dev/null || {
    echo "ERROR: API not reachable at ${API_URL}/health"
    exit 1
  }
  echo "Baseline:"
  kubectl get hpa datavault-api-hpa -n "${NAMESPACE}"
  kubectl get pods -n "${NAMESPACE}" -l app=datavault-api
  kubectl top pods -n "${NAMESPACE}" -l app=datavault-api || true
  echo
}

load_worker() {
  local id="$1"
  while true; do
    curl -s -o /dev/null -H "x-api-key: ${API_KEY}" "${API_URL}/api/audit" || true
    curl -s -o /dev/null -H "x-api-key: ${API_KEY}" -H "Content-Type: application/json" \
      -X POST "${API_URL}/api/audit" \
      -d "{\"actor\":\"hpa.load${id}@datavault.io\",\"action\":\"LOAD_TEST\",\"resource\":\"hpa-demo\",\"outcome\":\"success\",\"detail\":\"HPA stress worker ${id}\",\"client_id\":\"tier1-bank-uk\"}" || true
    curl -s -o /dev/null -H "x-api-key: ${API_KEY}" "${API_URL}/api/clients" || true
  done
}

start_load() {
  echo "--- Phase 1: generating load (target: HPA scales toward maxReplicas=5) ---"
  echo "Open another terminal and run:  kubectl get hpa -w"
  echo "Or:                              kubectl get pods -l app=datavault-api -w"
  echo
  PIDS=()
  for i in $(seq 1 "${LOAD_WORKERS}"); do
    load_worker "${i}" &
    PIDS+=($!)
  done
  END=$((SECONDS + LOAD_DURATION))
  while [[ ${SECONDS} -lt ${END} ]]; do
    kubectl get hpa datavault-api-hpa -n "${NAMESPACE}" --no-headers
    kubectl top pods -n "${NAMESPACE}" -l app=datavault-api 2>/dev/null | head -8 || true
    echo "---"
    sleep 15
  done
  echo "Stopping load workers..."
  for pid in "${PIDS[@]}"; do
    kill "${pid}" 2>/dev/null || true
  done
  wait 2>/dev/null || true
  echo
}

watch_scale_down() {
  echo "--- Phase 2: load stopped — watch scale-down (often 3–5+ minutes) ---"
  echo "HPA waits before reducing replicas (stabilization window)."
  END=$((SECONDS + 420))
  while [[ ${SECONDS} -lt ${END} ]]; do
    kubectl get hpa datavault-api-hpa -n "${NAMESPACE}" --no-headers
    kubectl get pods -n "${NAMESPACE}" -l app=datavault-api --no-headers | wc -l | xargs echo "pod count:"
    sleep 20
    REPLICAS=$(kubectl get hpa datavault-api-hpa -n "${NAMESPACE}" -o jsonpath='{.status.currentReplicas}')
    if [[ "${REPLICAS}" == "2" ]]; then
      echo "Scaled back to minReplicas=2."
      break
    fi
  done
  echo
  echo "Final state:"
  kubectl get hpa datavault-api-hpa -n "${NAMESPACE}"
  kubectl get pods -n "${NAMESPACE}" -l app=datavault-api
}

preflight
start_load
watch_scale_down

echo "=== Demo complete ==="
echo "Compare to old DataVault process: manual SSH to bare-metal servers, fixed capacity,"
echo "no automatic scale-down — vs Kubernetes HPA driven by metrics-server + Git-declared limits."
