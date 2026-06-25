#!/usr/bin/env bash
# Restore volume1 to default chaos overlay (no host bind mounts).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_confirm

COMPOSE=(docker compose -f "$ROOT_DIR/docker-compose.yml" -f "$ROOT_DIR/docker-compose.chaos.yml")

sim_log "Restoring volume1 to chaos tmpfs overlay (no disk-sim binds)..."
"${COMPOSE[@]}" up -d --no-deps --force-recreate volume1

sim_log "Waiting for volume1 health..."
for _ in $(seq 1 60); do
  if curl -fsS http://localhost:8080/healthz >/dev/null 2>&1; then
    sim_log "volume1 restored and healthy"
    exit 0
  fi
  sleep 2
done
die "volume1 did not become healthy after restore"
