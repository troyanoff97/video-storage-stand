#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

echo "Stopping sideweed..."
compose stop sideweed
sleep 3
echo "Done. GET via sideweed should fail; direct volume GET may still work."
