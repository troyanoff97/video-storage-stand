#!/usr/bin/env bash
# Production snapshot read: same path as fragments, bucket csb (production requirement).
# Metadata remains in video_archive.fragments (camera_id = snapshot_id); schema-v2 is not runtime.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <snapshot_id> <fragment_id> [output_file]" >&2
  echo "  GET via HAProxy → sideweed-read → S3 Gateway, bucket csb." >&2
  echo "  Use snapshot_id and fragment_id printed by put_snapshot.sh (camera_id / fragment_id)." >&2
  exit 1
fi

SNAPSHOT_ID="$1"
FRAGMENT_ID="$2"
OUTPUT_FILE="${3:-/tmp/snapshot_out.bin}"

export S3_BUCKET=csb

"${ROOT_DIR}/scripts/get_fragment.sh" "$SNAPSHOT_ID" "$FRAGMENT_ID" "$OUTPUT_FILE"

OBJECT_URI=$(awk '/seaweed_fid:/ {print $2}' /tmp/get_fragment_meta.txt 2>/dev/null || true)
if [[ -n "$OBJECT_URI" && "$OBJECT_URI" != s3://csb/* ]]; then
  echo "ERROR: expected object in bucket csb, got: ${OBJECT_URI}" >&2
  exit 1
fi
