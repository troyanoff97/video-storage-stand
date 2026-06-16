#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

echo "Stopping master..."
compose stop master
echo "Done. /dir/assign will fail; GET by known fid may still work via sideweed."
