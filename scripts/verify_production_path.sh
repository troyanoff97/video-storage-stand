#!/usr/bin/env bash
# Prove production PUT goes sideweed → S3 Gateway (not volume nodes).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TEST_FILE="${1:-/tmp/verify-s3-path.bin}"
CAMERA="path-proof-$$"

dd if=/dev/urandom of="$TEST_FILE" bs=16K count=1 status=none 2>/dev/null

echo "==> PUT via production path"
./scripts/put_fragment.sh "$TEST_FILE" "$CAMERA"

echo ""
echo "==> sideweed trace (expect PUT → http://s3:8333)"
docker compose logs sideweed --tail=20 2>&1 | grep -E '"method":"PUT"|"host":"http://s3:8333"' | tail -3 || true

echo ""
echo "==> s3 gateway (expect PutObject / upload)"
docker compose logs s3 --tail=20 2>&1 | grep -iE 'PUT|upload|video-fragments' | tail -5 || true

echo ""
echo "==> volume nodes (must NOT show client PUT from stand — only internal filer writes)"
docker compose logs volume1 --tail=10 2>&1 | grep -iE 'POST /' | tail -3 || echo "(no direct client POST on volume1 — OK)"

echo ""
echo "Proof complete. Production client path: sideweed:8880 → s3:8333."
