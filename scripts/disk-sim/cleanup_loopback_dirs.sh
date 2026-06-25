#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_confirm
check_dependencies
need_root_for_mount

# Strict guard: only delete DISK_SIM_ROOT under /tmp
root_real="$(readlink -f "$DISK_SIM_ROOT" 2>/dev/null || true)"
if [[ -z "$root_real" ]]; then
  info "Nothing to clean (DISK_SIM_ROOT missing)"
  exit 0
fi
case "$root_real" in
  /tmp/*) ;;
  *) die "Refusing cleanup outside /tmp: $root_real" ;;
esac
case "$root_real" in
  /tmp/seaweedfs-disk-sim) ;;
  *) die "Refusing cleanup: unexpected DISK_SIM_ROOT path: $root_real" ;;
esac

if [[ -f "$DISK_SIM_STATE" ]]; then
  # shellcheck source=/dev/null
  source "$DISK_SIM_STATE"
  for mnt in "$MNT1" "$MNT2"; do
    if is_mounted "$mnt" 2>/dev/null; then
      info "Unmounting $mnt"
      run_root umount "$mnt" || true
    fi
  done
  for loop in "$LOOP1" "$LOOP2"; do
    if run_root losetup "$loop" >/dev/null 2>&1; then
      info "Detaching $loop"
      run_root losetup -d "$loop" || true
    fi
  done
fi

info "Removing $root_real"
rm -rf "$root_real"

info "Cleanup complete"
