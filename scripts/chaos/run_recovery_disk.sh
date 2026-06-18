#!/usr/bin/env bash
# disk full on /vol → soft reset → GET baseline on loop-backed persistent store.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

source "$(dirname "${BASH_SOURCE[0]}")/_recovery_disk.sh"

RESULTS="${ROOT_DIR}/chaos-recovery-disk-results.txt"
TEST_FILE="/tmp/chaos-recovery-disk-fragment.bin"
CAMERA="chaos-recovery-disk"
BASELINE_CAMERA=""
BASELINE_FRAGMENT=""
FAILURES=0

log() { echo "$@" | tee -a "$RESULTS"; }

fail() {
  log "FAIL: $1"
  FAILURES=$((FAILURES + 1))
}

try_put_v1() {
  local label="$1"
  local expect_fail="${2:-0}"
  set +e
  local out code
  out=$(./scripts/put_fragment.sh "$TEST_FILE" "${CAMERA}-${label}" 2>&1)
  code=$?
  log "PUT-v1 [${label}]: exit=${code} (expect_fail=${expect_fail})"
  log "$out"
  if [ "$expect_fail" = "1" ] && [ "$code" -eq 0 ]; then
    fail "PUT succeeded during fault ${label}"
  elif [ "$expect_fail" = "0" ] && [ "$code" -ne 0 ]; then
    fail "PUT failed when healthy ${label}"
  fi
  set -e
}

try_get_baseline() {
  local label="$1"
  local expect_fail="${2:-0}"
  if [ -z "$BASELINE_FRAGMENT" ] || [ -z "$BASELINE_CAMERA" ]; then
    fail "missing baseline for GET ${label}"
    return
  fi
  set +e
  local out code
  out=$(./scripts/get_fragment.sh "$BASELINE_CAMERA" "$BASELINE_FRAGMENT" "/tmp/recovery-disk-get-${label}.bin" 2>&1)
  code=$?
  log "GET [${label}] camera=${BASELINE_CAMERA} fragment=${BASELINE_FRAGMENT}: exit=${code} (expect_fail=${expect_fail})"
  log "$out"
  if [ "$expect_fail" = "1" ] && [ "$code" -eq 0 ]; then
    fail "GET succeeded during fault ${label}"
  elif [ "$expect_fail" = "0" ] && [ "$code" -ne 0 ]; then
    fail "GET failed when healthy ${label}"
  fi
  set -e
}

: > "$RESULTS"
log "Recovery disk (loop /vol, disk full → reset → GET) run: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"

"$(dirname "${BASH_SOURCE[0]}")/prepare_recovery_disk.sh" volume1 2>&1 | tee -a "$RESULTS"

log "Stopping volume2 so replication=000 targets volume1 only"
compose stop volume2 || true
sleep 3

dd if=/dev/urandom of="$TEST_FILE" bs=64K count=1 status=none

log "=== baseline ==="
baseline_out=$(./scripts/put_fragment.sh "$TEST_FILE" "${CAMERA}-baseline" 2>&1) || true
log "$baseline_out"
BASELINE_FRAGMENT=$(echo "$baseline_out" | awk '/fragment_id:/ {print $2}')
BASELINE_CAMERA=$(echo "$baseline_out" | awk '/camera_id:/ {print $2}')
if [ -z "$BASELINE_FRAGMENT" ]; then
  fail "baseline PUT did not produce fragment_id"
fi

log "=== fault: disk full on /vol ==="
"$(dirname "${BASH_SOURCE[0]}")/disk_full_named.sh" volume1 2>&1 | tee -a "$RESULTS" || true
sleep 3
try_put_v1 fault-full 1
try_get_baseline during-fault 0

log "=== soft reset (remove fill) ==="
"$(dirname "${BASH_SOURCE[0]}")/reset_volumes_soft_named.sh" volume1 2>&1 | tee -a "$RESULTS" || true
sleep 5

try_get_baseline after-reset 0
try_put_v1 after-reset 0

compose up -d volume2 || true
sleep 5

log ""
if [ "$FAILURES" -eq 0 ]; then
  log "Recovery disk scenario PASSED. Results: ${RESULTS}"
  exit 0
fi
log "Recovery disk scenario FAILED (${FAILURES} checks). Results: ${RESULTS}"
exit 1
