#!/usr/bin/env bash
# Production snapshot write: same path as fragments, bucket csb (production requirement).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <file> <snapshot_id>" >&2
  echo "  PUT via sideweed → S3 Gateway, bucket csb." >&2
  exit 1
fi

export S3_BUCKET=csb
exec "${ROOT_DIR}/scripts/put_fragment.sh" "$1" "$2"
