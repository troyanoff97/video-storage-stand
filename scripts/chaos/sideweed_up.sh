#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

echo "Starting sideweed..."
compose up -d sideweed
sleep 5
echo "Done."
