#!/usr/bin/env bash
# E2E: host loopback fault → weed-volume bind mounts → production write path.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

E2E_COMPOSE_FILES=(docker-compose.yml docker-compose.chaos.yml docker-compose.disk-sim.yml)

require_confirm
load_state

assert_stand_project_matches_port8080
export DISK_SIM_ROOT

TS="$(date -u +%Y%m%dT%H%M%SZ)"
RESULTS="${DISK_SIM_ROOT}/logs/e2e-${TS}.txt"
TEST_FILE="/tmp/disk-sim-e2e-fragment.bin"
CAMERA="disk-sim-e2e"
FAILURES=0

log() { printf '[e2e] %s\n' "$*" | tee -a "$RESULTS"; }
fail() { log "FAIL: $*"; FAILURES=$((FAILURES + 1)); }

collect_e2e_logs() {
  local label="$1"
  DISK_SIM_E2E=1 "$SCRIPT_DIR/collect_logs.sh" 2>&1 | tee -a "$RESULTS" || true
  log "collect_logs after: ${label}"
}

try_put() {
  local label="$1"
  local expect_fail="${2:-0}"
  set +e
  local out code
  out=$(cd "$ROOT_DIR" && ./scripts/put_fragment.sh "$TEST_FILE" "${CAMERA}-${label}" 2>&1)
  code=$?
  log "PUT [${label}]: exit=${code} (expect_fail=${expect_fail})"
  log "$out"
  if [[ "$expect_fail" == "1" && "$code" -eq 0 ]]; then
    fail "PUT succeeded during fault ${label}"
  elif [[ "$expect_fail" == "0" && "$code" -ne 0 ]]; then
    fail "PUT failed when healthy ${label}"
  fi
  set -e
}

try_get() {
  local label="$1"
  local camera="$2"
  local fid="$3"
  set +e
  local out code
  out=$(cd "$ROOT_DIR" && ./scripts/get_fragment.sh "$camera" "$fid" 2>&1)
  code=$?
  log "GET [${label}]: exit=${code}"
  log "$out"
  if [[ "$code" -ne 0 ]]; then
    fail "GET failed ${label}"
  fi
  set -e
}

check_volume_logs() {
  local label="$1"
  shift
  local logs
  logs=$(compose_stand "$ROOT_DIR" "${E2E_COMPOSE_FILES[@]}" -- logs volume1 --tail=200 2>&1)
  for pattern in "$@"; do
    if echo "$logs" | grep -qiE "$pattern"; then
      log "LOG OK [${label}]: matched /${pattern}/"
      return 0
    fi
  done
  fail "expected log pattern [${label}]: $*"
  log "$logs" | tail -40
}

clear_stor1_fill() {
  rm -f "${MNT1}/${DISK_SIM_FILL_NAME}" 2>/dev/null || true
}

: >"$RESULTS"
log "E2E disk-sim test start: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

curl -fsS http://localhost:8080/healthz >/dev/null || die "volume1 not healthy — run e2e_up.sh first"
verify_volume1_disk_sim_binds "$ROOT_DIR" "${E2E_COMPOSE_FILES[@]}"
curl -fsS http://localhost:8880/v1/write-health | grep -q '"status":"healthy"' || \
  log "WARN: sideweed write-health not healthy at start"

dd if=/dev/urandom of="$TEST_FILE" bs=32K count=1 status=none

log "=== baseline write/read (production path) ==="
baseline_out=$(cd "$ROOT_DIR" && ./scripts/put_fragment.sh "$TEST_FILE" "${CAMERA}-baseline" 2>&1)
log "$baseline_out"
baseline_fid=$(echo "$baseline_out" | awk '/fragment_id:/ {print $2}')
[[ -n "$baseline_fid" ]] || fail "no fragment_id from baseline PUT"
try_get baseline-get "${CAMERA}-baseline" "$baseline_fid"
collect_e2e_logs baseline

log "=== disk full on stor1 (host) ==="
clear_stor1_fill
"$SCRIPT_DIR/test_disk_full.sh" 1 2>&1 | tee -a "$RESULTS"
sleep 5
try_put after-stor1-full 0
check_volume_logs stor1-full \
  "marked unhealthy.*data1|disk location.*data1|no space|ENOSPC" \
  "In dir /data2 adds volume|data2"
collect_e2e_logs stor1-full
clear_stor1_fill
CONFIRM_DISK_SIM=1 "$SCRIPT_DIR/recover_mounts.sh" 2>&1 | tee -a "$RESULTS" || true
sleep 3

log "=== read-only remount on stor1 ==="
CONFIRM_DISK_SIM=1 "$SCRIPT_DIR/test_readonly_mount.sh" 1 2>&1 | tee -a "$RESULTS"
sleep 5
try_put after-stor1-ro 0
check_volume_logs stor1-ro \
  "marked unhealthy.*data1|read-only|readonly" \
  "data2|In dir /data2"
collect_e2e_logs stor1-ro
CONFIRM_DISK_SIM=1 "$SCRIPT_DIR/recover_mounts.sh" 2>&1 | tee -a "$RESULTS" || true
sleep 5

log "=== mount unavailable on stor1 ==="
CONFIRM_DISK_SIM=1 "$SCRIPT_DIR/test_mount_unavailable.sh" 1 2>&1 | tee -a "$RESULTS"
sleep 5
try_put after-stor1-umount 0
check_volume_logs stor1-umount \
  "marked unhealthy|data1|mount|permission" \
  "data2|In dir /data2"
collect_e2e_logs stor1-umount
CONFIRM_DISK_SIM=1 "$SCRIPT_DIR/recover_mounts.sh" 2>&1 | tee -a "$RESULTS" || true
sleep 8

log "=== recovery: write/read again ==="
recovery_out=$(cd "$ROOT_DIR" && ./scripts/put_fragment.sh "$TEST_FILE" "${CAMERA}-recovery" 2>&1)
log "$recovery_out"
recovery_fid=$(echo "$recovery_out" | awk '/fragment_id:/ {print $2}')
[[ -n "$recovery_fid" ]] || fail "no fragment_id from recovery PUT"
try_get recovery-get "${CAMERA}-recovery" "$recovery_fid"
collect_e2e_logs recovery

log ""
if [[ "$FAILURES" -eq 0 ]]; then
  log "E2E disk-sim PASSED. Results: $RESULTS"
  exit 0
fi
log "E2E disk-sim FAILED (${FAILURES} checks). Results: $RESULTS"
exit 1
