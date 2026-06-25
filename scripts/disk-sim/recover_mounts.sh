#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_confirm
check_dependencies
load_state

recover_one() {
  local mnt="$1"
  local loop_dev="$2"
  safe_path "$mnt" >/dev/null

  while is_mounted "$mnt"; do
    local opts
    opts="$(mount_options "$mnt")"
    if [[ "$opts" == *ro* ]] && [[ "$opts" != *rw* ]]; then
      sim_log "Remounting ${mnt} read-write..."
      run_root mount -o remount,rw "$mnt" || run_root umount "$mnt"
    else
      break
    fi
  done

  if ! is_mounted "$mnt"; then
    sim_log "Remounting ${mnt} from ${loop_dev}..."
    mkdir -p "$mnt"
    run_root mount "$loop_dev" "$mnt"
  fi

  rm -f "${mnt}/${DISK_SIM_FILL_NAME}" "${mnt}/.readonly-probe" "${mnt}/.writable-probe" 2>/dev/null || true

  if ! touch "${mnt}/.recover-probe" 2>/dev/null; then
    die "Recovery failed: ${mnt} not writable (options: $(mount_options "$mnt"))"
  fi
  rm -f "${mnt}/.recover-probe"
  sim_log "Recovered: ${mnt} ($(mount_options "$mnt"))"
}

recover_one "$MNT1" "$LOOP1"
recover_one "$MNT2" "$LOOP2"

sim_log "Recovery complete"
show_mount_status
