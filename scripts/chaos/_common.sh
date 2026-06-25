#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

if [[ -z "${COMPOSE_PROJECT_NAME:-}" ]]; then
  _v1=$(docker ps --format '{{.Names}}' --filter "publish=8080" 2>/dev/null | grep -E 'volume1-' | head -1 || true)
  if [[ "$_v1" =~ ^(.+)-volume1-[0-9]+$ ]]; then
    export COMPOSE_PROJECT_NAME="${BASH_REMATCH[1]}"
  fi
fi
COMPOSE=(docker compose)
[[ -n "${COMPOSE_PROJECT_NAME:-}" ]] && COMPOSE+=(-p "$COMPOSE_PROJECT_NAME")
COMPOSE+=(-f docker-compose.yml -f docker-compose.chaos.yml)

compose() {
  "${COMPOSE[@]}" "$@"
}
