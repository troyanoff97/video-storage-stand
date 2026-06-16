#!/usr/bin/env bash
# Focused chaos on volume1 using put_to_volume1 (replication 000, volume2 stopped).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

RESULTS="${ROOT_DIR}/chaos-volume1-results.txt"
TEST_FILE="/tmp/volume1-chaos-fragment.bin"
CAMERA="chaos-v1"

log() { echo "$@" | tee -a "$RESULTS"; }

try_put_v1() {
  local label="$1"
  local expect_fail="${2:-0}"
  set +e
  local out code
  out=$(./scripts/put_to_volume1.sh "$TEST_FILE" "${CAMERA}-${label}" 2>&1)
  code=$?
  log "PUT-v1 [${label}]: exit=${code} (expect_fail=${expect_fail})"
  log "$out"
  if [ "$expect_fail" = "1" ] && [ "$code" -eq 0 ]; then
    log "UNEXPECTED: PUT succeeded during fault scenario ${label}"
  elif [ "$expect_fail" = "0" ] && [ "$code" -ne 0 ]; then
    log "UNEXPECTED: PUT failed during healthy scenario ${label}"
  fi
  set -e
}

: > "$RESULTS"
log "Volume1 chaos run: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
log "Stopping volume2 so replication=000 assign targets volume1 only"
compose stop volume2 || true
sleep 3

# 384K payload — does not fit after disk_full leaves ~512K on 512M tmpfs.
dd if=/dev/urandom of="$TEST_FILE" bs=384K count=1 status=none

log "=== baseline put_to_volume1 ==="
try_put_v1 baseline 0

log "=== disk full volume1 ==="
./scripts/chaos/disk_full.sh volume1 || true
try_put_v1 disk-full 1
compose logs volume1 --tail=15 2>&1 | tee -a "$RESULTS"
./scripts/chaos/reset_volumes.sh volume1 || true
sleep 10

log "=== disk read-only volume1 ==="
./scripts/chaos/disk_readonly.sh volume1 || true
try_put_v1 disk-readonly 1
compose logs volume1 --tail=15 2>&1 | tee -a "$RESULTS"
./scripts/chaos/reset_volumes.sh volume1 || true

compose up -d volume2 || true
sleep 5

log "Done: ${RESULTS}"
