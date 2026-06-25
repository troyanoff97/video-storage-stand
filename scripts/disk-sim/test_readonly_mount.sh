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

is_mounted "$MNT" || die "Mount not active: $MNT"

info "Remounting $MNT read-only..."
run_root mount -o remount,ro "$MNT"

info "findmnt options: $(mount_options "$MNT")"

PROBE="${MNT}/.readonly-probe"
if touch "$PROBE" 2>/dev/null; then
  rm -f "$PROBE"
  die "Mount still writable after remount,ro"
fi

info "Write probe failed as expected (read-only $MNT)"
cat <<'NOTE'

Expected behavior on production:
- volume heartbeat reports dir unhealthy / readonly
- new writes skip faulted dir; healthy dirs accept assigns

NOTE

show_mount_status
