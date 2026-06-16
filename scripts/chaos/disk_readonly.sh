#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

VOLUME="${1:-volume1}"

compose up -d "$VOLUME"
sleep 3

echo "Remounting ${VOLUME} /data read-only (tmpfs from docker-compose.chaos.yml)..."
compose exec "$VOLUME" sh -c '
  if ! grep -qE "[[:space:]]/data[[:space:]]" /proc/mounts; then
    echo "ERROR: /data is not a mount point; use docker-compose.chaos.yml" >&2
    exit 1
  fi
  mount -t tmpfs -o remount,ro tmpfs /data
  mount | grep "tmpfs on /data"
  touch /data/.ro-probe 2>/dev/null || echo "write probe failed (expected)"
'

echo "Done. PUT to ${VOLUME} should fail; GET of existing data may still work."
