#!/usr/bin/env bash
# DEBUG ONLY: pin master assign to volume1 via /dir/assign (direct volume POST).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
exec env REPLICATION=000 DATA_CENTER=dc1 \
  "${ROOT_DIR}/scripts/debug/put_fragment_direct.sh" "$@"
