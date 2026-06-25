#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_confirm
load_state

TARGET="${1:-1}"
MNT="$(default_mount "$TARGET")"
safe_path "$MNT" >/dev/null

is_mounted "$MNT" || die "Mount not active: $MNT (run recover_mounts.sh or setup)"

FILL="${MNT}/${DISK_SIM_FILL_NAME}"
rm -f "$FILL" 2>/dev/null || true

info "Filling $MNT until ENOSPC..."
set +e
for pass in $(seq 1 20); do
  avail_kb=$(df -k "$MNT" | tail -1 | awk '{print $4}')
  if [[ -z "$avail_kb" ]] || ! [[ "$avail_kb" =~ ^[0-9]+$ ]]; then
    die "Cannot read df for $MNT"
  fi
  if (( avail_kb <= 64 )); then
    break
  fi
  fill_kb=$((avail_kb - 32))
  dd if=/dev/zero of="$FILL" bs=1024 count="$fill_kb" conv=notrunc oflag=append 2>/dev/null
done
set -e

df -h "$MNT"
if touch "${MNT}/.writable-probe" 2>/dev/null; then
  rm -f "${MNT}/.writable-probe"
  die "Mount still writable after fill — simulation failed"
fi

info "Write probe failed as expected (disk full on $MNT)"
cat <<'NOTE'

Expected behavior on production weed volume (per-dir):
- volume marks dir unhealthy / readonly when minFreeSpace or ENOSPC
- master stops assigning new volumes on faulted dir
- writes continue on healthy dirs (multi-dir layout)

This script validates host-level ENOSPC on controlled ext4 only.
Wire into docker volume -dir bind for full stack integration (optional).

NOTE
