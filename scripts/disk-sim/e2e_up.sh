#!/usr/bin/env bash
# Start E2E disk-sim overlay: recreate volume1 with host loopback bind mounts.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

E2E_COMPOSE_FILES=(docker-compose.yml docker-compose.chaos.yml docker-compose.disk-sim.yml)

require_confirm
load_state

is_mounted "$MNT1" || die "stor1 not mounted: $MNT1"
is_mounted "$MNT2" || die "stor2 not mounted: $MNT2"

assert_stand_project_matches_port8080
export DISK_SIM_ROOT

sim_log "Recreating volume1 with disk-sim bind mounts (project=$(resolve_compose_project))..."
recreate_compose_service "$ROOT_DIR" "${E2E_COMPOSE_FILES[@]}" volume1

verify_volume1_disk_sim_binds "$ROOT_DIR" "${E2E_COMPOSE_FILES[@]}"

sim_log "Waiting for volume1 health..."
for _ in $(seq 1 60); do
  if curl -fsS http://localhost:8080/healthz >/dev/null 2>&1; then
    sim_log "volume1 healthy on :8080"
    exit 0
  fi
  sleep 2
done
die "volume1 did not become healthy within 120s"
