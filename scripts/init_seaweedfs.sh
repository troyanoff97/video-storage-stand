#!/usr/bin/env bash
# Clone customer SeaweedFS fork (if missing) and checkout the stand pin.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SEAWEEDFS_DIR="${SEAWEEDFS_DIR:-./seaweedfs}"
REQUIRED_BRANCH="${SEAWEEDFS_REQUIRED_BRANCH:-feat/volume-disk-health-isolation}"
REQUIRED_SHORT_COMMIT="${SEAWEEDFS_REQUIRED_COMMIT:-1528e7d}"
REQUIRED_FULL_COMMIT="${SEAWEEDFS_REQUIRED_COMMIT_FULL:-1528e7d6d610330ec0bc8256090005ffbe09d64c}"
DEFAULT_REPO_PLACEHOLDER="git@github.com:<org>/seaweedfs.git"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

checkout_pin() {
  local dir="$1"
  echo "==> Checking out SeaweedFS pin ${REQUIRED_SHORT_COMMIT} in ${dir}"
  if git -C "$dir" cat-file -e "${REQUIRED_FULL_COMMIT}^{commit}" 2>/dev/null; then
    git -C "$dir" checkout --detach "$REQUIRED_FULL_COMMIT"
  elif git -C "$dir" cat-file -e "${REQUIRED_SHORT_COMMIT}^{commit}" 2>/dev/null; then
    git -C "$dir" checkout --detach "$REQUIRED_SHORT_COMMIT"
  elif git -C "$dir" show-ref --verify --quiet "refs/remotes/origin/${REQUIRED_BRANCH}"; then
    git -C "$dir" checkout -B "$REQUIRED_BRANCH" "origin/${REQUIRED_BRANCH}"
  elif git -C "$dir" show-ref --verify --quiet "refs/heads/${REQUIRED_BRANCH}"; then
    git -C "$dir" checkout "$REQUIRED_BRANCH"
  else
    fail "commit ${REQUIRED_FULL_COMMIT} not found in ${dir}.
Fetch from customer fork: cd seaweedfs && git fetch origin ${REQUIRED_BRANCH}"
  fi

  short_head="$(git -C "$dir" rev-parse --short HEAD)"
  if [ "$short_head" != "$REQUIRED_SHORT_COMMIT" ]; then
    fail "after checkout HEAD is ${short_head}, required ${REQUIRED_SHORT_COMMIT}.
See docs/SEAWEEDFS_PIN.md"
  fi
  echo "OK: seaweedfs at ${short_head}"
}

if [ -d "$SEAWEEDFS_DIR/.git" ] || [ -f "$SEAWEEDFS_DIR/.git" ]; then
  echo "==> ${SEAWEEDFS_DIR} already exists — syncing to pin"
  if git -C "$SEAWEEDFS_DIR" remote get-url origin >/dev/null 2>&1; then
    git -C "$SEAWEEDFS_DIR" fetch origin --tags 2>/dev/null || true
  fi
  checkout_pin "$SEAWEEDFS_DIR"
  exit 0
fi

if [ -z "${SEAWEEDFS_REPO_URL:-}" ]; then
  fail "SEAWEEDFS_REPO_URL is not set and ${SEAWEEDFS_DIR} does not exist.
Example:
  SEAWEEDFS_REPO_URL=${DEFAULT_REPO_PLACEHOLDER} make init-seaweedfs
See docs/SEAWEEDFS_PIN.md"
fi

if [ -d "$SEAWEEDFS_DIR" ]; then
  fail "${SEAWEEDFS_DIR} exists but is not a git repo. Remove it or fix manually."
fi

echo "==> Cloning SeaweedFS from ${SEAWEEDFS_REPO_URL}"
git clone "$SEAWEEDFS_REPO_URL" "$SEAWEEDFS_DIR"
checkout_pin "$SEAWEEDFS_DIR"
