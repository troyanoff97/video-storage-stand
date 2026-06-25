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
  sim_log "Nothing to clean (DISK_SIM_ROOT missing)"
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

force_teardown_sim

sim_log "Removing $root_real"
rm -rf "$root_real"

sim_log "Cleanup complete"
