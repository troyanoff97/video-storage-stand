#!/usr/bin/env bash
# Remount /data rw on tmpfs — no container restart (preserves tmpfs data).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

VOLUME="${1:-volume1}"

echo "Soft reset ${VOLUME} /data tmpfs (no container restart)..."

compose up -d "$VOLUME"
sleep 2

compose exec --privileged "$VOLUME" sh -c '
  mount -o remount,rw /data 2>/dev/null || mount -t tmpfs -o remount,rw tmpfs /data
  chmod 1777 /data 2>/dev/null || true
  rm -f /data/fill /data/.ro-probe /data/.writable_probe
'

echo "Done."
