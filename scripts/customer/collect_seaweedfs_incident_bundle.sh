#!/usr/bin/env bash
# collect_seaweedfs_incident_bundle.sh — read-only incident data collection.
# Does NOT modify configs, restart services, or delete files.
# Config files with secrets: send separately with redaction (see docs/CUSTOMER-INCIDENT-DIAGNOSTICS.md).

set -euo pipefail

INCIDENT_SINCE="${INCIDENT_SINCE:-}"
INCIDENT_UNTIL="${INCIDENT_UNTIL:-}"
SIDEWEED_URL="${SIDEWEED_URL:-}"
SEAWEED_MASTER_URL="${SEAWEED_MASTER_URL:-}"
OUTPUT_BASE="${OUTPUT_DIR:-/tmp}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
COLLECT_DIR="${OUTPUT_BASE}/seaweedfs-incident-${TS}"

mkdir -p "${COLLECT_DIR}"
BUNDLE="${OUTPUT_BASE}/seaweedfs-incident-${TS}.tar.gz"
LOG="${COLLECT_DIR}/collect.log"

log() { echo "[$(date -Iseconds)] $*" | tee -a "${LOG}"; }
warn() { log "WARNING: $*"; }

run_optional() {
  local desc="$1"
  shift
  if ! command -v "$1" >/dev/null 2>&1; then
    warn "command not found: $1 ($desc)"
    return 0
  fi
  log "==> $desc"
  if ! "$@" >>"${LOG}" 2>&1; then
    warn "$desc failed (exit $?)"
  fi
}

run_systemctl() {
  local unit="$1"
  if ! command -v systemctl >/dev/null 2>&1; then
    warn "systemctl not available"
    return 0
  fi
  log "==> systemctl status ${unit}"
  if systemctl status "${unit}" --no-pager >>"${LOG}" 2>&1; then
    :
  else
    warn "systemctl status ${unit} failed or unit missing"
  fi
}

run_journal() {
  local unit="$1"
  local since="${2:-}"
  local until="${3:-}"
  if ! command -v journalctl >/dev/null 2>&1; then
    warn "journalctl not available"
    return 0
  fi
  local args=(-u "${unit}" --no-pager -o short-iso)
  [[ -n "${since}" ]] && args+=(--since "${since}")
  [[ -n "${until}" ]] && args+=(--until "${until}")
  log "==> journalctl ${unit} (since=${since:-all} until=${until:-now})"
  if ! journalctl "${args[@]}" >>"${COLLECT_DIR}/journal-${unit}.log" 2>>"${LOG}"; then
    warn "journalctl ${unit} failed"
  fi
}

curl_safe() {
  local name="$1"
  local url="$2"
  local out="${COLLECT_DIR}/${name}"
  if ! command -v curl >/dev/null 2>&1; then
    warn "curl not available for ${name}"
    return 0
  fi
  log "==> curl ${url}"
  if curl -fsS --connect-timeout 5 --max-time 30 "${url}" -o "${out}" 2>>"${LOG}"; then
    log "saved ${out}"
  else
    warn "curl failed: ${url}"
    rm -f "${out}"
  fi
}

log "Starting SeaweedFS incident bundle collection"
log "COLLECT_DIR=${COLLECT_DIR}"

{
  echo "=== hostname ==="
  hostname -f 2>/dev/null || hostname
  echo "=== date ==="
  date -Iseconds
  echo "=== uptime ==="
  uptime
} >"${COLLECT_DIR}/host.txt"

run_optional "uptime" uptime

for unit in weed-volume weed-master weed-filer sideweed haproxy varnish cassandra; do
  run_systemctl "${unit}"
done

if [[ -n "${INCIDENT_SINCE}" || -n "${INCIDENT_UNTIL}" ]]; then
  run_journal "weed-volume" "${INCIDENT_SINCE}" "${INCIDENT_UNTIL}"
else
  run_journal "weed-volume" "" ""
fi
run_journal "weed-master" "" ""
run_journal "weed-filer" "" ""

if command -v dmesg >/dev/null 2>&1; then
  log "==> dmesg -T"
  if dmesg -T >"${COLLECT_DIR}/dmesg.txt" 2>>"${LOG}"; then
    :
  else
    dmesg >"${COLLECT_DIR}/dmesg.txt" 2>>"${LOG}" || warn "dmesg failed"
  fi
else
  warn "dmesg not available"
fi

for bin in mount findmnt df lsblk; do
  if command -v "${bin}" >/dev/null 2>&1; then
    log "==> ${bin}"
    case "${bin}" in
      findmnt) findmnt -a >"${COLLECT_DIR}/${bin}.txt" 2>>"${LOG}" || warn "findmnt failed" ;;
      df) df -h >"${COLLECT_DIR}/${bin}.txt" 2>>"${LOG}" || warn "df failed" ;;
      *) "${bin}" >"${COLLECT_DIR}/${bin}.txt" 2>>"${LOG}" || warn "${bin} failed" ;;
    esac
  else
    warn "${bin} not found"
  fi
done

if [[ -n "${SIDEWEED_URL}" ]]; then
  base="${SIDEWEED_URL%/}"
  curl_safe "sideweed-write-health.json" "${base}/v1/write-health"
  if command -v curl >/dev/null 2>&1; then
    log "==> sideweed metrics (sideweed_* only)"
    if curl -fsS --connect-timeout 5 --max-time 30 "${base}/metrics" 2>>"${LOG}" \
      | grep '^sideweed_' >"${COLLECT_DIR}/sideweed-metrics.txt"; then
      :
    else
      warn "sideweed metrics scrape failed"
      rm -f "${COLLECT_DIR}/sideweed-metrics.txt"
    fi
  fi
else
  warn "SIDEWEED_URL not set — skipping sideweed HTTP checks"
fi

if [[ -n "${SEAWEED_MASTER_URL}" ]]; then
  mbase="${SEAWEED_MASTER_URL%/}"
  curl_safe "master-cluster-status.json" "${mbase}/cluster/status"
  curl_safe "master-dir-assign.json" "${mbase}/dir/assign?count=1&replication=000"
else
  warn "SEAWEED_MASTER_URL not set — skipping master HTTP checks"
fi

printf '[%s] ==> creating tar.gz bundle\n' "$(date -Iseconds)" >>"${LOG}"
tar_rc=0
tar -czf "${BUNDLE}" -C "${COLLECT_DIR}" . >>"${LOG}" 2>&1 || tar_rc=$?
if (( tar_rc != 0 )); then
  warn "tar failed (exit ${tar_rc})"
fi

log "Bundle: ${BUNDLE}"
log "Done. Send configs separately with secrets redacted."
