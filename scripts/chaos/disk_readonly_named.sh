#!/usr/bin/env bash
# Read-only fault: stop volume1, remount loop image ro via force_ro flag, restart.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_recovery_disk.sh"

VOLUME="${1:-volume1}"
RECOVERY_VOL="work2_volume1_recovery"

echo "Simulating read-only store on ${VOLUME} (loop ro via force_ro)..."

compose stop "$VOLUME"
docker run --rm -v "${RECOVERY_VOL}:/meta" alpine touch /meta/force_ro
compose up -d "$VOLUME"

echo "Waiting for ${VOLUME} health after ro mount..."
for _ in $(seq 1 60); do
  if curl -sf http://localhost:8080/healthz >/dev/null 2>&1; then
    sleep 2
    if curl -sf http://localhost:8080/healthz >/dev/null 2>&1; then
      break
    fi
  fi
  sleep 1
done

CID=$(compose ps -q "$VOLUME")
if [ -z "$CID" ]; then
  echo "ERROR: ${VOLUME} container not found" >&2
  exit 1
fi

docker exec "$CID" sh -c '
  mount | grep " /vol "
  if touch /vol/.wprobe 2>/dev/null; then
    rm -f /vol/.wprobe
    echo "ERROR: /vol still writable after ro mount" >&2
    exit 1
  fi
  echo "Write probe failed as expected"
'

echo "Done. New PUT should fail; existing blob GET should still work."
