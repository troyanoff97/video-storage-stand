#!/usr/bin/env bash
# Optional: dm-error injection if dmsetup available (requires root, CONFIRM_DISK_SIM=1).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_confirm

if ! command -v dmsetup >/dev/null 2>&1; then
  sim_log "SKIP: dmsetup not installed"
  exit 0
fi

if [[ ! -w /dev/mapper ]] && [[ "$(id -u)" -ne 0 ]]; then
  sim_log "SKIP: dmsetup requires root (try sudo)"
  exit 0
fi

cat <<'NOTE'
dm-error simulation is optional and environment-specific.

Typical flow (manual, not automated here):
  1. Create loop file + dm-linear device over loop
  2. dmsetup create error --table "0 <sectors> error"
  3. mkfs.ext4 on dm device, mount under DISK_SIM_ROOT
  4. Trigger reads/writes to observe EIO handling in weed volume

Automated dm-error can destabilize the host; run only on disposable VMs.
See docs/SEAWEEDFS-ENHANCED-DISK-SIMULATION.md §7.

NOTE

sim_log "dmsetup present; manual dm-error procedure documented in docs (no auto-run)"
