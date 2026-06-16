#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MASTER_URL="${MASTER_URL:-http://localhost:9333}"
VOLUME1_URL="${VOLUME1_URL:-http://localhost:8080}"
VOLUME2_URL="${VOLUME2_URL:-http://localhost:8081}"
SIDEWEED_URL="${SIDEWEED_URL:-http://localhost:8880}"
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
wait_for "sideweed" "${SIDEWEED_URL}/v1/health"

echo "Waiting for Cassandra at ${CASSANDRA_HOST}..."
attempt=1
max_attempts=60
until docker compose exec -T cassandra cqlsh -e "DESCRIBE CLUSTER" >/dev/null 2>&1; do
  if (( attempt >= max_attempts )); then
    echo "ERROR: Cassandra not ready after ${max_attempts} attempts" >&2
    exit 1
  fi
  sleep 2
  attempt=$((attempt + 1))
done
echo "OK: Cassandra is ready"

echo "Applying schema (idempotent)..."
docker compose run --rm cql-init

echo "All services are healthy."
