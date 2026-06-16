#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

echo "Stopping all volume servers..."
compose stop volume1 volume2
sleep 3
echo "Done. PUT/assign should fail until volumes are started."
