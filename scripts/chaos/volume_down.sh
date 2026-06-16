#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

VOLUME="${1:-volume1}"
echo "Stopping ${VOLUME}..."
compose stop "$VOLUME"
echo "Done. Wait ~5s for sideweed health check, then run put/get tests."
