#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <file> <camera_id> [fragment_id]" >&2
  echo "  fragment_id: optional timeuuid; auto-generated if omitted" >&2
  exit 1
fi

FILE="$1"
CAMERA_ID="$2"
FRAGMENT_ID="${3:-}"

MASTER_URL="${MASTER_URL:-http://localhost:9333}"
SIDEWEED_URL="${SIDEWEED_URL:-http://localhost:8880}"
REPLICATION="${REPLICATION:-001}"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: file not found: $FILE" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required" >&2
  exit 1
fi

SIZE=$(stat -c%s "$FILE")

echo "==> Assign from master (replication=${REPLICATION})"
ASSIGN=$(curl -sf "${MASTER_URL}/dir/assign?count=1&replication=${REPLICATION}")
echo "$ASSIGN" | jq .

FID=$(echo "$ASSIGN" | jq -r .fid)
VOLUME_URL=$(echo "$ASSIGN" | jq -r .url)

if [[ -z "$FID" || "$FID" == "null" ]]; then
  echo "ERROR: failed to get fid from assign response" >&2
  exit 1
fi

echo "==> PUT via sideweed (assigned volume: ${VOLUME_URL}, fid: ${FID})"
HTTP_CODE=$(curl -s -o /tmp/put_response.txt -w "%{http_code}" \
  -X POST -F "file=@${FILE}" "${SIDEWEED_URL}/${FID}")

if [[ "$HTTP_CODE" != "201" && "$HTTP_CODE" != "200" ]]; then
  echo "ERROR: PUT failed with HTTP ${HTTP_CODE}" >&2
  cat /tmp/put_response.txt >&2 || true
  exit 1
fi
cat /tmp/put_response.txt
echo

if [[ -z "$FRAGMENT_ID" ]]; then
  FRAGMENT_ID=$(python3 - <<'PY'
import uuid
print(uuid.uuid1())
PY
)
fi

CREATED_AT=$(date -u +"%Y-%m-%d %H:%M:%S+0000")

echo "==> INSERT metadata into Cassandra"
docker compose exec -T cassandra cqlsh -e \
  "INSERT INTO video_archive.fragments (camera_id, fragment_id, seaweed_fid, size, created_at)
   VALUES ('${CAMERA_ID}', ${FRAGMENT_ID}, '${FID}', ${SIZE}, '${CREATED_AT}');"

echo "==> Verify GET via sideweed"
curl -sf "${SIDEWEED_URL}/${FID}" -o /tmp/verify_fragment.bin
VERIFY_SIZE=$(stat -c%s /tmp/verify_fragment.bin)

if [[ "$VERIFY_SIZE" != "$SIZE" ]]; then
  echo "ERROR: size mismatch after GET (expected ${SIZE}, got ${VERIFY_SIZE})" >&2
  exit 1
fi

echo
echo "SUCCESS"
echo "  camera_id:    ${CAMERA_ID}"
echo "  fragment_id:  ${FRAGMENT_ID}"
echo "  seaweed_fid:  ${FID}"
echo "  size:         ${SIZE}"
