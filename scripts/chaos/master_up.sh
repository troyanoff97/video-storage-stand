#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

echo "Starting master..."
compose start master
echo "Done. Wait for volume heartbeats to recover."
