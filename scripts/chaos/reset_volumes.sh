#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

VOLUME="${1:-volume1}"

echo "Resetting ${VOLUME} data directory and disk state..."

compose exec --privileged "$VOLUME" sh -c '
  chmod 755 /data
  rm -f /data/fill
  mount -o remount,rw /data 2>/dev/null || true
' 2>/dev/null || compose exec "$VOLUME" sh -c 'chmod 755 /data; rm -f /data/fill'

echo "Restarting ${VOLUME}..."
compose restart "$VOLUME"
echo "Done. Wait for healthcheck, then verify with put_fragment.sh."
