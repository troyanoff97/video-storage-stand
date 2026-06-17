#!/usr/bin/env bash
# Remove fill file on /vol so writes recover (no container restart).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_recovery_disk.sh"

VOLUME="${1:-volume1}"

echo "Soft reset ${VOLUME} /vol (remove fill file)..."

compose up -d "$VOLUME"
sleep 2

CID=$(compose ps -q "$VOLUME")
docker exec "$CID" sh -c '
  rm -f /vol/fill /vol/.writable_probe /vol/.wprobe
  df -h /vol
'

sleep 5
echo "Done."
