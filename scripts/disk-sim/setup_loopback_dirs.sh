#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_confirm
check_dependencies
need_root_for_mount

IMG1="${DISK_SIM_ROOT}/disk1.img"
IMG2="${DISK_SIM_ROOT}/disk2.img"
MNT1="${DISK_SIM_ROOT}/mnt/stor1"
MNT2="${DISK_SIM_ROOT}/mnt/stor2"

safe_path "$DISK_SIM_ROOT" >/dev/null
mkdir -p "${DISK_SIM_ROOT}/mnt" "${DISK_SIM_ROOT}/logs"

if [[ -f "$DISK_SIM_STATE" ]]; then
  info "State file already exists: $DISK_SIM_STATE"
  load_state
  show_mount_status
  exit 0
fi

info "Creating loopback images (${DISK_SIM_SIZE_MB} MiB each)..."
mkdir -p "$(dirname "$IMG1")"
dd if=/dev/zero of="$IMG1" bs=1M count="$DISK_SIM_SIZE_MB" status=progress 2>/dev/null || \
  dd if=/dev/zero of="$IMG1" bs=1M count="$DISK_SIM_SIZE_MB"
dd if=/dev/zero of="$IMG2" bs=1M count="$DISK_SIM_SIZE_MB" status=progress 2>/dev/null || \
  dd if=/dev/zero of="$IMG2" bs=1M count="$DISK_SIM_SIZE_MB"

LOOP1="$(run_root losetup -f)"
LOOP2="$(run_root losetup -f)"
run_root losetup "$LOOP1" "$IMG1"
run_root losetup "$LOOP2" "$IMG2"

info "Formatting ext4..."
run_root mkfs.ext4 -F "$LOOP1" >/dev/null
run_root mkfs.ext4 -F "$LOOP2" >/dev/null

mkdir -p "$MNT1" "$MNT2"
run_root mount "$LOOP1" "$MNT1"
run_root mount "$LOOP2" "$MNT2"
run_root chmod 1777 "$MNT1" "$MNT2"

cat >"$DISK_SIM_STATE" <<EOF
# disk-sim state — do not edit loop device names while mounted
DISK_SIM_ROOT='$DISK_SIM_ROOT'
LOOP1='$LOOP1'
LOOP2='$LOOP2'
IMG1='$IMG1'
IMG2='$IMG2'
MNT1='$MNT1'
MNT2='$MNT2'
EOF
chmod 600 "$DISK_SIM_STATE"

info "Setup complete. State: $DISK_SIM_STATE"
show_mount_status
lsblk "$LOOP1" "$LOOP2" 2>/dev/null || true
