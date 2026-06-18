#!/usr/bin/env bash
# Integration tests for sideweed write degradation gate (production write path).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source "$(dirname "${BASH_SOURCE[0]}")/chaos/_common.sh"

READ_URL="${READ_URL:-http://localhost:8882}"
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

put_s3_http_code() {
  local label="$1"
  set +e
  local out code start_ms elapsed
  start_ms=$(date +%s%3N)
  out=$(./scripts/put_fragment.sh "$TEST_FILE" "${CAMERA}-${label}" 2>&1)
  code=$?
  elapsed=$(( $(date +%s%3N) - start_ms ))
  if [ "$code" -eq 0 ]; then
    echo "200 ${elapsed}"
    return 0
  fi
  if echo "$out" | grep -qE 'status code: 503|503 Service'; then
    echo "503 ${elapsed}"
    return 0
  fi
  if echo "$out" | grep -qE 'status code: 502|502 Bad'; then
    echo "502 ${elapsed}"
    return 0
  fi
  echo "fail ${elapsed}"
  echo "$out" >&2
  return 1
}

wait_log() {
  local pattern="$1"
  local i
  for i in $(seq 1 30); do
    if compose logs sideweed --tail=120 2>&1 | grep -qE "$pattern"; then
      return 0
    fi
    sleep 2
  done
  return 1
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
  pass "baseline PUT via sideweed → S3"
else
  fail "baseline PUT via sideweed → S3"
  echo "$baseline_out"
fi

log "==> master down → PUT blocked fast"
compose stop master
sleep 8
read -r http_code elapsed < <(put_s3_http_code "master-down" || echo "fail 0")
if [ "$http_code" = "503" ] && [ "${elapsed:-99999}" -lt 8000 ]; then
  pass "master down PUT fast 503 (${elapsed}ms)"
else
  fail "master down PUT expected 503 fast, got http=${http_code} elapsed=${elapsed}ms"
fi
if wait_log 'PUT_BLOCKED|"Status":"PUT_BLOCKED"|"Status":"DEGRADED"'; then
  pass "sideweed log contains PUT_BLOCKED or DEGRADED"
else
  fail "missing PUT_BLOCKED/DEGRADED in sideweed logs"
fi
if [ -n "$BASELINE_FRAGMENT" ]; then
  if ./scripts/get_fragment.sh "${CAMERA}-baseline" "$BASELINE_FRAGMENT" /tmp/sideweed-get.bin >/dev/null 2>&1; then
    pass "GET via read path works when master down"
  else
    fail "GET via read path when master down"
  fi
fi
compose start master
sleep 12
./scripts/wait-healthy.sh >/dev/null

log "==> recovery after master up"
if wait_put_ok; then
  pass "PUT works again after master recovery"
else
  fail "PUT did not recover after master restart"
fi
if wait_log '"Status":"RECOVERED"'; then
  pass "sideweed log contains RECOVERED"
else
  fail "missing RECOVERED in sideweed logs"
fi

log "==> all volumes down → PUT blocked"
compose stop volume1 volume2
sleep 8
read -r http_code elapsed < <(put_s3_http_code "all-vol-down" || echo "fail 0")
if [ "$http_code" = "503" ]; then
  pass "all volumes down PUT returns 503"
else
  fail "all volumes down PUT expected 503, got ${http_code}"
fi
compose start volume1 volume2
sleep 12
./scripts/wait-healthy.sh >/dev/null

log "==> S3 gateway down → PUT fails fast"
compose stop s3
sleep 6
read -r http_code elapsed < <(put_s3_http_code "s3-down" || echo "fail 0")
if { [ "$http_code" = "503" ] || [ "$http_code" = "502" ]; } && [ "${elapsed:-99999}" -lt 10000 ]; then
  pass "S3 down PUT fails fast (http=${http_code}, ${elapsed}ms)"
else
  fail "S3 down PUT expected 502/503 fast, got http=${http_code} elapsed=${elapsed}ms"
fi
compose up -d s3 sideweed
sleep 15
./scripts/wait-healthy.sh >/dev/null

log ""
log "Results: PASS=${PASSES} FAIL=${FAILURES}"
if [ "$FAILURES" -gt 0 ]; then
  exit 1
fi
log "sideweed degradation tests PASSED"
exit 0
