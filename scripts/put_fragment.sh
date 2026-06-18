#!/usr/bin/env bash
# Production write path: client → sideweed → S3 Gateway → filer/master → volumes.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <file> <camera_id>" >&2
  echo "  Production: PUT via sideweed → S3 Gateway." >&2
  echo "  Debug direct volume: scripts/debug/put_fragment_direct.sh" >&2
  exit 1
fi

FILE="$1"
CAMERA_ID="$2"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: file not found: $FILE" >&2
  exit 1
fi

export SIDEWEED_URL="${SIDEWEED_URL:-http://localhost:8880}"
export READ_URL="${READ_URL:-http://localhost:8882}"
export S3_BUCKET="${S3_BUCKET:-video-fragments}"
export S3_ACCESS_KEY="${S3_ACCESS_KEY:-stand_access_key}"
export S3_SECRET_KEY="${S3_SECRET_KEY:-stand_secret_key}"
export S3_REGION="${S3_REGION:-us-east-1}"

if [[ ! -x ./bin/fragment ]]; then
  echo "==> Building fragment CLI..."
  make build-cli
fi

echo "==> PUT production path: sideweed ${SIDEWEED_URL} → S3 Gateway (bucket=${S3_BUCKET})"
./bin/fragment put "$FILE" "$CAMERA_ID"
