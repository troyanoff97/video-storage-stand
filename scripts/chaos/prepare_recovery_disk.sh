#!/usr/bin/env bash
# Fresh loop-backed /vol and healthy stack before recovery-disk tests.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_recovery_disk.sh"

VOLUME="${1:-volume1}"
RECOVERY_VOL="work2_volume1_recovery"

echo "Preparing ${VOLUME} for recovery-disk scenario (fresh loop ext4)..."

compose stop volume1 2>/dev/null || true
docker run --rm -v "${RECOVERY_VOL}:/meta" alpine sh -c 'rm -f /meta/disk.img' 2>/dev/null || true

compose up -d --build
compose up -d volume1 volume2
sleep 10

"${ROOT_DIR}/scripts/wait-healthy.sh"
echo "Recovery-disk stack ready."
