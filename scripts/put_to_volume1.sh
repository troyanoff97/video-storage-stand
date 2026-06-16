#!/usr/bin/env bash
# Upload fragment with assign pinned to volume1 (dataCenter=dc1, no cross-DC replica).
set -euo pipefail
export DATA_CENTER=dc1
export REPLICATION=000
exec "$(dirname "$0")/put_fragment.sh" "$@"
