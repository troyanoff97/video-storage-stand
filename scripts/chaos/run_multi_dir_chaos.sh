#!/usr/bin/env bash
# Per-dir disk health via production write path (sideweed → S3 Gateway).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

source "$(dirname "${BASH_SOURCE[0]}")/_multi_dir.sh"

RESULTS="${ROOT_DIR}/chaos-multi-dir-results.txt"
TEST_FILE="/tmp/multi-dir-chaos-fragment.bin"
CAMERA="chaos-multi-dir"
FAILURES=0

log() { echo "$@" | tee -a "$RESULTS"; }
fail() { log "FAIL: $1"; FAILURES=$((FAILURES + 1)); }

try_put_s3() {
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

check_logs() {
  local label="$1"
  shift
  local logs
  logs=$(compose logs volume1 --tail=150 2>&1)
  for pattern in "$@"; do
    if echo "$logs" | grep -qE "$pattern"; then
      log "LOG OK [${label}]: matched /${pattern}/"
      return 0
    fi
  done
  fail "expected one of [${label}]: $*"
  log "$logs"
}

check_sideweed_put() {
  local label="$1"
  if compose logs sideweed --tail=30 2>&1 | grep -qE '"method":"PUT".*s3:8333|"host":"http://s3:8333".*"method":"PUT"'; then
    log "LOG OK [${label}]: sideweed proxied PUT to S3 Gateway"
  else
    compose logs sideweed --tail=10 2>&1 | tee -a "$RESULTS"
    fail "sideweed did not proxy PUT to s3:8333 for ${label}"
  fi
}

probe_data1_write() {
  compose exec volume1 sh -c '
    dat=$(ls /data1/*.dat 2>/dev/null | head -1)
    if [ -n "$dat" ]; then echo probe >> "$dat" 2>&1 || true; fi
  ' 2>/dev/null || true
}

reset_volume1_fresh() {
  log "Reset volume1 (tmpfs wipe) for clean volume slots..."
  compose restart volume1 2>/dev/null || true
  sleep 15
  curl -sf http://localhost:8080/healthz >/dev/null || sleep 10
}

: > "$RESULTS"
log "Multi-dir chaos (S3 production path): $(date -u +"%Y-%m-%dT%H:%M:%SZ")"

compose up -d --build
./scripts/wait-healthy.sh 2>&1 | tee -a "$RESULTS"

compose stop volume2 || true
sleep 3

dd if=/dev/urandom of="$TEST_FILE" bs=32K count=1 status=none

log "=== baseline (both dirs healthy) ==="
try_put_s3 baseline 0
check_sideweed_put baseline

log "=== fill /data1 only ==="
reset_volume1_fresh
try_put_s3 pre-fault-fill 0
./scripts/chaos/disk_fail_data1.sh fill volume1 || true
sleep 8
try_put_s3 after-data1-full 0
check_sideweed_put after-data1-full
check_logs data1-full-failover \
  "marked unhealthy.*data1" \
  "In dir /data2 adds volume"
./scripts/chaos/reset_multi_dir_data1.sh volume1 || true
sleep 8
reset_volume1_fresh

log "=== remount /data1 read-only ==="
try_put_s3 pre-fault-ro 0
./scripts/chaos/disk_fail_data1.sh readonly volume1 || true
sleep 8
probe_data1_write
sleep 5
try_put_s3 after-data1-readonly 0
check_sideweed_put after-data1-readonly
check_logs data1-ro-failover \
  "marked unhealthy.*data1" \
  "In dir /data2 adds volume"
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
