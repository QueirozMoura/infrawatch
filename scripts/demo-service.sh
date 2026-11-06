#!/usr/bin/env bash
# Control ONLY the InfraWatch demo service (used to simulate an outage).
# It never touches Prometheus, Grafana or Node Exporter.
#
# Usage: scripts/demo-service.sh {start|stop|restore|status}
set -euo pipefail

SERVICE="demo-service"
CONTAINER="infrawatch-demo-service"
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if command -v podman >/dev/null 2>&1; then
  ENGINE=podman
elif command -v docker >/dev/null 2>&1; then
  ENGINE=docker
else
  echo "error: neither podman nor docker found" >&2
  exit 1
fi

is_running() {
  [ "$("$ENGINE" inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo false)" = "true" ]
}

case "${1:-}" in
  start | restore)
    if is_running; then
      echo "$SERVICE already running"
    else
      # --no-deps: start only this service, leave the rest of the stack alone.
      "$ENGINE" compose up -d --no-deps "$SERVICE" >/dev/null 2>&1
      echo "$SERVICE started"
    fi
    ;;
  stop)
    if is_running; then
      "$ENGINE" stop "$CONTAINER" >/dev/null
      echo "$SERVICE stopped"
    else
      echo "$SERVICE already stopped"
    fi
    ;;
  status)
    if is_running; then echo "$SERVICE: running"; else echo "$SERVICE: stopped"; fi
    ;;
  *)
    echo "usage: $0 {start|stop|restore|status}" >&2
    exit 2
    ;;
esac
