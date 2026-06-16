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

log() {
  echo "$@" | tee -a "$RESULTS"
}

section() {
  log ""
  log "=== $1 ==="
}

try_put() {
  local label="$1"
  set +e
  local out code
  out=$(./scripts/put_fragment.sh "$TEST_FILE" "${CAMERA}-${label}" 2>&1)
  code=$?
  log "PUT [${label}]: exit=${code}"
  log "$out"
  set -e
  return "$code"
}

try_get() {
  local label="$1"
  local fid="$2"
  set +e
  local out code
  out=$(./scripts/get_fragment.sh "${CAMERA}-baseline" "$fid" "/tmp/chaos-get-${label}.bin" 2>&1)
  code=$?
  log "GET [${label}] fid=${fid}: exit=${code}"
  log "$out"
  set -e
  return "$code"
}

try_assign() {
  set +e
  local out code
  out=$(curl -s -w "\nHTTP_CODE:%{http_code}" "http://localhost:9333/dir/assign?count=1&replication=001" 2>&1)
  code=$?
  log "ASSIGN: exit=${code}"
  log "$out"
  set -e
}

capture_logs() {
  local svc="$1"
  log "--- logs ${svc} (last 15) ---"
  compose logs "$svc" --tail=15 2>&1 | tee -a "$RESULTS"
}

recover_all() {
  compose start master volume1 volume2 2>/dev/null || true
  ./scripts/chaos/reset_volumes.sh volume1 2>/dev/null || true
  compose restart volume1 volume2 2>/dev/null || true
  sleep 8
}

: > "$RESULTS"
log "Chaos matrix run: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"

dd if=/dev/urandom of="$TEST_FILE" bs=1M count=1 status=none

section "baseline (healthy stack)"
baseline_out=$(./scripts/put_fragment.sh "$TEST_FILE" "${CAMERA}-baseline" 2>&1) || true
log "PUT [baseline]:"
log "$baseline_out"
BASELINE_FRAGMENT=$(echo "$baseline_out" | awk '/fragment_id:/ {print $2}')
BASELINE_FID=$(echo "$baseline_out" | awk '/seaweed_fid:/ {print $2}')
log "Captured baseline fragment_id=${BASELINE_FRAGMENT} fid=${BASELINE_FID}"

section "1 volume down"
compose stop volume1
sleep 6
try_put volume-down || true
try_get volume-down "$BASELINE_FRAGMENT" || true
capture_logs sideweed
capture_logs volume2
compose start volume1
sleep 8

section "2 mount unavailable (volume1)"
./scripts/chaos/mount_unavailable.sh volume1
sleep 5
try_put mount-unavailable || true
capture_logs volume1
capture_logs sideweed
./scripts/chaos/reset_volumes.sh volume1 || true
sleep 8

section "3 disk full (volume1)"
./scripts/chaos/disk_full.sh volume1 || true
try_put disk-full || true
capture_logs volume1
./scripts/chaos/reset_volumes.sh volume1 || true
sleep 8

section "4 disk read-only (volume1)"
./scripts/chaos/disk_readonly.sh volume1 || true
try_put disk-readonly || true
try_get disk-readonly "$BASELINE_FRAGMENT" || true
capture_logs volume1
./scripts/chaos/reset_volumes.sh volume1 || true
sleep 8

section "5 master down"
compose stop master
try_assign || true
try_get master-down "$BASELINE_FRAGMENT" || true
capture_logs volume1
compose start master
sleep 8

recover_all
log ""
log "Matrix complete. Results: ${RESULTS}"
exit 0
