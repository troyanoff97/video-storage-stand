#!/usr/bin/env bash
# Remount /data rw without recreating the container (bind-mount keeps files on host).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_recovery_disk.sh"

VOLUME="${1:-volume1}"

echo "Soft reset ${VOLUME} /data (bind mount, no recreate)..."

compose up -d "$VOLUME"
sleep 2

compose exec --privileged "$VOLUME" sh -c '
  mount -o remount,rw /data 2>/dev/null || true
  chmod 755 /data 2>/dev/null || true
  rm -f /data/fill /data/.ro-probe
'

echo "Restarting ${VOLUME} process to reload volumes from disk..."
compose restart "$VOLUME"
sleep 10
