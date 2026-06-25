#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -z "${COMPOSE_PROJECT_NAME:-}" ]]; then
  _v1=$(docker ps --format '{{.Names}}' --filter "publish=8080" 2>/dev/null | grep -E 'volume1-' | head -1 || true)
  if [[ "$_v1" =~ ^(.+)-volume1-[0-9]+$ ]]; then
    export COMPOSE_PROJECT_NAME="${BASH_REMATCH[1]}"
  fi
fi
COMPOSE=(docker compose)
[[ -n "${COMPOSE_PROJECT_NAME:-}" ]] && COMPOSE+=(-p "$COMPOSE_PROJECT_NAME")

MASTER_URL="${MASTER_URL:-http://localhost:9333}"
VOLUME1_URL="${VOLUME1_URL:-http://localhost:8080}"
VOLUME2_URL="${VOLUME2_URL:-http://localhost:8081}"
FILER_URL="${FILER_URL:-http://localhost:8888}"
S3_URL="${S3_URL:-http://localhost:8333}"
SIDEWEED_URL="${SIDEWEED_URL:-http://localhost:8880}"
READ_URL="${READ_URL:-http://localhost:8882}"
CASSANDRA_HOST="${CASSANDRA_HOST:-localhost:9042}"

wait_for() {
  local name="$1"
  local url="$2"
  local max_attempts="${3:-60}"
  local attempt=1

  echo "Waiting for ${name} at ${url}..."
  until curl -sf "$url" >/dev/null 2>&1; do
    if (( attempt >= max_attempts )); then
      echo "ERROR: ${name} not ready after ${max_attempts} attempts" >&2
      exit 1
    fi
    sleep 2
    attempt=$((attempt + 1))
  done
  echo "OK: ${name} is ready"
}

wait_for "SeaweedFS master" "${MASTER_URL}/cluster/status"
wait_for "SeaweedFS volume1" "${VOLUME1_URL}/healthz"
wait_for "SeaweedFS volume2" "${VOLUME2_URL}/healthz"
wait_for "SeaweedFS filer" "${FILER_URL}/"
wait_for "SeaweedFS S3 Gateway" "${S3_URL}/healthz"
wait_for "sideweed (write)" "${SIDEWEED_URL}/v1/health"
wait_for "HAProxy (read path)" "${READ_URL}/healthz"

echo "Waiting for Cassandra at ${CASSANDRA_HOST}..."
attempt=1
max_attempts=60
until "${COMPOSE[@]}" exec -T cassandra cqlsh -e "DESCRIBE CLUSTER" >/dev/null 2>&1; do
  if (( attempt >= max_attempts )); then
    echo "ERROR: Cassandra not ready after ${max_attempts} attempts" >&2
    exit 1
  fi
  sleep 2
  attempt=$((attempt + 1))
done
echo "OK: Cassandra is ready"

echo "Applying schema (idempotent)..."
"${COMPOSE[@]}" run --rm cql-init

echo "All services are healthy."
