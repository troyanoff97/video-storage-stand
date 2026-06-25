#!/usr/bin/env bash
# Start E2E disk-sim overlay: recreate volume1 with host loopback bind mounts.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_confirm
load_state

is_mounted "$MNT1" || die "stor1 not mounted: $MNT1"
is_mounted "$MNT2" || die "stor2 not mounted: $MNT2"

COMPOSE=(docker compose -f "$ROOT_DIR/docker-compose.yml" -f "$ROOT_DIR/docker-compose.chaos.yml" \
  -f "$ROOT_DIR/docker-compose.disk-sim.yml")

sim_log "Recreating volume1 with disk-sim bind mounts (stack otherwise unchanged)..."
export DISK_SIM_ROOT
"${COMPOSE[@]}" up -d --no-deps --force-recreate volume1

sim_log "Waiting for volume1 health..."
for _ in $(seq 1 60); do
  if curl -fsS http://localhost:8080/healthz >/dev/null 2>&1; then
    sim_log "volume1 healthy on :8080"
    exit 0
  fi
  sleep 2
done
die "volume1 did not become healthy within 120s"
