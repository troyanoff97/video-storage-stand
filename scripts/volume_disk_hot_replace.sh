#!/usr/bin/env bash
# Hot-replace a failed disk on a running weed-volume (no process restart).
# add/remove persist to -dir.config and survive systemctl restart (no systemd -dir edit).
#
# Typical flow (customer case):
#   1) failed dir marked unhealthy by volume disk-health
#   2) remove dir from volume server (force if volumes still registered)
#   3) umount / replace physical disk / format / mount
#      OR mount a brand-new path (e.g. /mnt/stor5) — no systemd edit
#   4) add dir back (or add /mnt/stor5) to the same volume server
#
# Usage:
#   VOLUME_URL=http://127.0.0.1:8088 DIR=/mnt/stor4 ./scripts/volume_disk_hot_replace.sh remove
#   VOLUME_URL=http://127.0.0.1:8088 DIR=/mnt/stor4 MAX=0 MIN_FREE=50GiB ./scripts/volume_disk_hot_replace.sh add
#   VOLUME_URL=http://127.0.0.1:8088 ./scripts/volume_disk_hot_replace.sh list
set -euo pipefail

VOLUME_URL="${VOLUME_URL:?set VOLUME_URL e.g. http://127.0.0.1:8088}"
ACTION="${1:-}"

curl_json() {
  local method="$1"
  local path="$2"
  shift 2
  curl -fsS -X "$method" "${VOLUME_URL}${path}" "$@"
}

case "$ACTION" in
  list)
    curl_json GET /admin/disk/list
    echo
    ;;
  add)
    DIR="${DIR:?set DIR e.g. /mnt/stor5}"
    MAX="${MAX:-0}"
    MIN_FREE="${MIN_FREE:-50GiB}"
    DISK="${DISK:-}"
    curl_json POST "/admin/disk/add" \
      --data-urlencode "dir=${DIR}" \
      --data-urlencode "max=${MAX}" \
      --data-urlencode "minFreeSpace=${MIN_FREE}" \
      --data-urlencode "disk=${DISK}"
    echo
    ;;
  remove)
    DIR="${DIR:?set DIR e.g. /mnt/stor4}"
    FORCE="${FORCE:-true}"
    curl_json POST "/admin/disk/remove" \
      --data-urlencode "dir=${DIR}" \
      --data-urlencode "force=${FORCE}"
    echo
    ;;
  *)
    cat >&2 <<'EOF'
Usage: volume_disk_hot_replace.sh {list|add|remove}

Env:
  VOLUME_URL   volume HTTP admin base (required)
  DIR          disk directory for add/remove
  MAX          max volumes for add (default 0 = unlimited/auto)
  MIN_FREE     minFreeSpace for add (default 50GiB)
  FORCE        force remove with volumes (default true)
EOF
    exit 1
    ;;
esac
