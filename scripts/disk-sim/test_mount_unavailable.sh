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
safe_path "$MNT" >/dev/null"

is_mounted "$MNT" || die "Already unmounted: $MNT"

info "Unmounting $MNT (controlled fault)..."
run_root umount "$MNT"

if is_mounted "$MNT"; then
  die "Unmount failed: $MNT still mounted"
fi

info "Mount unavailable confirmed for $MNT"
cat <<'NOTE'

Expected behavior on production:
- volume detects missing/unavailable mount path
- dir excluded from writable set; assigns use remaining dirs

Data on disk image preserved; recover_mounts.sh can remount.

NOTE

show_mount_status
