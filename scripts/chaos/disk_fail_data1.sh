#!/usr/bin/env bash
# Fault /data1 on multi-dir volume1; /data2 should stay writable.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_multi_dir.sh"

MODE="${1:-fill}"
VOLUME="${2:-volume1}"

compose up -d "$VOLUME"
sleep 3

case "$MODE" in
  fill)
    echo "Filling /data1 on ${VOLUME} (multi-dir)..."
    compose exec "$VOLUME" sh -c '
      rm -f /data1/fill
      avail_kb=$(df /data1 | tail -1 | awk "{print \$(NF-3)}")
      if [ -z "$avail_kb" ] || ! echo "$avail_kb" | grep -Eq "^[0-9]+$"; then
        echo "Could not determine /data1 free space (avail_kb=${avail_kb})" >&2
        exit 1
      fi
      fill_kb=$((avail_kb - 64))
      fill_bytes=$((fill_kb * 1024))
      if command -v fallocate >/dev/null 2>&1; then
        fallocate -l "$fill_bytes" /data1/fill
      else
        dd if=/dev/zero of=/data1/fill bs=1M count=$((fill_kb / 1024)) status=none
      fi
      df -h /data1 /data2
    '
    ;;
  readonly)
    echo "Remounting /data1 read-only on ${VOLUME}..."
    compose exec "$VOLUME" sh -c '
      if ! grep -qE "[[:space:]]/data1[[:space:]]" /proc/mounts; then
        echo "ERROR: /data1 is not a mount point; use docker-compose.multi-dir.yml" >&2
        exit 1
      fi
      mount -t tmpfs -o remount,ro tmpfs /data1
      mount | grep "tmpfs on /data1"
      touch /data1/.ro-probe 2>/dev/null || echo "write probe on /data1 failed (expected)"
      touch /data2/.rw-probe && echo "/data2 still writable"
    '
    ;;
  *)
    echo "Usage: disk_fail_data1.sh [fill|readonly] [volume1]" >&2
    exit 1
    ;;
esac

echo "Done. New volume growth on /data1 should fail; /data2 should accept writes."
