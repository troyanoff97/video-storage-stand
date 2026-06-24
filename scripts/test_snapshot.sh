#!/usr/bin/env bash
# Smoke: snapshot PUT (csb) → GET round-trip via production read path.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SNAP_FILE=$(mktemp /tmp/snapshot-smoke-XXXX.bin)
OUT_FILE=$(mktemp /tmp/snapshot-smoke-out-XXXX.bin)
SNAPSHOT_ID="snapshot-smoke-$$"

cleanup() {
  rm -f "$SNAP_FILE" "$OUT_FILE"
}
trap cleanup EXIT

dd if=/dev/urandom of="$SNAP_FILE" bs=64K count=1 status=none

echo "==> PUT snapshot (bucket csb)"
put_out=$("./scripts/put_snapshot.sh" "$SNAP_FILE" "$SNAPSHOT_ID")
echo "$put_out"

fragment_id=$(echo "$put_out" | awk '/fragment_id:/ {print $2}')
object_uri=$(echo "$put_out" | awk '/seaweed_fid:/ {print $2}')

if [[ -z "$fragment_id" ]]; then
  echo "FAIL: fragment_id not found in put_snapshot output" >&2
  exit 1
fi

if [[ -z "$object_uri" || "$object_uri" != s3://csb/* ]]; then
  echo "FAIL: expected seaweed_fid s3://csb/..., got: ${object_uri:-<empty>}" >&2
  exit 1
fi

echo ""
echo "==> GET snapshot (snapshot_id=${SNAPSHOT_ID}, fragment_id=${fragment_id})"
get_out=$("./scripts/get_snapshot.sh" "$SNAPSHOT_ID" "$fragment_id" "$OUT_FILE")
echo "$get_out"

if ! cmp -s "$SNAP_FILE" "$OUT_FILE"; then
  echo "FAIL: downloaded snapshot does not match source file" >&2
  exit 1
fi

echo ""
echo "PASS: snapshot PUT/GET round-trip via bucket csb"
