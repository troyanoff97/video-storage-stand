#!/usr/bin/env bash
# Upload fragment with assign pinned to volume1 (replication=000; stop volume2 or retry).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

export REPLICATION=000
export DATA_CENTER=dc1

FILE="${1:?usage: put_to_volume1.sh <file> <camera_id>}"
CAMERA="${2:?usage: put_to_volume1.sh <file> <camera_id>}"

MAX_ATTEMPTS="${PUT_V1_MAX_ATTEMPTS:-10}"

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  set +e
  out=$(
    DATA_CENTER=dc1 REPLICATION=000 "${ROOT_DIR}/scripts/put_fragment.sh" \
      "$FILE" "${CAMERA}-try${attempt}" 2>&1
  )
  code=$?
  set -e

  if [ "$code" -ne 0 ]; then
    echo "$out" >&2
    exit "$code"
  fi

  if echo "$out" | grep -q 'volume1:8080'; then
    echo "$out"
    exit 0
  fi

  echo "assign missed volume1 (attempt ${attempt}), retrying..." >&2
done

echo "ERROR: could not assign to volume1 after ${MAX_ATTEMPTS} attempts (stop volume2 to force pin)" >&2
exit 1
