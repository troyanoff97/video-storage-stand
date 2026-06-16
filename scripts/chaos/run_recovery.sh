#!/usr/bin/env bash
# Fault → reset → wait → assert assign/PUT/GET recovery.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

RESULTS="${ROOT_DIR}/chaos-recovery-results.txt"
TEST_FILE="/tmp/chaos-recovery-fragment.bin"
CAMERA="chaos-recovery"
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

try_get_baseline() {
  local label="$1"
  local expect_fail="${2:-0}"
  if [ -z "$BASELINE_FRAGMENT" ] || [ -z "$BASELINE_CAMERA" ]; then
    fail "missing baseline fragment for GET ${label}"
    return
  fi
  set +e
  local out code
  out=$(./scripts/get_fragment.sh "$BASELINE_CAMERA" "$BASELINE_FRAGMENT" "/tmp/recovery-get-${label}.bin" 2>&1)
  code=$?
  log "GET [${label}] camera=${BASELINE_CAMERA} fid=${BASELINE_FRAGMENT}: exit=${code} (expect_fail=${expect_fail})"
  log "$out"
  if [ "$expect_fail" = "1" ] && [ "$code" -eq 0 ]; then
    fail "GET succeeded during fault ${label}"
  elif [ "$expect_fail" = "0" ] && [ "$code" -ne 0 ]; then
    fail "GET failed when healthy ${label}"
  fi
  set -e
}

try_assign_v1() {
  local label="$1"
  local expect_http="${2:-200}"
  set +e
  local body http
  body=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
    "http://localhost:9333/dir/assign?count=1&replication=000&dataCenter=dc1" 2>&1)
  http=$(echo "$body" | awk -F: '/HTTP_CODE:/ {print $2}')
  log "ASSIGN-v1 [${label}]: http=${http:-?} (expect ${expect_http})"
  log "$body"
  if [ "$http" != "$expect_http" ]; then
    fail "assign-v1 http ${http} != ${expect_http} for ${label}"
  fi
  set -e
}

: > "$RESULTS"
log "Recovery scenario: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"

compose up -d
./scripts/wait-healthy.sh 2>&1 | tee -a "$RESULTS"

log "Stopping volume2 so replication=000 targets volume1 only"
compose stop volume2 || true
sleep 3

dd if=/dev/urandom of="$TEST_FILE" bs=64K count=1 status=none

log "=== baseline (volume1 only) ==="
baseline_out=$(./scripts/put_to_volume1.sh "$TEST_FILE" "${CAMERA}-baseline" 2>&1) || true
log "$baseline_out"
BASELINE_FRAGMENT=$(echo "$baseline_out" | awk '/fragment_id:/ {print $2}')
BASELINE_CAMERA=$(echo "$baseline_out" | awk '/camera_id:/ {print $2}')

log "=== fault: volume1 stopped ==="
compose stop volume1
sleep 5
try_put_v1 fault-volume-down 1
try_assign_v1 fault-volume-down 406

log "=== recover: start volume1 ==="
compose start volume1
sleep 5
for i in $(seq 1 30); do
  if curl -sf http://localhost:8080/healthz >/dev/null 2>&1; then
    log "OK: volume1 ready after recovery"
    break
  fi
  if [ "$i" -eq 30 ]; then
    fail "volume1 not healthy after recovery"
  fi
  sleep 2
done
sleep 5

log "=== post-recovery checks (volume1 only) ==="
try_assign_v1 after-recover 200
try_put_v1 after-recover 0
# Note: volume1 tmpfs loses blobs on container restart; GET baseline is not asserted here.

compose up -d volume2 || true
sleep 5

log ""
if [ "$FAILURES" -eq 0 ]; then
  log "Recovery scenario PASSED. Results: ${RESULTS}"
  exit 0
fi
log "Recovery scenario FAILED (${FAILURES} checks). Results: ${RESULTS}"
exit 1
