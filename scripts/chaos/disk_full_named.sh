#!/usr/bin/env bash
# Fill loop-mounted /vol until new writes fail (weed keeps serving reads).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_recovery_disk.sh"

VOLUME="${1:-volume1}"

compose up -d "$VOLUME"
sleep 2

echo "Filling /vol on ${VOLUME} until writes fail..."
CID=$(compose ps -q "$VOLUME")
if [ -z "$CID" ]; then
  echo "ERROR: ${VOLUME} container not found" >&2
  exit 1
fi

docker exec "$CID" sh -c '
  rm -f /vol/fill
  for pass in 1 2 3 4 5; do
    avail_kb=$(df -k /vol | tail -1 | awk "{print \$4}")
    if [ -z "$avail_kb" ] || ! echo "$avail_kb" | grep -Eq "^[0-9]+$"; then
      echo "Could not determine available space (avail_kb=${avail_kb})" >&2
      exit 1
    fi
    if [ "$avail_kb" -le 64 ]; then
      break
    fi
    fill_kb=$((avail_kb - 32))
    dd if=/dev/zero of=/vol/fill bs=1024 count="$fill_kb" 2>/dev/null || true
    if ! touch /vol/.writable_probe 2>/dev/null; then
      rm -f /vol/.writable_probe
      break
    fi
    rm -f /vol/.writable_probe
  done
  df -h /vol
  if touch /vol/.writable_probe 2>/dev/null; then
    rm -f /vol/.writable_probe
    echo "ERROR: /vol still writable after fill" >&2
    exit 1
  fi
  echo "Write probe failed as expected (disk full)"
'

echo "Done. New PUT should fail; existing blob GET should still work."
