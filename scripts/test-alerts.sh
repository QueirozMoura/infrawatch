#!/usr/bin/env bash
# Run the Prometheus alert rule checks and unit tests.
#
# Uses a local `promtool` if installed, otherwise the pinned Prometheus image
# through podman or docker. Nothing in the running stack is touched: the
# container is short-lived, read-only on the repo, and uses only synthetic data.
#
# Usage: scripts/test-alerts.sh
set -euo pipefail

IMAGE="docker.io/prom/prometheus:v3.5.0"
cd "$(dirname "${BASH_SOURCE[0]}")/../prometheus"

if command -v promtool >/dev/null 2>&1; then
  promtool() { command promtool "$@"; }
else
  if command -v podman >/dev/null 2>&1; then ENGINE=podman
  elif command -v docker >/dev/null 2>&1; then ENGINE=docker
  else echo "error: need promtool, podman or docker" >&2; exit 1; fi
  promtool() {
    "$ENGINE" run --rm --entrypoint promtool -v "$PWD:/etc/prometheus:ro,z" -w /etc/prometheus "$IMAGE" "$@"
  }
fi

echo "== promtool check rules =="
promtool check rules alerts.yml
echo
echo "== promtool test rules =="
promtool test rules tests/alerts_test.yml
