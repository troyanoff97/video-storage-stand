#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

VOLUME="${1:-volume1}"

compose up -d "$VOLUME"
sleep 3

echo "Filling disk on ${VOLUME}..."
compose exec "$VOLUME" sh -c '
  rm -f /data/fill
  avail_kb=$(df /data | tail -1 | awk "{print \$(NF-3)}")
  if [ -z "$avail_kb" ] || ! echo "$avail_kb" | grep -Eq "^[0-9]+$"; then
    echo "Could not determine available space (avail_kb=${avail_kb})" >&2
    exit 1
  fi
  if [ "$avail_kb" -le 1024 ]; then
    echo "Not enough free space (avail_kb=${avail_kb})" >&2
    exit 1
  fi
  fill_kb=$((avail_kb - 64))
  fill_bytes=$((fill_kb * 1024))
  if command -v fallocate >/dev/null 2>&1; then
    fallocate -l "$fill_bytes" /data/fill
  else
    dd if=/dev/zero of=/data/fill bs=1M count=$((fill_kb / 1024)) status=none
  fi
  df -h /data
'

echo "Done. PUT to ${VOLUME} should fail with ENOSPC in volume logs."
