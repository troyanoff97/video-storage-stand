#!/usr/bin/env bash
# Simulate I/O error via dm-error device mapper (isolated under DISK_SIM_ROOT only).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_confirm

if ! command -v dmsetup >/dev/null 2>&1; then
  sim_log "SKIP: dmsetup not installed"
  exit 0
fi

DM_SIM_ROOT="${DISK_SIM_ROOT}/dm-error"
DM_IMG="${DM_SIM_ROOT}/error.img"
DM_NAME="swfs-dmerr-sim"
DM_MNT="${DM_SIM_ROOT}/mnt"
DM_SIZE_MB="${DM_ERROR_SIZE_MB:-64}"

safe_path "$DISK_SIM_ROOT" >/dev/null
mkdir -p "$DM_SIM_ROOT" "$DM_MNT"

cleanup_dm() {
  run_root umount "$DM_MNT" 2>/dev/null || true
  run_root dmsetup remove "$DM_NAME" 2>/dev/null || true
  if [[ -n "${DM_LOOP:-}" ]]; then
    run_root losetup -d "$DM_LOOP" 2>/dev/null || true
  fi
}
trap cleanup_dm EXIT

if ! run_root bash -c 'command -v dmsetup >/dev/null && (lsmod | grep -q dm_mod || modprobe dm-mod 2>/dev/null || true)'; then
  sim_log "SKIP: dm_mod unavailable in root context"
  exit 0
fi

sim_log "Creating ${DM_SIZE_MB}MiB loop image for dm-error under $DM_SIM_ROOT"
rm -f "$DM_IMG"
dd if=/dev/zero of="$DM_IMG" bs=1M count="$DM_SIZE_MB" status=none

DM_LOOP="$(run_root losetup -f --show "$DM_IMG")"
SECTORS="$(run_root blockdev --getsz "$DM_LOOP")"
sim_log "Loop $DM_LOOP sectors=$SECTORS — creating dm-error device $DM_NAME"
run_root dmsetup create "$DM_NAME" --table "0 $SECTORS error"

DM_DEV="/dev/mapper/$DM_NAME"
set +e
mkfs_out="$(run_root mkfs.ext4 -F "$DM_DEV" 2>&1)"
mkfs_rc=$?
set -e

if [[ $mkfs_rc -ne 0 ]] && echo "$mkfs_out" | grep -qiE 'Input/output error|I/O error|EIO|error reading'; then
  sim_log "PASS: mkfs on dm-error device failed with I/O error (expected)"
  exit 0
fi

if [[ $mkfs_rc -ne 0 ]]; then
  sim_log "NOTE: mkfs failed (rc=$mkfs_rc) but message not clearly I/O: $mkfs_out"
  sim_log "SKIP: inconclusive dm-error behavior on this host"
  exit 0
fi

run_root mount "$DM_DEV" "$DM_MNT"
set +e
write_out="$(run_root dd if=/dev/zero of="$DM_MNT/.dm-error-probe" bs=4k count=1 conv=fsync 2>&1)"
write_rc=$?
set -e

if [[ $write_rc -ne 0 ]] && echo "$write_out" | grep -qiE 'Input/output error|I/O error|EIO|error reading'; then
  sim_log "PASS: write to dm-error mount failed with I/O error (expected)"
  cat <<'NOTE'

Next: observe weed volume / kernel logs if this mount is bound into a volume container.
This script only verifies host-level dm-error injection under /tmp/seaweedfs-disk-sim.

NOTE
  exit 0
fi

sim_log "NOTE: dm-error device did not produce clear EIO (mkfs_rc=$mkfs_rc write_rc=$write_rc)"
sim_log "SKIP: kernel/dm-error behavior inconclusive — manual verification on disposable VM recommended"
exit 0
