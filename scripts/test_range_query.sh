#!/usr/bin/env bash
# Smoke: PUT fragments then list by camera_id + time range on runtime schema.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CAMERA_ID="range-query-$$"
SMALL_FILE=$(mktemp /tmp/range-query-smoke-XXXX.bin)

cleanup() {
  rm -f "$SMALL_FILE"
}
trap cleanup EXIT

dd if=/dev/urandom of="$SMALL_FILE" bs=4K count=1 status=none

echo "==> PUT 3 fragments for camera ${CAMERA_ID}"
for _ in 1 2 3; do
  ./scripts/put_fragment.sh "$SMALL_FILE" "$CAMERA_ID" >/dev/null
done

FROM=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)
TO=$(date -u -d '1 hour' +%Y-%m-%dT%H:%M:%SZ)

echo "==> LIST fragments (${FROM} .. ${TO})"
list_out=$(./scripts/list_fragments.sh "$CAMERA_ID" "$FROM" "$TO" 100)
echo "$list_out"

count=$(echo "$list_out" | grep -c 's3://video-fragments/' || true)
if (( count < 3 )); then
  echo "FAIL: expected at least 3 fragments with s3://video-fragments/, got ${count}" >&2
  exit 1
fi

echo ""
echo "PASS: range query found ${count} fragment(s) for ${CAMERA_ID}"
