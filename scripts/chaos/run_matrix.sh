#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

RESULTS="${ROOT_DIR}/chaos-matrix-results.txt"
TEST_FILE="/tmp/chaos-matrix-fragment.bin"
CAMERA="chaos-matrix"
BASELINE_FRAGMENT=""
FAILURES=0
WARNS=0
SKIPS=0
PASSES=0

SUMMARY_PASS=()
SUMMARY_WARN=()
SUMMARY_SKIP=()
SUMMARY_FAIL=()

log() { echo "$@" | tee -a "$RESULTS"; }
section() { log ""; log "=== $1 ==="; }

record_pass() {
  PASSES=$((PASSES + 1))
  SUMMARY_PASS+=("$1")
  log "PASS: $1"
}

record_warn() {
  WARNS=$((WARNS + 1))
  SUMMARY_WARN+=("$1")
  log "WARN: $1"
}

record_skip() {
  SKIPS=$((SKIPS + 1))
  SUMMARY_SKIP+=("$1")
  log "SKIP: $1"
}

record_fail() {
  FAILURES=$((FAILURES + 1))
  SUMMARY_FAIL+=("$1")
  log "FAIL: $1"
}

try_put() {
  local label="$1"
  local expect="$2" # pass | fail
  set +e
  local out code
  out=$(./scripts/put_fragment.sh "$TEST_FILE" "${CAMERA}-${label}" 2>&1)
  code=$?
  log "PUT-S3 [${label}]: exit=${code} (expect=${expect})"
  log "$out"
  if [ "$expect" = "fail" ]; then
    if [ "$code" -eq 0 ]; then
      record_fail "PUT [${label}]: succeeded but production path should reject new write"
    else
      record_pass "PUT [${label}]: failed as expected"
    fi
  elif [ "$expect" = "pass" ]; then
    if [ "$code" -eq 0 ]; then
      record_pass "PUT [${label}]: succeeded as expected"
    else
      record_fail "PUT [${label}]: failed but healthy path should accept write"
    fi
  fi
  set -e
}

try_get() {
  local label="$1"
  local fid="$2"
  local expect="$3" # pass | fail
  set +e
  local out code
  out=$(./scripts/get_fragment.sh "${CAMERA}-baseline" "$fid" "/tmp/chaos-get-${label}.bin" 2>&1)
  code=$?
  log "GET-S3 [${label}] fragment=${fid}: exit=${code} (expect=${expect})"
  log "$out"
  if [ "$expect" = "fail" ]; then
    if [ "$code" -eq 0 ]; then
      record_fail "GET [${label}]: succeeded but read path should be unavailable"
    else
      record_pass "GET [${label}]: failed as expected"
    fi
  elif [ "$expect" = "pass" ]; then
    if [ "$code" -eq 0 ]; then
      record_pass "GET [${label}]: succeeded as expected"
    else
      record_fail "GET [${label}]: failed but read path should serve existing object"
    fi
  fi
  set -e
}

# GET may pass or fail — both acceptable (e.g. master down, existing object).
try_get_optional() {
  local label="$1"
  local fid="$2"
  set +e
  local out code
  out=$(./scripts/get_fragment.sh "${CAMERA}-baseline" "$fid" "/tmp/chaos-get-${label}.bin" 2>&1)
  code=$?
  log "GET-S3 [${label}] fragment=${fid}: exit=${code} (expect=optional)"
  log "$out"
  if [ "$code" -eq 0 ]; then
    record_pass "GET [${label}]: succeeded (acceptable — existing object via read path)"
  else
    record_pass "GET [${label}]: failed (also acceptable during fault)"
  fi
  set -e
}

try_master_assign() {
  local label="$1"
  local expect_http="${2:-200}"
  set +e
  local out http
  out=$(REPLICATION=000 ./scripts/debug/master_assign.sh 2>&1)
  http=$(echo "$out" | awk -F: '/HTTP_CODE:/ {print $2}')
  log "MASTER-ASSIGN [DEBUG] [${label}]: http=${http:-?} (expect ${expect_http})"
  log "$out"
  if [ "$http" = "$expect_http" ]; then
    record_pass "MASTER-ASSIGN [${label}]: http=${http}"
  else
    record_fail "MASTER-ASSIGN [${label}]: http=${http:-?} != ${expect_http}"
  fi
  set -e
}

# Returns 0 when /data on volume1 accepts writes (fault not active).
volume1_data_writable() {
  compose exec volume1 sh -c 'touch /data/.fault-probe 2>/dev/null' >/dev/null 2>&1
}

apply_volume1_fault() {
  local label="$1"
  shift
  set +e
  local out code
  out=$("$@" 2>&1)
  code=$?
  log "$out"
  if [ "$code" -ne 0 ]; then
    record_warn "Fault [${label}]: script exited ${code} (tmpfs/remount limitation)"
    return 1
  fi
  if volume1_data_writable; then
    compose exec volume1 rm -f /data/.fault-probe 2>/dev/null || true
    record_warn "Fault [${label}]: script OK but /data still writable"
    return 1
  fi
  record_pass "Fault [${label}]: applied (/data not writable)"
  return 0
}

try_put_with_fault() {
  local label="$1"
  shift
  if apply_volume1_fault "$label" "$@"; then
    try_put "$label" fail
  else
    record_skip "PUT [${label}]: fault not applied — cannot assert production behavior"
  fi
}

capture_logs() {
  local svc="$1"
  log "--- logs ${svc} (last 15) ---"
  compose logs "$svc" --tail=15 2>&1 | tee -a "$RESULTS"
}

ensure_healthy() {
  compose up -d master volume1 volume2 filer s3 sideweed sideweed-read haproxy 2>/dev/null || true
  sleep 12
  ./scripts/wait-healthy.sh 2>&1 | tail -8 | tee -a "$RESULTS" || true
}

recover_all() {
  ensure_healthy
  ./scripts/chaos/reset_volumes.sh volume1 2>/dev/null || true
  sleep 8
}

pin_volume1_only() {
  compose stop volume2 2>/dev/null || true
  sleep 3
}

unpin_volume1() {
  compose up -d volume2 2>/dev/null || true
  sleep 5
}

volume2_running() {
  compose ps volume2 2>/dev/null | grep -qE 'running|Up'
}

print_summary() {
  section "Matrix summary"
  log "Totals: PASS=${PASSES} WARN=${WARNS} SKIP=${SKIPS} FAIL=${FAILURES}"
  if [ "${#SUMMARY_PASS[@]}" -gt 0 ]; then
    log ""
    log "PASS:"
    for item in "${SUMMARY_PASS[@]}"; do
      log "  - ${item}"
    done
  fi
  if [ "${#SUMMARY_WARN[@]}" -gt 0 ]; then
    log ""
    log "WARN:"
    for item in "${SUMMARY_WARN[@]}"; do
      log "  - ${item}"
    done
  fi
  if [ "${#SUMMARY_SKIP[@]}" -gt 0 ]; then
    log ""
    log "SKIP:"
    for item in "${SUMMARY_SKIP[@]}"; do
      log "  - ${item}"
    done
  fi
  if [ "${#SUMMARY_FAIL[@]}" -gt 0 ]; then
    log ""
    log "FAIL:"
    for item in "${SUMMARY_FAIL[@]}"; do
      log "  - ${item}"
    done
  fi
}

: > "$RESULTS"
log "Chaos matrix run (production S3 path): $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
log "WRITE: sideweed:8880 → S3:8333 → filer → master → volumes"
log "READ:  HAProxy:8882 → sideweed-read → S3:8333"

compose up -d --build
./scripts/wait-healthy.sh 2>&1 | tee -a "$RESULTS"

dd if=/dev/urandom of="$TEST_FILE" bs=512K count=1 status=none

section "0 baseline (healthy stack)"
set +e
baseline_out=$(./scripts/put_fragment.sh "$TEST_FILE" "${CAMERA}-baseline" 2>&1)
baseline_code=$?
set -e
log "PUT-S3 [baseline]: exit=${baseline_code}"
log "$baseline_out"
BASELINE_FRAGMENT=$(echo "$baseline_out" | awk '/fragment_id:/ {print $2}')
if [ -z "$BASELINE_FRAGMENT" ]; then
  record_fail "baseline PUT did not produce fragment_id"
else
  record_pass "baseline PUT produced fragment_id=${BASELINE_FRAGMENT}"
  try_get baseline "$BASELINE_FRAGMENT" pass
fi
capture_logs sideweed

section "1 volume1 down (volume2 up, replication=000)"
compose stop volume1
sleep 6
if volume2_running; then
  try_put volume-down pass
  try_get volume-down "$BASELINE_FRAGMENT" pass
else
  record_skip "volume1 down: volume2 not running — cannot test failover write"
fi
capture_logs sideweed
compose start volume1
sleep 8
ensure_healthy

pin_volume1_only
section "2 mount unavailable (volume1 only, volume2 stopped)"
sleep 3
try_put_with_fault mount-unavailable ./scripts/chaos/mount_unavailable.sh volume1
capture_logs volume1
./scripts/chaos/reset_volumes.sh volume1 || true
sleep 8

section "3 disk full (volume1 only, volume2 stopped)"
try_put_with_fault disk-full ./scripts/chaos/disk_full.sh volume1
capture_logs volume1
./scripts/chaos/reset_volumes.sh volume1 || true
sleep 8

section "4 disk read-only (volume1 only, volume2 stopped)"
if apply_volume1_fault disk-readonly ./scripts/chaos/disk_readonly.sh volume1; then
  try_put disk-readonly fail
else
  record_skip "PUT [disk-readonly]: fault not applied — cannot assert production behavior"
fi
compose up -d volume2 2>/dev/null || true
sleep 10
./scripts/wait-healthy.sh 2>&1 | tail -3 | tee -a "$RESULTS" || true
try_get disk-readonly "$BASELINE_FRAGMENT" pass
capture_logs volume1
./scripts/chaos/reset_volumes.sh volume1 || true
sleep 8
unpin_volume1
ensure_healthy

section "5 master down (new writes blocked, existing GET may work)"
compose stop master
sleep 3
try_put master-down fail
try_master_assign master-down 000
try_get_optional master-down "$BASELINE_FRAGMENT"
capture_logs volume1
compose start master
sleep 10
ensure_healthy

section "6 all volumes down"
compose stop volume1 volume2
sleep 5
try_master_assign all-volumes-down 406
try_put all-volumes-down fail
try_get all-volumes-down "$BASELINE_FRAGMENT" fail
compose start volume1 volume2
sleep 10
ensure_healthy

section "7 sideweed down (write entrypoint blocked, read path separate)"
compose stop sideweed
sleep 3
try_put sideweed-down fail
try_get sideweed-down "$BASELINE_FRAGMENT" pass
compose up -d sideweed
sleep 5

recover_all
print_summary
log ""
if [ "$FAILURES" -eq 0 ]; then
  log "Matrix PASSED (${PASSES} checks, ${WARNS} warn, ${SKIPS} skip). Results: ${RESULTS}"
  exit 0
fi
log "Matrix FAILED (${FAILURES} real errors, ${WARNS} warn, ${SKIPS} skip). Results: ${RESULTS}"
exit 1
