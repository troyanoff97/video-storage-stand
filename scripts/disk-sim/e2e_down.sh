#!/usr/bin/env bash
# Restore volume1 to default chaos overlay (no host bind mounts).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

CHAOS_COMPOSE_FILES=(docker-compose.yml docker-compose.chaos.yml)

require_confirm
pin_compose_project_from_running_stand
assert_stand_project_matches_port8080

sim_log "Restoring volume1 to chaos tmpfs overlay (project=$(resolve_compose_project))..."
recreate_compose_service "$ROOT_DIR" "${CHAOS_COMPOSE_FILES[@]}" volume1

sim_log "Waiting for volume1 health..."
for _ in $(seq 1 60); do
  if curl -fsS http://localhost:8080/healthz >/dev/null 2>&1; then
    sim_log "volume1 restored and healthy"
    exit 0
  fi
  sleep 2
done
die "volume1 did not become healthy after restore"
