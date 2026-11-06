#!/usr/bin/env bash
# Controlled outage test: stops the demo service, then checks that the
# TargetDown alert goes inactive -> pending -> firing, and that it clears
# after the service is restored. Only the demo service is stopped.
#
# Usage: scripts/test-target-down.sh
set -euo pipefail

PROM="${PROMETHEUS_URL:-http://127.0.0.1:9090}"
JOB="demo-service"
POLL=5            # seconds between checks
FIRE_TIMEOUT=180  # max seconds to wait for pending/firing
CLEAR_TIMEOUT=120 # max seconds to wait for recovery
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START=$SECONDS

log() { printf '[%3ds] %s\n' $((SECONDS - START)) "$*"; }

# Prints: <up value or none> <alert state: inactive|pending|firing>
snapshot() {
  python3 - "$PROM" "$JOB" <<'PY'
import json, sys, urllib.parse, urllib.request
prom, job = sys.argv[1:3]
def get(path):
    with urllib.request.urlopen(prom + path, timeout=5) as r:
        return json.load(r)
q = urllib.parse.quote(f'up{{job="{job}"}}')
res = get(f"/api/v1/query?query={q}")["data"]["result"]
up = res[0]["value"][1] if res else "none"
state = "inactive"
for a in get("/api/v1/alerts")["data"]["alerts"]:
    l = a["labels"]
    if l.get("alertname") == "TargetDown" and l.get("job") == job:
        state = a["state"]
print(up, state)
PY
}

wait_for() { # <description> <timeout> <expected up value|any> <expected alert state>
  local desc=$1 timeout=$2 want_up=$3 want_state=$4
  local end=$((SECONDS + timeout)) last=""
  while [ $SECONDS -lt $end ]; do
    read -r up state < <(snapshot)
    cur="up=$up alert=$state"
    [ "$cur" != "$last" ] && { log "$cur"; last=$cur; }
    if [ "$state" = "$want_state" ] && { [ "$want_up" = any ] || [ "$up" = "$want_up" ]; }; then
      return 0
    fi
    sleep "$POLL"
  done
  log "TIMEOUT waiting for: $desc"
  return 1
}

curl -sf "$PROM/-/ready" >/dev/null || { echo "Prometheus is not ready at $PROM" >&2; exit 1; }

log "1/5 baseline: demo service must be running and target UP"
"$HERE/demo-service.sh" start
wait_for "target up, alert inactive" 60 1 inactive

restore() { "$HERE/demo-service.sh" restore >/dev/null 2>&1 || true; }
trap restore EXIT # always bring the demo service back, even on failure/Ctrl-C

log "2/5 stopping the demo service"
"$HERE/demo-service.sh" stop

log "3/5 waiting for TargetDown: pending, then firing (rule uses for: 1m)"
wait_for "pending" "$FIRE_TIMEOUT" 0 pending
wait_for "firing" "$FIRE_TIMEOUT" 0 firing

log "4/5 restoring the demo service"
"$HERE/demo-service.sh" restore

log "5/5 waiting for recovery: target UP and alert cleared"
wait_for "recovery" "$CLEAR_TIMEOUT" 1 inactive

log "RESULT: OK - inactive -> pending -> firing -> recovered"
