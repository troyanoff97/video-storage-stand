#!/usr/bin/env bash
# Chaos on volume1 faults using production S3 write path (volume2 stopped to pin node).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

RESULTS="${ROOT_DIR}/chaos-volume1-results.txt"
TEST_FILE="/tmp/volume1-chaos-fragment.bin"
CAMERA="chaos-volume1"
FAILURES=0

log() { echo "$@" | tee -a "$RESULTS"; }
fail() { log "FAIL: $1"; FAILURES=$((FAILURES + 1)); }

try_put() {
  local label="$1"
  local expect_fail="${2:-0}"
  set +e
  local out code
  out=$(./scripts/put_fragment.sh "$TEST_FILE" "${CAMERA}-${label}" 2>&1)
  code=$?
  log "PUT-S3 [${label}]: exit=${code} (expect_fail=${expect_fail})"
  log "$out"
  if [ "$expect_fail" = "1" ] && [ "$code" -eq 0 ]; then
    fail "PUT succeeded during fault ${label}"
  elif [ "$expect_fail" = "0" ] && [ "$code" -ne 0 ]; then
    fail "PUT failed when healthy ${label}"
  fi
  set -e
}

: > "$RESULTS"
log "Volume1 chaos (S3 path): $(date -u +"%Y-%m-%dT%H:%M:%SZ")"

compose up -d --build
./scripts/wait-healthy.sh 2>&1 | tee -a "$RESULTS"
compose stop volume2 || true
sleep 3

dd if=/dev/urandom of="$TEST_FILE" bs=64K count=1 status=none

log "=== baseline ==="
try_put baseline 0

log "=== disk full ==="
./scripts/chaos/disk_full.sh volume1 || true
try_put disk-full 1
./scripts/chaos/reset_volumes.sh volume1 || true
sleep 8

log "=== disk read-only ==="
./scripts/chaos/disk_readonly.sh volume1 || true
try_put disk-readonly 1
./scripts/chaos/reset_volumes.sh volume1 || true

compose up -d volume2 || true

if [ "$FAILURES" -eq 0 ]; then
  log "Volume1 chaos PASSED"
  exit 0
fi
log "Volume1 chaos FAILED (${FAILURES})"
exit 1
