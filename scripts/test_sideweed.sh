#!/usr/bin/env bash
# Integration tests for sideweed write degradation gate (production write path).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source "$(dirname "${BASH_SOURCE[0]}")/chaos/_common.sh"

SIDEWEED_URL="${SIDEWEED_URL:-http://localhost:8880}"
TEST_FILE="${TEST_FILE:-/tmp/sideweed-test.bin}"
CAMERA="sideweed-gate-test"
FAILURES=0
PASSES=0
BASELINE_FRAGMENT=""

log() { echo "$@"; }
pass() { PASSES=$((PASSES + 1)); log "PASS: $1"; }
fail() { FAILURES=$((FAILURES + 1)); log "FAIL: $1"; }

put_s3() {
  local label="$1"
  set +e
  local out code
  out=$(./scripts/put_fragment.sh "$TEST_FILE" "${CAMERA}-${label}" 2>&1)
  code=$?
  echo "$out"
  return "$code"
}

# Raw PUT to sideweed — hits write gate before S3 auth (latency measurement).
put_sideweed_raw() {
  local key="$1"
  curl -sS -o /tmp/sideweed-put-body.txt -w "%{http_code} %{time_total}" \
    --max-time 2 \
    -X PUT --data-binary @"$TEST_FILE" \
    -H "Content-Type: application/octet-stream" \
    "${SIDEWEED_URL}/video-fragments/${CAMERA}/${key}.bin" 2>/dev/null
}

parse_curl_result() {
  local raw="$1"
  local http_code elapsed_ms
  http_code=$(echo "$raw" | awk '{print $1}')
  elapsed_ms=$(echo "$raw" | awk '{printf "%.0f", $2 * 1000}')
  echo "${http_code} ${elapsed_ms}"
}

wait_log() {
  local pattern="$1"
  local i
  for i in $(seq 1 30); do
    if compose logs sideweed --tail=150 2>&1 | grep -qE "$pattern"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_write_degraded() {
  wait_log 'WRITE_DEGRADED|"Status":"WRITE_DEGRADED"'
}

wait_put_ok() {
  local i
  for i in $(seq 1 40); do
    if put_s3 "recovery-probe-${i}" >/dev/null; then
      return 0
    fi
    sleep 2
  done
  return 1
}

dd if=/dev/urandom of="$TEST_FILE" bs=32K count=1 status=none 2>/dev/null || true
make -s build-cli >/dev/null

log "==> sideweed degradation integration tests"
./scripts/wait-healthy.sh >/dev/null

baseline_out=$(put_s3 "baseline" || true)
if echo "$baseline_out" | grep -q SUCCESS; then
  BASELINE_FRAGMENT=$(echo "$baseline_out" | awk '/fragment_id:/ {print $2}')
  pass "baseline PUT via sideweed → S3 (200)"
else
  fail "baseline PUT via sideweed → S3"
  echo "$baseline_out"
fi

log "==> master down → PUT blocked <1s after WRITE_DEGRADED"
compose stop master
if ! wait_write_degraded; then
  fail "WRITE_DEGRADED not seen after master down"
else
  pass "WRITE_DEGRADED logged (master_down)"
fi
read -r http_code elapsed < <(parse_curl_result "$(put_sideweed_raw "master-down-$(date +%s)")")
if [ "$http_code" = "503" ] && [ "${elapsed:-9999}" -lt 1000 ]; then
  pass "master down PUT 503 <1s (${elapsed}ms)"
else
  fail "master down PUT expected 503 <1s, got http=${http_code} elapsed=${elapsed}ms"
fi
if wait_log 'PUT_BLOCKED.*write_health_degraded|"Reason":"write_health_degraded"'; then
  pass "PUT_BLOCKED reason=write_health_degraded"
else
  fail "missing PUT_BLOCKED write_health_degraded"
fi
if [ -n "$BASELINE_FRAGMENT" ]; then
  if ./scripts/get_fragment.sh "${CAMERA}-baseline" "$BASELINE_FRAGMENT" /tmp/sideweed-get.bin >/dev/null 2>&1; then
    pass "GET via read path works when master down"
  else
    fail "GET via read path when master down"
  fi
fi
compose start master
sleep 10
./scripts/wait-healthy.sh >/dev/null

log "==> recovery after master up"
if wait_put_ok; then
  pass "PUT works again after master recovery (200)"
else
  fail "PUT did not recover after master restart"
fi
if wait_log 'WRITE_RECOVERED|"Status":"WRITE_RECOVERED"'; then
  pass "WRITE_RECOVERED logged"
else
  fail "missing WRITE_RECOVERED in sideweed logs"
fi

log "==> all volumes down → PUT 503 <1s after WRITE_DEGRADED"
compose stop volume1 volume2
if ! wait_write_degraded; then
  fail "WRITE_DEGRADED not seen after all volumes down"
else
  pass "WRITE_DEGRADED logged (all_volumes_down)"
fi
read -r http_code elapsed < <(parse_curl_result "$(put_sideweed_raw "all-vol-$(date +%s)")")
if [ "$http_code" = "503" ] && [ "${elapsed:-9999}" -lt 1000 ]; then
  pass "all volumes down PUT 503 <1s (${elapsed}ms)"
else
  fail "all volumes down PUT expected 503 <1s, got http=${http_code} elapsed=${elapsed}ms"
fi
compose start volume1 volume2
sleep 10
./scripts/wait-healthy.sh >/dev/null

log "==> S3 gateway down → PUT 503 <1s (not 502)"
compose stop s3
for _ in $(seq 1 5); do
  if compose logs sideweed --tail=40 2>&1 | grep -qE 'WRITE_DEGRADED.*s3_down|"Reason":"s3_down"|s3_backend_down|PUT_BLOCKED.*s3_backend_down'; then
    break
  fi
  sleep 1
done
read -r http_code elapsed < <(parse_curl_result "$(put_sideweed_raw "s3-down-$(date +%s)")")
if [ "$http_code" = "503" ] && [ "${elapsed:-9999}" -lt 1000 ]; then
  pass "S3 down PUT 503 <1s (${elapsed}ms)"
else
  fail "S3 down PUT expected 503 <1s, got http=${http_code} elapsed=${elapsed}ms"
fi
if wait_log 'PUT_BLOCKED.*s3_backend_down|"Reason":"s3_backend_down"'; then
  pass "PUT_BLOCKED reason=s3_backend_down"
else
  fail "missing PUT_BLOCKED s3_backend_down"
fi
compose up -d s3 sideweed
sleep 12
./scripts/wait-healthy.sh >/dev/null

log ""
log "Results: PASS=${PASSES} FAIL=${FAILURES}"
if [ "$FAILURES" -gt 0 ]; then
  exit 1
fi
log "sideweed degradation tests PASSED"
exit 0
