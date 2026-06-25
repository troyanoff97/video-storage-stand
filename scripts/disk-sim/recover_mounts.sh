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

  if is_mounted "$mnt"; then
    local opts
    opts="$(mount_options "$mnt")"
    if [[ "$opts" == *ro* ]] && [[ "$opts" != *rw* ]]; then
      info "Remounting $mnt read-write..."
      run_root mount -o remount,rw "$mnt"
    fi
  else
    info "Remounting $mnt from $loop_dev..."
    mkdir -p "$mnt"
    run_root mount "$loop_dev" "$mnt"
  fi

  rm -f "${mnt}/${DISK_SIM_FILL_NAME}" "${mnt}/.readonly-probe" "${mnt}/.writable-probe" 2>/dev/null || true

  if ! touch "${mnt}/.recover-probe" 2>/dev/null; then
    die "Recovery failed: $mnt not writable"
  fi
  rm -f "${mnt}/.recover-probe"
  info "Recovered: $mnt ($(mount_options "$mnt"))"
}

recover_one "$MNT1" "$LOOP1"
recover_one "$MNT2" "$LOOP2"

info "Recovery complete"
show_mount_status
