#!/usr/bin/env bash
# Restore /data1 after multi-dir chaos (remount rw, remove fill file).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_multi_dir.sh"

VOLUME="${1:-volume1}"

echo "Resetting ${VOLUME} /data1..."

compose up -d "$VOLUME"
sleep 3

compose exec --privileged "$VOLUME" sh -c '
  mount -o remount,rw /data1 2>/dev/null || true
  chmod 1777 /data1 2>/dev/null || true
  rm -f /data1/fill /data1/.ro-probe
'

echo "Waiting for disk health recovery tick (up to 70s)..."
for i in $(seq 1 14); do
  if compose logs "$VOLUME" --tail=50 2>&1 | grep -q "recovered and is healthy again"; then
    echo "Recovery log seen after $((i * 5))s"
    exit 0
  fi
  sleep 5
done

echo "WARN: recovery log not seen yet; volume may still be unhealthy on /data1"
exit 0
