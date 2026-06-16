#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

RESULTS="${ROOT_DIR}/chaos-matrix-results.txt"
TEST_FILE="/tmp/chaos-matrix-fragment.bin"
CAMERA="chaos-matrix"
BASELINE_FID=""
BASELINE_FRAGMENT=""
FAILURES=0

log() {
  echo "$@" | tee -a "$RESULTS"
}

section() {
  log ""
  log "=== $1 ==="
}

fail() {
  log "FAIL: $1"
  FAILURES=$((FAILURES + 1))
}

try_put() {
  local label="$1"
  local expect_fail="${2:-0}"
  local data_center="${3:-}"
  set +e
  local out code
  if [[ "$data_center" == "dc1-v1" ]]; then
    out=$(DATA_CENTER=dc1 REPLICATION=000 ./scripts/put_fragment.sh "$TEST_FILE" "${CAMERA}-${label}" 2>&1)
  elif [[ -n "$data_center" ]]; then
    out=$(DATA_CENTER="$data_center" ./scripts/put_fragment.sh "$TEST_FILE" "${CAMERA}-${label}" 2>&1)
  else
    out=$(./scripts/put_fragment.sh "$TEST_FILE" "${CAMERA}-${label}" 2>&1)
  fi
  code=$?
  log "PUT [${label}] dataCenter=${data_center:-any}: exit=${code} (expect_fail=${expect_fail})"
  log "$out"
  if [ "$expect_fail" = "1" ] && [ "$code" -eq 0 ]; then
    fail "PUT succeeded during fault ${label}"
  elif [ "$expect_fail" = "0" ] && [ "$code" -ne 0 ]; then
    fail "PUT failed when healthy ${label}"
  fi
  set -e
  return "$code"
}

try_get() {
  local label="$1"
  local fid="$2"
  local expect_fail="${3:-0}"
  set +e
  local out code
  out=$(./scripts/get_fragment.sh "${CAMERA}-baseline" "$fid" "/tmp/chaos-get-${label}.bin" 2>&1)
  code=$?
  log "GET [${label}] fid=${fid}: exit=${code} (expect_fail=${expect_fail})"
  log "$out"
  if [ "$expect_fail" = "1" ] && [ "$code" -eq 0 ]; then
    fail "GET succeeded during fault ${label}"
  elif [ "$expect_fail" = "0" ] && [ "$code" -ne 0 ]; then
    fail "GET failed when healthy ${label}"
  fi
  set -e
  return "$code"
}

try_assign() {
  local label="$1"
  local expect_http="${2:-200}"
  set +e
  local out code http
  out=$(curl -s -w "\nHTTP_CODE:%{http_code}" "http://localhost:9333/dir/assign?count=1&replication=001" 2>&1)
  code=$?
  http=$(echo "$out" | awk -F: '/HTTP_CODE:/ {print $2}')
  log "ASSIGN [${label}]: curl_exit=${code} http=${http:-?} (expect ${expect_http})"
  log "$out"
  if [ "$http" != "$expect_http" ]; then
    fail "assign http ${http} != ${expect_http} for ${label}"
  fi
  set -e
}

capture_logs() {
  local svc="$1"
  log "--- logs ${svc} (last 15) ---"
  compose logs "$svc" --tail=15 2>&1 | tee -a "$RESULTS"
}

recover_all() {
  compose start master volume1 volume2 sideweed 2>/dev/null || true
  ./scripts/chaos/reset_volumes.sh volume1 2>/dev/null || true
  compose restart volume1 volume2 2>/dev/null || true
  sleep 8
}

: > "$RESULTS"
log "Chaos matrix run: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"

compose up -d
./scripts/wait-healthy.sh 2>&1 | tee -a "$RESULTS"

dd if=/dev/urandom of="$TEST_FILE" bs=384K count=1 status=none

section "baseline (healthy stack)"
baseline_out=$(./scripts/put_fragment.sh "$TEST_FILE" "${CAMERA}-baseline" 2>&1) || true
log "PUT [baseline]:"
log "$baseline_out"
BASELINE_FRAGMENT=$(echo "$baseline_out" | awk '/fragment_id:/ {print $2}')
BASELINE_FID=$(echo "$baseline_out" | awk '/seaweed_fid:/ {print $2}')
if [ -z "$BASELINE_FRAGMENT" ]; then
  fail "baseline PUT did not produce fragment_id"
fi
log "Captured baseline fragment_id=${BASELINE_FRAGMENT} fid=${BASELINE_FID}"

section "1 volume down"
compose stop volume1
sleep 6
try_put volume-down 0
try_get volume-down "$BASELINE_FRAGMENT" 0
capture_logs sideweed
capture_logs volume2
compose start volume1
sleep 8

section "2 mount unavailable (volume1)"
./scripts/chaos/mount_unavailable.sh volume1
sleep 5
try_put mount-unavailable 1 dc1-v1
capture_logs volume1
capture_logs sideweed
./scripts/chaos/reset_volumes.sh volume1 || true
sleep 8

section "3 disk full (volume1)"
./scripts/chaos/disk_full.sh volume1 || true
try_put disk-full 1 dc1-v1
capture_logs volume1
./scripts/chaos/reset_volumes.sh volume1 || true
sleep 8

section "4 disk read-only (volume1)"
./scripts/chaos/disk_readonly.sh volume1 || true
try_put disk-readonly 1 dc1-v1
try_get disk-readonly "$BASELINE_FRAGMENT" 0
capture_logs volume1
./scripts/chaos/reset_volumes.sh volume1 || true
sleep 8

section "5 master down"
compose stop master
try_assign master-down 000
try_get master-down "$BASELINE_FRAGMENT" 0
capture_logs volume1
compose start master
sleep 8

section "6 all volumes down"
compose stop volume1 volume2
sleep 5
try_assign all-volumes-down 000
try_put all-volumes-down 1
try_get all-volumes-down "$BASELINE_FRAGMENT" 1
compose start volume1 volume2
sleep 8

section "7 sideweed down"
compose stop sideweed
sleep 3
try_put sideweed-down 0
try_get sideweed-down "$BASELINE_FRAGMENT" 1
compose up -d sideweed
sleep 5

recover_all
log ""
if [ "$FAILURES" -eq 0 ]; then
  log "Matrix PASSED. Results: ${RESULTS}"
  exit 0
fi
log "Matrix FAILED (${FAILURES} checks). Results: ${RESULTS}"
exit 1
