#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

VOLUME="${1:-volume1}"
VOLUME_DATA="work2_${VOLUME}_data"

echo "Resetting ${VOLUME} data directory and disk state..."

# Fix permissions even if the volume container cannot start (e.g. after chmod 000 /data).
docker run --rm -v "${VOLUME_DATA}:/data" alpine sh -c '
  chmod 755 /data 2>/dev/null || true
  rm -f /data/fill
' 2>/dev/null || true

compose up -d "$VOLUME"
sleep 5

compose exec --privileged "$VOLUME" sh -c '
  mount -o remount,rw /data 2>/dev/null || true
  rm -f /data/fill
' 2>/dev/null || true

echo "Restarting ${VOLUME}..."
compose restart "$VOLUME"
echo "Done. Wait for healthcheck, then verify with put_fragment.sh."
