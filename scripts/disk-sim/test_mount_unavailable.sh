#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_confirm
check_dependencies
load_state

TARGET="${1:-1}"
MNT="$(default_mount "$TARGET")"
safe_path "$MNT" >/dev/null

is_mounted "$MNT" || die "Already unmounted: $MNT"

sim_log "Unmounting ${MNT} [controlled fault]"
run_root umount "$MNT" 2>/dev/null || run_root umount -l "$MNT" 2>/dev/null || true
if is_mounted "$MNT"; then
  run_root umount -f "$MNT" 2>/dev/null || run_root umount -l "$MNT" 2>/dev/null || true
fi

if is_mounted "$MNT"; then
  die "Unmount failed: ${MNT} still mounted"
fi

sim_log "Mount unavailable confirmed for ${MNT}"
cat <<'NOTE'

Expected behavior on production:
- volume detects missing/unavailable mount path
- dir excluded from writable set; assigns use remaining dirs

Data on disk image preserved; recover_mounts.sh can remount.

NOTE

show_mount_status
