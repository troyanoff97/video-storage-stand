#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

VOLUME="${1:-volume1}"
echo "Starting ${VOLUME}..."
compose start "$VOLUME"
echo "Done. Wait for healthcheck to pass."
