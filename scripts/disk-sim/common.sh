#!/usr/bin/env bash
# Shared helpers for host-level disk fault simulation (loopback ext4).
# All destructive ops require CONFIRM_DISK_SIM=1 and paths under DISK_SIM_ROOT.
set -euo pipefail

DISK_SIM_ROOT="${DISK_SIM_ROOT:-/tmp/seaweedfs-disk-sim}"
DISK_SIM_SIZE_MB="${DISK_SIM_SIZE_MB:-512}"
DISK_SIM_STATE="${DISK_SIM_ROOT}/state.env"
DISK_SIM_FILL_NAME=".disk-sim-fill"

log()  { printf '[disk-sim] %s\n' "$*"; }
sim_log() { log "INFO: $*"; }
ds_err()  { log "ERROR: $*" >&2; }

die() {
  ds_err "$@"
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
  elif [[ -n "${SUDO_ASKPASS:-}" ]] && [[ -x "${SUDO_ASKPASS}" ]]; then
    sudo -A -E "$@"
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
  if command -v mountpoint >/dev/null 2>&1; then
    mountpoint -q "$mnt"
  else
    findmnt -rn "$mnt" >/dev/null 2>&1
  fi
}

mount_options() {
  local mnt
  mnt="$(safe_path "$1")"
  findmnt -rn -T "$mnt" -o OPTIONS 2>/dev/null | head -1 || echo "not-mounted"
}

show_mount_status() {
  sim_log "findmnt under $DISK_SIM_ROOT:"
  findmnt -rn "$DISK_SIM_ROOT" 2>/dev/null || true
  sim_log "df -h:"
  df -h "$DISK_SIM_ROOT"/* 2>/dev/null || df -h "$DISK_SIM_ROOT" 2>/dev/null || true
}

force_teardown_sim() {
  local root img loop_dev targets
  root="$(readlink -f "$DISK_SIM_ROOT" 2>/dev/null || echo "$DISK_SIM_ROOT")"
  [[ -d "$root" ]] || return 0

  if [[ -f "$DISK_SIM_STATE" ]]; then
    # shellcheck source=/dev/null
    source "$DISK_SIM_STATE"
    for mnt in "${MNT1:-}" "${MNT2:-}"; do
      [[ -n "$mnt" ]] || continue
      while is_mounted "$mnt" 2>/dev/null; do
        run_root umount "$mnt" 2>/dev/null || break
      done
    done
    for loop in "${LOOP1:-}" "${LOOP2:-}"; do
      [[ -n "$loop" ]] && run_root losetup -d "$loop" 2>/dev/null || true
    done
    rm -f "$DISK_SIM_STATE"
  fi

  mapfile -t targets < <(findmnt -rn -o TARGET "$root" 2>/dev/null | awk '{print $1}' | sort -r)
  for target in "${targets[@]}"; do
    run_root umount "$target" 2>/dev/null || true
  done

  for img in "$root"/disk1.img "$root"/disk2.img; do
    [[ -f "$img" ]] || continue
    loop_dev="$(losetup -j "$img" 2>/dev/null | cut -d: -f1 | head -1 || true)"
    [[ -n "$loop_dev" ]] && run_root losetup -d "$loop_dev" 2>/dev/null || true
  done
}

# Compose project for stand (must match running stack, not only directory name).
detect_compose_project_name() {
  local name
  name=$(docker ps --format '{{.Names}}' --filter "publish=8080" 2>/dev/null | grep -E 'volume1-' | head -1 || true)
  if [[ -z "$name" ]]; then
    return 1
  fi
  if [[ "$name" =~ ^(.+)-volume1-[0-9]+$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

resolve_compose_project() {
  if [[ -n "${COMPOSE_PROJECT_NAME:-}" ]]; then
    printf '%s\n' "$COMPOSE_PROJECT_NAME"
    return 0
  fi
  local detected
  if detected="$(detect_compose_project_name)"; then
    printf '%s\n' "$detected"
    return 0
  fi
  basename "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
}

assert_stand_project_matches_port8080() {
  local project name holder_proj
  project="$(resolve_compose_project)"
  name=$(docker ps --format '{{.Names}}' --filter "publish=8080" 2>/dev/null | grep -E 'volume1-' | head -1 || true)
  [[ -n "$name" ]] || return 0
  if [[ "$name" =~ ^(.+)-volume1-[0-9]+$ ]]; then
    holder_proj="${BASH_REMATCH[1]}"
    if [[ "$holder_proj" != "$project" ]]; then
      die "Port 8080 held by compose project '${holder_proj}' but scripts target '${project}'. Export COMPOSE_PROJECT_NAME=${holder_proj}"
    fi
  fi
}

# Build and run docker compose for stand. Usage:
#   compose_stand "$ROOT" file1.yml file2.yml -- ps volume1
compose_stand() {
  local root_dir="$1"
  shift
  local project args=()
  project="$(resolve_compose_project)"
  args=(-p "$project")
  while [[ $# -gt 0 && "$1" != -- ]]; do
    args+=(-f "${root_dir}/$1")
    shift
  done
  [[ "${1:-}" == -- ]] && shift
  docker compose "${args[@]}" "$@"
}

recreate_compose_service() {
  local root_dir="$1"
  shift
  local service="${!#}"
  local -a files=()
  while [[ $# -gt 1 ]]; do
    files+=("$1")
    shift
  done
  compose_stand "$root_dir" "${files[@]}" -- stop "$service" 2>/dev/null || true
  compose_stand "$root_dir" "${files[@]}" -- rm -f "$service" 2>/dev/null || true
  compose_stand "$root_dir" "${files[@]}" -- up -d --no-deps "$service"
}

verify_volume1_disk_sim_binds() {
  local root_dir="$1"
  shift
  local -a files=("$@")
  local cid mnts
  cid=$(compose_stand "$root_dir" "${files[@]}" -- ps -q volume1 2>/dev/null | head -1)
  [[ -n "$cid" ]] || die "volume1 not running in compose project $(resolve_compose_project) — run e2e_up.sh first"
  mnts=$(docker inspect "$cid" --format '{{range .Mounts}}{{.Source}} {{end}}')
  if ! echo "$mnts" | grep -q "${DISK_SIM_ROOT}/mnt/stor1"; then
    die "volume1 has no bind mount to ${DISK_SIM_ROOT}/mnt/stor1 — e2e_up did not apply (check e2e_up / COMPOSE_PROJECT_NAME)"
  fi
  sim_log "volume1 bind mounts OK (disk-sim E2E active)"
}
