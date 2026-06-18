#!/usr/bin/env bash
# Redirect to debug location (not production).
exec "$(dirname "$0")/debug/put_fragment_direct.sh" "$@"
