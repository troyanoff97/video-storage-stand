#!/usr/bin/env bash
# DEBUG ONLY: direct master assign + POST to volume (bypasses sideweed/S3 production path).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <file> <camera_id> [fragment_id]" >&2
  echo "  DEBUG: master /dir/assign → direct POST to volume. Not production." >&2
  exit 1
fi

FILE="$1"
CAMERA_ID="$2"
FRAGMENT_ID="${3:-}"

MASTER_URL="${MASTER_URL:-http://localhost:9333}"
SIDEWEED_VOLUMES_URL="${SIDEWEED_VOLUMES_URL:-http://localhost:8884}"
REPLICATION="${REPLICATION:-000}"
DATA_CENTER="${DATA_CENTER:-}"

# shellcheck source=volume_url.sh
source "$(dirname "${BASH_SOURCE[0]}")/volume_url.sh"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: file not found: $FILE" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required" >&2
  exit 1
fi

SIZE=$(stat -c%s "$FILE")

echo "==> [DEBUG] Assign from master (replication=${REPLICATION})"
set +e
ASSIGN_URL="${MASTER_URL}/dir/assign?count=1&replication=${REPLICATION}"
if [[ -n "$DATA_CENTER" ]]; then
  ASSIGN_URL="${ASSIGN_URL}&dataCenter=${DATA_CENTER}"
fi
ASSIGN=$(curl -s -w "\nHTTP_CODE:%{http_code}" "${ASSIGN_URL}")
ASSIGN_HTTP=$(echo "$ASSIGN" | awk -F: '/HTTP_CODE:/ {print $2}')
ASSIGN_BODY=$(echo "$ASSIGN" | sed '/HTTP_CODE:/d')
set -e

echo "$ASSIGN_BODY" | jq . 2>/dev/null || echo "$ASSIGN_BODY"

if [[ "$ASSIGN_HTTP" != "200" ]]; then
  echo "ERROR: assign failed with HTTP ${ASSIGN_HTTP}" >&2
  exit 22
fi

FID=$(echo "$ASSIGN_BODY" | jq -r .fid)
VOLUME_URL=$(echo "$ASSIGN_BODY" | jq -r .url)

if [[ -z "$FID" || "$FID" == "null" ]]; then
  echo "ERROR: failed to get fid from assign response" >&2
  exit 1
fi

echo "==> [DEBUG] PUT directly to assigned volume (${VOLUME_URL}, fid: ${FID})"
DIRECT_VOLUME_URL=$(resolve_volume_url "${VOLUME_URL}")
HTTP_CODE=$(curl -s -o /tmp/put_response.txt -w "%{http_code}" \
  -X POST -F "file=@${FILE}" "${DIRECT_VOLUME_URL}/${FID}")

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

echo "==> [DEBUG] INSERT metadata into Cassandra (stand only; production uses filer metadata)"
docker compose exec -T cassandra cqlsh -e \
  "INSERT INTO video_archive.fragments (camera_id, fragment_id, seaweed_fid, size, created_at)
   VALUES ('${CAMERA_ID}', ${FRAGMENT_ID}, '${FID}', ${SIZE}, '${CREATED_AT}');"

echo "==> [DEBUG] Verify GET via sideweed-volumes (compose profile debug, port 8884)"
if [[ "${SKIP_SIDEWEED_VERIFY:-0}" == "1" ]]; then
  echo "SKIP_SIDEWEED_VERIFY=1 — skipping GET check"
else
  curl -sf "${SIDEWEED_VOLUMES_URL}/${FID}" -o /tmp/verify_fragment.bin
  VERIFY_SIZE=$(stat -c%s /tmp/verify_fragment.bin)
  if [[ "$VERIFY_SIZE" != "$SIZE" ]]; then
    echo "ERROR: size mismatch after GET (expected ${SIZE}, got ${VERIFY_SIZE})" >&2
    exit 1
  fi
fi

echo
echo "SUCCESS (debug direct volume PUT)"
echo "  camera_id:    ${CAMERA_ID}"
echo "  fragment_id:  ${FRAGMENT_ID}"
echo "  seaweed_fid:  ${FID}"
echo "  size:         ${SIZE}"
