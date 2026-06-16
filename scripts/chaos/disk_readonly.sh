#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

VOLUME="${1:-volume1}"

echo "Remounting /data read-only on ${VOLUME}..."
compose exec --privileged "$VOLUME" sh -c '
  mount -o remount,ro /data 2>/dev/null || {
    echo "Direct remount failed; trying bind mount workaround..."
    mkdir -p /data_ro
    mount --bind /data /data_ro
    mount -o remount,ro /data_ro
    mount --bind /data_ro /data
  }
'

echo "Done. PUT should fail; GET of existing data may still work."
