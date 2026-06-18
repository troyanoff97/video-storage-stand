#!/usr/bin/env bash
# Verify ./seaweedfs exists and HEAD matches the stand pin.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SEAWEEDFS_DIR="${SEAWEEDFS_DIR:-./seaweedfs}"
REQUIRED_SHORT_COMMIT="${SEAWEEDFS_REQUIRED_COMMIT:-1528e7d}"
REQUIRED_FULL_COMMIT="${SEAWEEDFS_REQUIRED_COMMIT_FULL:-1528e7d6d610330ec0bc8256090005ffbe09d64c}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

if [ ! -d "$SEAWEEDFS_DIR" ]; then
  fail "./seaweedfs is missing. Clone the customer fork, e.g.:
  SEAWEEDFS_REPO_URL=git@github.com:<org>/seaweedfs.git make init-seaweedfs
See docs/SEAWEEDFS_PIN.md"
fi

if [ ! -d "$SEAWEEDFS_DIR/weed" ]; then
  fail "$SEAWEEDFS_DIR/weed not found — not a SeaweedFS source tree.
Run: SEAWEEDFS_REPO_URL=git@github.com:<org>/seaweedfs.git make init-seaweedfs"
fi

if ! git -C "$SEAWEEDFS_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  fail "$SEAWEEDFS_DIR is not a git repository.
Run: SEAWEEDFS_REPO_URL=git@github.com:<org>/seaweedfs.git make init-seaweedfs"
fi

short_head="$(git -C "$SEAWEEDFS_DIR" rev-parse --short=7 HEAD)"
full_head="$(git -C "$SEAWEEDFS_DIR" rev-parse HEAD)"

if [ "$short_head" != "$REQUIRED_SHORT_COMMIT" ] && [ "$full_head" != "$REQUIRED_FULL_COMMIT" ]; then
  fail "seaweedfs HEAD is ${short_head} (${full_head}); required ${REQUIRED_SHORT_COMMIT}.
Checkout the pinned commit:
  cd seaweedfs && git fetch origin && git checkout ${REQUIRED_FULL_COMMIT}
Or re-init:
  SEAWEEDFS_REPO_URL=git@github.com:<org>/seaweedfs.git make init-seaweedfs
See docs/SEAWEEDFS_PIN.md"
fi

echo "OK: seaweedfs at ${short_head} (required ${REQUIRED_SHORT_COMMIT})"
