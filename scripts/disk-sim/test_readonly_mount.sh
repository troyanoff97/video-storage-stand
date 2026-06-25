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

sim_log "Remounting ${MNT} read-only..."
run_root mount -o remount,ro "$MNT"

opts="$(mount_options "$MNT")"
sim_log "findmnt options: ${opts}"
if [[ "$opts" != *ro* ]]; then
  die "remount,ro did not apply (stacked mounts? run cleanup and setup again)"
fi

PROBE="${MNT}/.readonly-probe"
if touch "$PROBE" 2>/dev/null; then
  rm -f "$PROBE"
  die "Mount still writable after remount,ro"
fi

sim_log "Write probe failed as expected (read-only $MNT)"
cat <<'NOTE'

Expected behavior on production:
- volume heartbeat reports dir unhealthy / readonly
- new writes skip faulted dir; healthy dirs accept assigns

NOTE

show_mount_status
