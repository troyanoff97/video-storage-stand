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

export READ_URL="${READ_URL:-http://localhost:8882}"
export SIDEWEED_URL="${SIDEWEED_URL:-http://localhost:8880}"
export S3_BUCKET="${S3_BUCKET:-video-fragments}"
export S3_ACCESS_KEY="${S3_ACCESS_KEY:-stand_access_key}"
export S3_REGION="${S3_REGION:-us-east-1}"

if [[ ! -x ./bin/fragment ]]; then
  make build-cli
fi

echo "==> GET via production read path (HAProxy ${READ_URL} → sideweed-read → S3)"
./bin/fragment get "$CAMERA_ID" "$FRAGMENT_ID" >/tmp/get_fragment_meta.txt

OBJECT_URI=$(awk '/seaweed_fid:/ {print $2}' /tmp/get_fragment_meta.txt)
OUT=$(awk '/output:/ {print $2}' /tmp/get_fragment_meta.txt)

if [[ -n "$OUT" && -f "$OUT" ]]; then
  cp "$OUT" "$OUTPUT_FILE"
fi

cat /tmp/get_fragment_meta.txt
echo "  saved_to:     ${OUTPUT_FILE}"
echo "  object_uri:   ${OBJECT_URI:-unknown}"
