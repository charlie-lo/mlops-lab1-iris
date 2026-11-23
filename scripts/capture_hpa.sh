#!/usr/bin/env bash
# Run on the Ubuntu Actions runner after deploying the app and Metrics Server.
set -euo pipefail
: "${RUNNER_TEMP:?set RUNNER_TEMP to a writable directory}"
cd "$(dirname "$0")/.."
record="$RUNNER_TEMP/hpa-snapshots.txt"

# Wait for the first real CPU measurement before collecting the baseline.
for attempt in {1..36}; do
    if kubectl get hpa iris-api -o json | jq -e \
        'any(.status.currentMetrics[]?; .resource.current.averageUtilization != null)' >/dev/null; then
        break
    fi
    sleep 5
done
kubectl top pods -l app=iris-api

# Keep watch output as an independent log in addition to the three screenshots' rows.
kubectl get hpa iris-api --watch > "$RUNNER_TEMP/hpa-watch.txt" &
watch_pid=$!
trap 'kill "$watch_pid" 2>/dev/null || true' EXIT

replicas() {
    kubectl get hpa iris-api -o jsonpath='{.status.currentReplicas}'
}

snapshot() {
    {
        echo "$1   $(date -u '+%H:%M:%S UTC')"
        echo '$ kubectl get hpa iris-api'
        kubectl get hpa iris-api
        echo '$ kubectl get deployment iris-api'
        kubectl get deployment iris-api
        echo
    } | tee -a "$record"
}
[[ "$(replicas)" == 1 ]]
: > "$record"
snapshot 'Before load'

# Use the service DNS name from a client pod so requests reach all ready replicas.
kubectl run iris-load --image=iris-api:v1 --image-pull-policy=Never --restart=Never \
    --command -- sleep 1800
kubectl wait pod/iris-load --for=condition=Ready --timeout=90s
kubectl exec iris-load -- python -c '
import json
from urllib.request import Request, urlopen
url = "http://iris-api/predict"
payload = json.dumps({"instances": [[5.1, 3.5, 1.4, 0.2]]}).encode()
request = Request(url, data=payload, headers={"Content-Type": "application/json"})
with urlopen(request, timeout=15) as response:
    result = json.load(response)
assert result == {"predictions": [0]}, result
print(result)
'
kubectl cp "$(go env GOPATH)/bin/hey" iris-load:/tmp/hey
kubectl exec iris-load -- chmod +x /tmp/hey
kubectl exec iris-load -- /tmp/hey -z 120s -c 50 -m POST -T application/json \
    -d '{"instances":[[5.1,3.5,1.4,0.2]]}' http://iris-api/predict > "$RUNNER_TEMP/hey.txt" &
load_pid=$!
scaled=false
for attempt in {1..36}; do
    if [[ "$(replicas)" -gt 1 ]]; then
        snapshot 'Scale-out observed'
        scaled=true
        break
    fi
    sleep 5
done
[[ "$scaled" == true ]] || { echo 'No scale-out observed'; exit 1; }
wait "$load_pid"
cat "$RUNNER_TEMP/hey.txt"
grep -Eq '\[200\][[:space:]]+[1-9][0-9]* responses' "$RUNNER_TEMP/hey.txt"
kubectl delete pod iris-load --wait=false

# Allow for the default five-minute downscale stabilization window.
scaled=false
for attempt in {1..100}; do
    if [[ "$(replicas)" == 1 ]] && [[ "$(kubectl get deploy iris-api -o jsonpath='{.status.readyReplicas}')" == 1 ]]; then
        snapshot 'After load stopped'
        scaled=true
        break
    fi
    sleep 5
done
[[ "$scaled" == true ]] || { echo 'No scale-in observed'; exit 1; }

# Capture a running X terminal displaying the actual kubectl transcript.
mkdir -p screenshots
export EVIDENCE_TERMINAL_LOG="$record"
xvfb-run -a -s "-screen 0 1600x900x24" bash -euo pipefail <<'CAPTURE'
xterm -title 'Iris Lab 1 - HPA' -fa 'DejaVu Sans Mono' -fs 14 \
    -geometry 108x23+0+0 -bg '#101820' -fg '#eef3f5' \
    -e sh -c 'cat "$EVIDENCE_TERMINAL_LOG"; sleep 30' &
terminal_pid=$!
trap 'kill "$terminal_pid" 2>/dev/null || true' EXIT
window=$(timeout 10 xdotool search --sync --onlyvisible --name 'Iris Lab 1 - HPA' | head -n 1)
sleep 1
import -window "$window" screenshots/hpa-scaling.png
CAPTURE
