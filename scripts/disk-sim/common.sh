#!/usr/bin/env bash
# Shared helpers for host-level disk fault simulation (loopback ext4).
# All destructive ops require CONFIRM_DISK_SIM=1 and paths under DISK_SIM_ROOT.
set -euo pipefail

DISK_SIM_ROOT="${DISK_SIM_ROOT:-/tmp/seaweedfs-disk-sim}"
DISK_SIM_SIZE_MB="${DISK_SIM_SIZE_MB:-512}"
DISK_SIM_STATE="${DISK_SIM_ROOT}/state.env"
DISK_SIM_FILL_NAME=".disk-sim-fill"

log()  { printf '[disk-sim] %s\n' "$*"; }
info() { log "INFO: $*"; }
err()  { log "ERROR: $*" >&2; }

die() {
  err "$@"
  exit 1
}

require_confirm() {
  if [[ "${CONFIRM_DISK_SIM:-}" != "1" ]]; then
    die "Set CONFIRM_DISK_SIM=1 to run destructive disk-sim operations"
  fi
}

# Normalize path (resolve ..) and ensure it stays under DISK_SIM_ROOT.
safe_path() {
  local p="$1"
  local root real
  root="$(readlink -f "$DISK_SIM_ROOT" 2>/dev/null || true)"
  if [[ -z "$root" ]]; then
    root="$DISK_SIM_ROOT"
  fi
  if [[ ! -d "$root" && "$p" != "$DISK_SIM_ROOT" && "$p" != "$root" ]]; then
    die "DISK_SIM_ROOT does not exist: $DISK_SIM_ROOT (run setup first)"
  fi
  mkdir -p "$root" 2>/dev/null || true
  real="$(readlink -f "$p" 2>/dev/null || true)"
  if [[ -z "$real" ]]; then
    die "Cannot resolve path: $p"
  fi
  case "$real" in
    "$root"|"$root"/*) printf '%s\n' "$real" ;;
    *) die "Path outside DISK_SIM_ROOT refused: $p (resolved: $real)" ;;
  esac
}

check_dependencies() {
  local missing=()
  local cmd
  for cmd in losetup mkfs.ext4 mount umount df findmnt dd; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done
  if ((${#missing[@]} > 0)); then
    die "Missing commands: ${missing[*]}"
  fi
}

need_root_for_mount() {
  if [[ "$(id -u)" -eq 0 ]]; then
    return 0
  fi
  if command -v sudo >/dev/null 2>&1; then
    return 0
  fi
  die "mount/umount/losetup require root or sudo"
}

run_root() {
  need_root_for_mount
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo -E "$@"
  fi
}

load_state() {
  [[ -f "$DISK_SIM_STATE" ]] || die "State file missing: $DISK_SIM_STATE (run setup_loopback_dirs.sh)"
  # shellcheck source=/dev/null
  source "$DISK_SIM_STATE"
  : "${MNT1:?}" "${MNT2:?}" "${LOOP1:?}" "${LOOP2:?}"
  MNT1="$(safe_path "$MNT1")"
  MNT2="$(safe_path "$MNT2")"
}

default_mount() {
  local which="${1:-1}"
  if [[ "$which" == "2" ]]; then
    printf '%s\n' "$MNT2"
  else
    printf '%s\n' "$MNT1"
  fi
}

is_mounted() {
  local mnt
  mnt="$(safe_path "$1")"
  findmnt -rn -T "$mnt" >/dev/null 2>&1
}

mount_options() {
  local mnt
  mnt="$(safe_path "$1")"
  findmnt -rn -T "$mnt" -o OPTIONS 2>/dev/null | head -1 || echo "not-mounted"
}

show_mount_status() {
  info "findmnt under $DISK_SIM_ROOT:"
  findmnt -rn "$DISK_SIM_ROOT" 2>/dev/null || true
  info "df -h:"
  df -h "$DISK_SIM_ROOT"/* 2>/dev/null || df -h "$DISK_SIM_ROOT" 2>/dev/null || true
}
