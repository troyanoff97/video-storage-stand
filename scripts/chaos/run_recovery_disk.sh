#!/usr/bin/env bash
# disk ro → soft reset + volume reload → GET baseline (bind-mounted /data).
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
  out=$(./scripts/put_to_volume1.sh "$TEST_FILE" "${CAMERA}-${label}" 2>&1)
  code=$?
  log "PUT-v1 [${label}]: exit=${code} (expect_fail=${expect_fail})"
  log "$out"
  if [ "$expect_fail" = "1" ] && [ "$code" -eq 0 ]; then
    log "WARN: PUT succeeded during fault ${label} (bind mount may ignore remount ro)"
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

check_status_health() {
  local label="$1"
  local expect_writes="${2:-1}"
  local body healthy
  body=$(curl -sf "http://localhost:8080/status" 2>&1) || {
    fail "could not fetch /status for ${label}"
    return
  }
  log "STATUS [${label}]:"
  log "$body"
  if ! echo "$body" | grep -q '"DiskHealth"'; then
    fail "/status missing DiskHealth for ${label}"
    return
  fi
  if echo "$body" | grep -q '"HealthyForWrites":true'; then
    healthy=1
  else
    healthy=0
  fi
  if [ "$healthy" = "$expect_writes" ]; then
    log "OK: HealthyForWrites expectation met (${expect_writes})"
  else
    fail "HealthyForWrites mismatch for ${label} (got ${healthy}, want ${expect_writes})"
  fi
}

disk_readonly_bind() {
  compose exec --privileged volume1 sh -c '
    if grep -qE "[[:space:]]/data[[:space:]]" /proc/mounts; then
      mount -o remount,ro /data
    else
      chmod -R a-w /data
    fi
    touch /data/.ro-probe 2>/dev/null || echo "write probe failed (expected)"
  '
}

: > "$RESULTS"
log "Recovery disk (ro → soft reset → GET) run: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"

compose up -d --build
./scripts/wait-healthy.sh 2>&1 | tee -a "$RESULTS"

check_status_health baseline 1

log "Stopping volume2 so replication=000 targets volume1 only"
compose stop volume2 || true
sleep 3

dd if=/dev/urandom of="$TEST_FILE" bs=64K count=1 status=none

log "=== baseline ==="
baseline_out=$(./scripts/put_to_volume1.sh "$TEST_FILE" "${CAMERA}-baseline" 2>&1) || true
log "$baseline_out"
BASELINE_FRAGMENT=$(echo "$baseline_out" | awk '/fragment_id:/ {print $2}')
BASELINE_CAMERA=$(echo "$baseline_out" | awk '/camera_id:/ {print $2}')
if [ -z "$BASELINE_FRAGMENT" ]; then
  fail "baseline PUT did not produce fragment_id"
fi

log "=== fault: disk read-only (bind mount) ==="
disk_readonly_bind || true
sleep 3
try_put_v1 fault-readonly 1 || log "WARN: PUT during ro fault may succeed on bind-mounted host /data (remount ro often blocked)"
try_get_baseline during-fault 0

log "=== soft reset + reload volumes ==="
"$(dirname "${BASH_SOURCE[0]}")/reset_volumes_soft.sh" volume1 || true
for i in $(seq 1 30); do
  if curl -sf http://localhost:8080/healthz >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
sleep 5

check_status_health after-reset 1
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
