#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

VOLUME="${1:-volume1}"

echo "Filling disk on ${VOLUME}..."
compose exec "$VOLUME" sh -c '
  rm -f /data/fill
  avail=$(df --output=avail -B1 /data 2>/dev/null | tail -1 | tr -d " ")
  if [ -z "$avail" ] || [ "$avail" -le 0 ]; then
    echo "Could not determine available space" >&2
    exit 1
  fi
  # Leave a small margin to avoid immediate crash
  fill_size=$((avail - 1048576))
  if [ "$fill_size" -le 0 ]; then
    echo "Not enough free space margin" >&2
    exit 1
  fi
  if command -v fallocate >/dev/null 2>&1; then
    fallocate -l "$fill_size" /data/fill
  else
    dd if=/dev/zero of=/data/fill bs=1M count=$((fill_size / 1048576)) status=none
  fi
  df -h /data
'

echo "Done. PUT should fail with ENOSPC in volume logs."
