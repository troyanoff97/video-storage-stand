#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

VOLUME="${1:-volume1}"

echo "Simulating unavailable mount point on ${VOLUME} (chmod 000 /data)..."
compose exec "$VOLUME" sh -c 'chmod 000 /data'

echo "Restarting ${VOLUME}..."
compose restart "$VOLUME"
echo "Done. PUT should fail; /healthz may still return 200."
