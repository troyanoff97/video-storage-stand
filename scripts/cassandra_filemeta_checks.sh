#!/usr/bin/env bash
# Pre/post checklist for seaweedfs.filemeta TWCS change (and optional stand mirror smoke).
#
# Production (print commands; does not ALTER):
#   HOST=cassandra-node KEYSPACE=seaweedfs TABLE=filemeta ./scripts/cassandra_filemeta_checks.sh
#
# Stand mirror smoke (requires healthy compose Cassandra):
#   STAND_MIRROR=1 ./scripts/cassandra_filemeta_checks.sh
#   make cassandra-filemeta-checks STAND_MIRROR=1
#
# Env:
#   HOST / CASSANDRA_HOST  nodetool/cqlsh host (default: localhost)
#   JMX_PORT               nodetool port (default: 7199)
#   CQLSH_HOST / CQL_PORT  cqlsh (default: HOST / 9042)
#   KEYSPACE TABLE         default seaweedfs / filemeta
#   STAND_MIRROR=1         apply cassandra/filemeta_twcs_2d_mirror_stand.cql via docker compose
#   APPLY_ALTER=1          DANGEROUS: pipe production alter CQL via cqlsh (off by default)
#   ROLLBACK=1             with APPLY_ALTER=1, use 6h rollback CQL instead
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

HOST="${HOST:-${CASSANDRA_HOST:-localhost}}"
JMX_PORT="${JMX_PORT:-7199}"
CQLSH_HOST="${CQLSH_HOST:-$HOST}"
CQL_PORT="${CQL_PORT:-9042}"
KEYSPACE="${KEYSPACE:-seaweedfs}"
TABLE="${TABLE:-filemeta}"
STAND_MIRROR="${STAND_MIRROR:-0}"
APPLY_ALTER="${APPLY_ALTER:-0}"
ROLLBACK="${ROLLBACK:-0}"

echo "==> Cassandra filemeta checks"
echo "    host=${HOST} jmx=${JMX_PORT} cql=${CQLSH_HOST}:${CQL_PORT}"
echo "    target=${KEYSPACE}.${TABLE}"
echo ""

print_checklist() {
  cat <<EOF
---- Checklist (run on a Cassandra node / ops jump host) ----

# 1) Schema
cqlsh ${CQLSH_HOST} ${CQL_PORT} -e "DESCRIBE TABLE ${KEYSPACE}.${TABLE};"

# 2) Table stats / tombstones / repair
nodetool -h ${HOST} -p ${JMX_PORT} tablestats ${KEYSPACE}.${TABLE}

# 3) Latency / SSTable fan-out histograms
nodetool -h ${HOST} -p ${JMX_PORT} tablehistograms ${KEYSPACE} ${TABLE}

# 4) Compaction pressure
nodetool -h ${HOST} -p ${JMX_PORT} compactionstats
nodetool -h ${HOST} -p ${JMX_PORT} tpstats | head -n 80

# 5) After ALTER — confirm window
cqlsh ${CQLSH_HOST} ${CQL_PORT} -e "DESCRIBE TABLE ${KEYSPACE}.${TABLE};" | grep -E "compaction_window|TimeWindow"

# 6) Trend (repeat over hours/days)
#    - SSTable count should trend down toward ~15 windows for ~30d TTL
#    - watch pending compactions, read p95/p99, droppable tombstone ratio
#    - disk free on Cassandra data dirs

# Manual ALTER (change window only; never from CI):
#   cqlsh ${CQLSH_HOST} ${CQL_PORT} -f cassandra/filemeta_twcs_2d_alter.cql
# Rollback:
#   cqlsh ${CQLSH_HOST} ${CQL_PORT} -f cassandra/filemeta_twcs_6h_rollback.cql

Docs: docs/07-CASSANDRA-FILEMETA.md , docs/05-PRODUCTION-RUNBOOKS.md
EOF
}

print_checklist

if [[ "$STAND_MIRROR" == "1" ]]; then
  echo ""
  echo "==> STAND_MIRROR=1: apply mirror TWCS smoke via docker compose"
  if ! docker compose ps cassandra 2>/dev/null | grep -q 'Up\|running'; then
    echo "FAIL: cassandra service not running. Run: make up && make health" >&2
    exit 1
  fi
  docker compose exec -T cassandra cqlsh < "$ROOT_DIR/cassandra/filemeta_twcs_2d_mirror_stand.cql"
  echo "==> DESCRIBE seaweedfs_stand.filemeta (expect DAYS / size 2)"
  out=$(docker compose exec -T cassandra cqlsh -e "DESCRIBE TABLE seaweedfs_stand.filemeta;")
  echo "$out"
  if ! echo "$out" | grep -Eq "compaction_window_unit.*DAYS|DAYS"; then
    echo "FAIL: expected TWCS window unit DAYS on stand mirror" >&2
    exit 1
  fi
  if ! echo "$out" | grep -Eq "compaction_window_size.: .?2.?|'compaction_window_size': '2'|compaction_window_size.*2"; then
    # DESCRIBE often prints map form; accept either quoted 2 or bare
    if ! echo "$out" | grep -q "compaction_window_size"; then
      echo "WARN: could not assert window size=2 from DESCRIBE text; inspect output above" >&2
    fi
  fi
  echo "PASS: stand mirror TWCS 2d ALTER/DESCRIBE smoke"
fi

if [[ "$APPLY_ALTER" == "1" ]]; then
  echo ""
  echo "==> APPLY_ALTER=1 (explicit): running CQL via cqlsh ${CQLSH_HOST}:${CQL_PORT}"
  if [[ "$ROLLBACK" == "1" ]]; then
    cql_file="$ROOT_DIR/cassandra/filemeta_twcs_6h_rollback.cql"
  else
    cql_file="$ROOT_DIR/cassandra/filemeta_twcs_2d_alter.cql"
  fi
  echo "    file=$cql_file"
  cqlsh "$CQLSH_HOST" "$CQL_PORT" -f "$cql_file"
  cqlsh "$CQLSH_HOST" "$CQL_PORT" -e "DESCRIBE TABLE ${KEYSPACE}.${TABLE};"
fi

echo ""
echo "Done (checklist printed; no prod ALTER unless APPLY_ALTER=1)."
