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
LOG_CHECKPOINT=""
LOG_WAIT_TIMEOUT="${LOG_WAIT_TIMEOUT:-15}"

log() { echo "$@"; }
pass() { PASSES=$((PASSES + 1)); log "PASS: $1"; }
fail() { FAILURES=$((FAILURES + 1)); log "FAIL: $1"; }

write_health_fetch() {
  curl -sS -w $'\n%{http_code}' "${SIDEWEED_URL}/v1/write-health" 2>/dev/null
}

# Args: expected_http expected_status_regex [timeout_seconds]
wait_for_write_health() {
  local expect_http="$1"
  local expect_status_re="$2"
  local timeout="${3:-$LOG_WAIT_TIMEOUT}"
  local i raw http_code body
  for i in $(seq 1 "$timeout"); do
    raw=$(write_health_fetch)
    http_code=$(echo "$raw" | tail -1)
    body=$(echo "$raw" | sed '$d')
    if [ "$http_code" = "$expect_http" ] && echo "$body" | grep -qE "\"status\"[[:space:]]*:[[:space:]]*\"${expect_status_re}\""; then
      echo "$body"
      return 0
    fi
    sleep 1
  done
  raw=$(write_health_fetch)
  http_code=$(echo "$raw" | tail -1)
  body=$(echo "$raw" | sed '$d')
  log "write-health last response http=${http_code} body=${body}"
  return 1
}

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

# Mark log search start — only lines after checkpoint count for this scenario.
sideweed_log_checkpoint() {
  LOG_CHECKPOINT="$(date -u +%Y-%m-%dT%H:%M:%S)"
}

sideweed_logs_since_checkpoint() {
  if [ -n "$LOG_CHECKPOINT" ]; then
    compose logs sideweed --since "$LOG_CHECKPOINT" 2>&1 \
      | grep -E '"Type":"LOG"|WRITE_DEGRADED|WRITE_RECOVERED|PUT_BLOCKED' || true
  else
    compose logs sideweed --tail=200 2>&1 \
      | grep -E '"Type":"LOG"|WRITE_DEGRADED|WRITE_RECOVERED|PUT_BLOCKED' || true
  fi
}

dump_sideweed_logs() {
  log "--- sideweed logs since checkpoint (${LOG_CHECKPOINT:-none}) ---"
  sideweed_logs_since_checkpoint | tail -40
  log "--- end sideweed logs ---"
}

# Wait for log pattern in sideweed output after checkpoint.
# Args: pattern [timeout_seconds]
wait_for_log() {
  local pattern="$1"
  local timeout="${2:-$LOG_WAIT_TIMEOUT}"
  local i logs
  for i in $(seq 1 "$timeout"); do
    logs="$(sideweed_logs_since_checkpoint)"
    if echo "$logs" | grep -qE "$pattern"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# Wait for WRITE_DEGRADED with optional reason alternates (pipe-separated regex).
wait_for_write_degraded() {
  local reasons="${1:-}"
  local pattern='"Status":"WRITE_DEGRADED"'
  if [ -n "$reasons" ]; then
    pattern="\"Status\":\"WRITE_DEGRADED\".*\"Reason\":\"(${reasons})\""
  fi
  if wait_for_log "$pattern"; then
    return 0
  fi
  dump_sideweed_logs
  return 1
}

wait_for_write_recovered() {
  wait_for_log '"Status":"WRITE_RECOVERED"'
}

wait_for_put_blocked() {
  local reason="$1"
  wait_for_log "\"Status\":\"PUT_BLOCKED\".*\"Reason\":\"${reason}\""
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

assert_put_503_fast() {
  local slug="$1"
  local attempt http_code elapsed raw
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    raw=$(put_sideweed_raw "${slug}-$(date +%s)-${attempt}")
    read -r http_code elapsed < <(parse_curl_result "$raw")
    if [ "$http_code" = "503" ] && [ "${elapsed:-9999}" -lt 1000 ]; then
      pass "${slug} PUT 503 <1s (${elapsed}ms, attempt ${attempt})"
      return 0
    fi
    sleep 0.3
  done
  fail "${slug} PUT expected 503 <1s, got http=${http_code} elapsed=${elapsed}ms after ${attempt} attempts"
  dump_sideweed_logs
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

log "==> Prometheus /metrics"
if curl -fsS "${SIDEWEED_URL}/metrics" | grep -q 'sideweed_write_health_status'; then
  pass "GET /metrics exposes sideweed_write_health_status"
else
  fail "GET /metrics missing sideweed_write_health_status"
fi

log "==> write-health baseline"
if wait_for_write_health 200 healthy 20 >/dev/null; then
  pass "GET /v1/write-health baseline 200 status=healthy"
else
  fail "GET /v1/write-health baseline not healthy"
fi

log "==> master down → WRITE_DEGRADED + PUT 503 <1s"
sideweed_log_checkpoint
compose stop master
# Probes run every 3s; allow one interval before strict wait.
sleep 1
if wait_for_write_degraded "master_down|assign_failed"; then
  pass "WRITE_DEGRADED logged (master_down|assign_failed)"
else
  fail "WRITE_DEGRADED not seen after master down (within ${LOG_WAIT_TIMEOUT}s)"
fi
if wait_for_write_health 503 degraded >/dev/null; then
  pass "GET /v1/write-health 503 status=degraded (master down)"
else
  fail "GET /v1/write-health not degraded after master down"
fi
assert_put_503_fast "master-down" || true
if wait_for_put_blocked "write_health_degraded"; then
  pass "PUT_BLOCKED reason=write_health_degraded"
else
  fail "missing PUT_BLOCKED write_health_degraded"
  dump_sideweed_logs
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
sideweed_log_checkpoint
if wait_put_ok; then
  pass "PUT works again after master recovery (200)"
else
  fail "PUT did not recover after master restart"
fi
if wait_for_write_recovered; then
  pass "WRITE_RECOVERED logged"
else
  fail "missing WRITE_RECOVERED in sideweed logs"
  dump_sideweed_logs
fi
if wait_for_write_health 200 healthy 20 >/dev/null; then
  pass "GET /v1/write-health 200 status=healthy after master recovery"
else
  fail "GET /v1/write-health not healthy after master recovery"
fi

log "==> all volumes down → WRITE_DEGRADED + PUT 503 <1s"
sideweed_log_checkpoint
compose stop volume1 volume2
sleep 1
if wait_for_write_degraded "all_volumes_down|assign_failed"; then
  pass "WRITE_DEGRADED logged (all_volumes_down|assign_failed)"
else
  fail "WRITE_DEGRADED not seen after all volumes down (within ${LOG_WAIT_TIMEOUT}s)"
fi
if wait_for_write_health 503 degraded >/dev/null; then
  pass "GET /v1/write-health 503 status=degraded (all volumes down)"
else
  fail "GET /v1/write-health not degraded after all volumes down"
fi
assert_put_503_fast "all-volumes-down" || true
compose start volume1 volume2
sleep 10
./scripts/wait-healthy.sh >/dev/null

log "==> filer down → WRITE_DEGRADED + PUT 503 <1s"
sideweed_log_checkpoint
compose stop filer
sleep 1
if wait_for_write_degraded "filer_down|s3_down|write_unhealthy"; then
  pass "WRITE_DEGRADED logged after filer down (filer_down|s3_down|write_unhealthy)"
else
  fail "WRITE_DEGRADED not seen after filer down (within ${LOG_WAIT_TIMEOUT}s)"
fi
wh_filer_down=$(wait_for_write_health 503 degraded || true)
if [ -n "$wh_filer_down" ]; then
  pass "GET /v1/write-health 503 status=degraded (filer down)"
  if echo "$wh_filer_down" | grep -q '"reason":"filer_down"'; then
    pass "GET /v1/write-health reason=filer_down"
  elif echo "$wh_filer_down" | grep -qE '"reason":"(s3_down|write_unhealthy)"'; then
    reason=$(echo "$wh_filer_down" | grep -oE '"reason":"[^"]*"' | head -1)
    pass "GET /v1/write-health degraded (${reason}; S3 may depend on filer)"
    log "NOTE: filer-down reason=${reason} — if not filer_down, SeaweedFS S3↔filer coupling on stand"
  else
    reason=$(echo "$wh_filer_down" | grep -oE '"reason":"[^"]*"' | head -1 || echo "unknown")
    fail "unexpected /v1/write-health reason after filer down: ${reason}"
    log "write-health body: ${wh_filer_down}"
  fi
else
  fail "GET /v1/write-health not degraded after filer down"
fi
assert_put_503_fast "filer-down" || true
if wait_for_put_blocked "write_health_degraded"; then
  pass "PUT_BLOCKED reason=write_health_degraded (filer down)"
else
  fail "missing PUT_BLOCKED write_health_degraded after filer down"
  dump_sideweed_logs
fi
compose up -d filer
sleep 10
./scripts/wait-healthy.sh >/dev/null

log "==> recovery after filer up"
sideweed_log_checkpoint
if wait_put_ok; then
  pass "PUT works again after filer recovery (200)"
else
  fail "PUT did not recover after filer restart"
fi
if wait_for_write_recovered; then
  pass "WRITE_RECOVERED logged after filer recovery"
else
  fail "missing WRITE_RECOVERED after filer recovery"
  dump_sideweed_logs
fi
if wait_for_write_health 200 healthy 20 >/dev/null; then
  pass "GET /v1/write-health 200 status=healthy after filer recovery"
else
  fail "GET /v1/write-health not healthy after filer recovery"
fi

log "==> S3 gateway down → PUT 503 <1s (not 502)"
sideweed_log_checkpoint
compose stop s3
sleep 1
if wait_for_log '"Status":"WRITE_DEGRADED".*"Reason":"s3_down"|"Status":"PUT_BLOCKED".*"Reason":"s3_backend_down"'; then
  pass "WRITE_DEGRADED reason=s3_down or PUT_BLOCKED s3_backend_down"
else
  fail "missing WRITE_DEGRADED s3_down / PUT_BLOCKED s3_backend_down"
  dump_sideweed_logs
fi
assert_put_503_fast "s3-down" || true
if wait_for_put_blocked "s3_backend_down"; then
  pass "PUT_BLOCKED reason=s3_backend_down"
else
  fail "missing PUT_BLOCKED s3_backend_down"
  dump_sideweed_logs
fi
if wait_for_write_health 503 degraded >/dev/null; then
  pass "GET /v1/write-health 503 status=degraded (S3 down)"
else
  fail "GET /v1/write-health not degraded after S3 down"
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
