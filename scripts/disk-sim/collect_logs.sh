#!/usr/bin/env bash
# Collect stand + host mount diagnostics (non-destructive).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${DISK_SIM_ROOT}/logs/${TS}"
mkdir -p "$OUT"

log() { printf '[collect_logs] %s\n' "$*"; }

save() {
  local name="$1"
  shift
  log "Saving $name"
  if "$@" >"$OUT/${name}" 2>&1; then
    :
  else
    echo "(command failed: $*)" >>"$OUT/${name}"
  fi
}

cd "$ROOT_DIR"
COMPOSE=(docker compose -f docker-compose.yml -f docker-compose.chaos.yml)

save docker-compose-ps.txt "${COMPOSE[@]}" ps
save docker-compose-logs.txt "${COMPOSE[@]}" logs --no-color --tail=500 \
  master volume1 volume2 filer s3 sideweed sideweed-read haproxy cassandra

save df-h.txt df -h
save mount.txt mount
save findmnt.txt findmnt -a
save lsblk.txt lsblk

if [[ -f "$DISK_SIM_STATE" ]]; then
  cp "$DISK_SIM_STATE" "$OUT/disk-sim-state.env"
fi

curl -fsS http://localhost:8880/v1/write-health >"$OUT/sideweed-write-health.json" 2>&1 || \
  echo "curl write-health failed" >"$OUT/sideweed-write-health.json"
curl -fsS http://localhost:8880/metrics 2>/dev/null | grep '^sideweed_' >"$OUT/sideweed-metrics.txt" || \
  echo "curl metrics failed" >"$OUT/sideweed-metrics.txt"
curl -fsS http://localhost:9333/cluster/status >"$OUT/master-cluster-status.json" 2>&1 || \
  echo "curl cluster/status failed" >"$OUT/master-cluster-status.json"
curl -fsS "http://localhost:9333/dir/assign?count=1&replication=000" >"$OUT/master-assign.json" 2>&1 || \
  echo "curl assign failed" >"$OUT/master-assign.json"

log "Logs written to $OUT"
ls -la "$OUT"
