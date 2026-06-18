#!/usr/bin/env bash
# DEBUG ONLY: map SeaweedFS assign volume host to localhost URL for direct volume POST.
resolve_volume_url() {
  local assign_url="$1"
  case "$assign_url" in
    volume1:8080) echo "http://localhost:8080" ;;
    volume2:8080) echo "http://localhost:8081" ;;
    *)
      echo "ERROR: unknown volume URL '${assign_url}'" >&2
      return 1
      ;;
  esac
}
