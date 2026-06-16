#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <camera_id> <fragment_id> [output_file]" >&2
  exit 1
fi

CAMERA_ID="$1"
FRAGMENT_ID="$2"
OUTPUT_FILE="${3:-/tmp/fragment_out.bin}"

SIDEWEED_URL="${SIDEWEED_URL:-http://localhost:8880}"

echo "==> SELECT metadata from Cassandra"
ROW=$(docker compose exec -T cassandra cqlsh -e \
  "SELECT seaweed_fid, size, created_at FROM video_archive.fragments
   WHERE camera_id='${CAMERA_ID}' AND fragment_id=${FRAGMENT_ID};" | tr -d '\r')

echo "$ROW"

FID=$(echo "$ROW" | awk -F'|' '/^[[:space:]]*[0-9]+,/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); print $1; exit}')
EXPECTED_SIZE=$(echo "$ROW" | awk -F'|' '/^[[:space:]]*[0-9]+,/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}')

if [[ -z "$FID" ]]; then
  echo "ERROR: fragment not found in Cassandra" >&2
  exit 1
fi

echo "==> GET blob via sideweed (fid: ${FID})"
curl -sf "${SIDEWEED_URL}/${FID}" -o "$OUTPUT_FILE"

ACTUAL_SIZE=$(stat -c%s "$OUTPUT_FILE")
echo "Downloaded ${ACTUAL_SIZE} bytes to ${OUTPUT_FILE}"

if [[ -n "$EXPECTED_SIZE" && "$ACTUAL_SIZE" != "$EXPECTED_SIZE" ]]; then
  echo "WARNING: size mismatch (expected ${EXPECTED_SIZE}, got ${ACTUAL_SIZE})" >&2
  exit 1
fi

echo "SUCCESS"
