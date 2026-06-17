#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

VOLUME="${1:-volume1}"

compose up -d "$VOLUME"
sleep 2

echo "Simulating unavailable /data on ${VOLUME} (tmpfs remount ro)..."
compose exec --privileged "$VOLUME" sh -c '
  if ! grep -qE "[[:space:]]/data[[:space:]]" /proc/mounts; then
    echo "ERROR: /data is not a mount point; use docker-compose.chaos.yml" >&2
    exit 1
  fi
  mount -t tmpfs -o remount,ro tmpfs /data
  mount | grep "tmpfs on /data"
  if touch /data/.ro-probe 2>/dev/null; then
    rm -f /data/.ro-probe
    echo "ERROR: /data still writable after remount ro" >&2
    exit 1
  fi
  echo "Write probe failed as expected"
'

echo "Done. Assign/PUT on ${VOLUME} should fail until remount rw."
