#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

VOLUME="${1:-volume1}"

echo "Simulating unavailable mount point on ${VOLUME} (chmod 000 /data, no restart)..."
compose exec "$VOLUME" sh -c 'chmod 000 /data'

echo "Done. PUT should fail; volume process stays up (unhealthy on next startup if restarted)."
