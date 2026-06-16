#!/usr/bin/env bash
# Map SeaweedFS assign volume host (docker network) to localhost URL for direct PUT.
resolve_volume_url() {
  local assign_url="$1"
  local host port

  host="${assign_url%%:*}"
  port="${assign_url##*:}"

  case "${host}:${port}" in
    volume1:8080) echo "http://localhost:8080" ;;
    volume2:8080) echo "http://localhost:8081" ;;
    localhost:8080) echo "http://localhost:8080" ;;
    localhost:8081) echo "http://localhost:8081" ;;
    *)
      echo "ERROR: unknown volume URL '${assign_url}'" >&2
      return 1
      ;;
  esac
}
