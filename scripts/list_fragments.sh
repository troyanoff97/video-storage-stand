#!/usr/bin/env bash
# List fragment metadata for a camera in a time range (Cassandra timeuuid bounds).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <camera_id> <from_rfc3339> <to_rfc3339> [limit]" >&2
  echo "  Example: $0 camera-1 2026-06-24T00:00:00Z 2026-06-24T23:59:59Z 100" >&2
  exit 1
fi

export CASSANDRA_HOSTS="${CASSANDRA_HOSTS:-127.0.0.1}"
export READ_URL="${READ_URL:-http://localhost:8882}"
export SIDEWEED_URL="${SIDEWEED_URL:-http://localhost:8880}"
export S3_BUCKET="${S3_BUCKET:-video-fragments}"
export S3_ACCESS_KEY="${S3_ACCESS_KEY:-stand_access_key}"
export S3_REGION="${S3_REGION:-us-east-1}"

if [[ ! -x ./bin/fragment ]]; then
  make build-cli
fi

echo "==> LIST fragments (camera=$1, from=$2, to=$3, limit=${4:-100})" >&2
./bin/fragment list "$@"
