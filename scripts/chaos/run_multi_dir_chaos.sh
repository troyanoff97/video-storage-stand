#!/usr/bin/env bash
# Prove per-dir failover: fault /data1, PUT still succeeds via /data2 on volume1.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

source "$(dirname "${BASH_SOURCE[0]}")/_multi_dir.sh"

RESULTS="${ROOT_DIR}/chaos-multi-dir-results.txt"
TEST_FILE="/tmp/multi-dir-chaos-fragment.bin"
CAMERA="chaos-multi-dir"
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
  out=$(./scripts/put_to_volume1.sh "$TEST_FILE" "${CAMERA}-${label}" 2>&1)
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

check_logs() {
  local label="$1"
  shift
  local logs
  logs=$(compose logs volume1 --tail=120 2>&1)
  for pattern in "$@"; do
    if echo "$logs" | grep -qE "$pattern"; then
      log "LOG OK [${label}]: matched /${pattern}/"
      return 0
    fi
  done
  fail "expected one of [${label}]: $*"
  log "$logs"
}

probe_data1_write() {
  compose exec volume1 sh -c '
    dat=$(ls /data1/*.dat 2>/dev/null | head -1)
    if [ -n "$dat" ]; then
      echo probe >> "$dat" 2>&1 || true
    fi
  ' 2>/dev/null || true
}

: > "$RESULTS"
log "Multi-dir chaos run: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"

log "Starting stack with multi-dir volume1..."
compose up -d --build
./scripts/wait-healthy.sh 2>&1 | tee -a "$RESULTS"

log "Stopping volume2 so replication=000 assign targets volume1 only"
compose stop volume2 || true
sleep 3

dd if=/dev/urandom of="$TEST_FILE" bs=64K count=1 status=none

log "=== baseline (both dirs healthy) ==="
try_put_v1 baseline 0

log "=== fill /data1 only ==="
./scripts/chaos/disk_fail_data1.sh fill volume1 || true
sleep 3
try_put_v1 after-data1-full 0
check_logs data1-full-failover \
  "marked unhealthy.*data1" \
  "dir /data1 disk free" \
  "In dir /data2 adds volume"
compose logs volume1 --tail=20 2>&1 | tee -a "$RESULTS"
./scripts/chaos/reset_multi_dir_data1.sh volume1 || true
sleep 5

log "=== remount /data1 read-only ==="
./scripts/chaos/disk_fail_data1.sh readonly volume1 || true
sleep 2
probe_data1_write
sleep 2
try_put_v1 after-data1-readonly 0
check_logs data1-ro-failover \
  "marked unhealthy.*data1" \
  "read-only file system" \
  "In dir /data2 adds volume"
compose logs volume1 --tail=20 2>&1 | tee -a "$RESULTS"
./scripts/chaos/reset_multi_dir_data1.sh volume1 || true
sleep 65
check_logs data1-recovered \
  "recovered and is healthy again.*data1" \
  "Folder /data1 Permission"

compose up -d volume2 || true
sleep 5

log ""
if [ "$FAILURES" -eq 0 ]; then
  log "Multi-dir chaos PASSED. Results: ${RESULTS}"
  exit 0
fi
log "Multi-dir chaos FAILED (${FAILURES} checks). Results: ${RESULTS}"
exit 1
