#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

VOLUME="${1:-volume1}"

compose up -d "$VOLUME"
sleep 3

echo "Filling disk on ${VOLUME} (expect ENOSPC on new writes)..."
compose exec "$VOLUME" sh -c '
  rm -f /data/fill
  for pass in 1 2 3; do
    avail_kb=$(df -k /data | tail -1 | awk "{print \$4}")
    if [ -z "$avail_kb" ] || ! echo "$avail_kb" | grep -Eq "^[0-9]+$"; then
      echo "Could not determine available space (avail_kb=${avail_kb})" >&2
      exit 1
    fi
    if [ "$avail_kb" -le 64 ]; then
      break
    fi
    fill_kb=$((avail_kb - 32))
    dd if=/dev/zero of=/data/fill bs=1024 count="$fill_kb" 2>/dev/null || true
    if ! touch /data/.writable_probe 2>/dev/null; then
      rm -f /data/.writable_probe
      break
    fi
    rm -f /data/.writable_probe
  done
  df -h /data
  if touch /data/.writable_probe 2>/dev/null; then
    rm -f /data/.writable_probe
    echo "ERROR: /data still writable after fill" >&2
    exit 1
  fi
  echo "Write probe failed as expected (disk full or ro)"
'

echo "Done. PUT/assign on ${VOLUME} should fail."
