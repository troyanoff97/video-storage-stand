#!/usr/bin/env bash
# DEBUG ONLY: curl master /dir/assign (internal API, not production client path).
set -euo pipefail

MASTER_URL="${MASTER_URL:-http://localhost:9333}"
REPLICATION="${REPLICATION:-000}"
COLLECTION="${COLLECTION:-}"

url="${MASTER_URL}/dir/assign?count=1&replication=${REPLICATION}"
if [[ -n "$COLLECTION" ]]; then
  url="${url}&collection=${COLLECTION}"
fi
if [[ -n "${DATA_CENTER:-}" ]]; then
  url="${url}&dataCenter=${DATA_CENTER}"
fi

echo "==> [DEBUG] GET ${url}"
curl -s -w "\nHTTP_CODE:%{http_code}\n" "${url}"
