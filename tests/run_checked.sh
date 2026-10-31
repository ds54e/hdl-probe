#!/usr/bin/env bash
# A successful process exit is necessary, but not sufficient, for a test pass.
set -euo pipefail
if [[ $# -lt 5 || $4 != -- ]]; then
  echo 'usage: run_checked.sh seconds log exact-pass-marker -- command [args...]' >&2
  exit 2
fi
seconds=$1
log=$2
marker=$3
shift 4
if timeout --kill-after=5s "${seconds}s" "$@" 2>&1 | tee "$log"; then
  :
else
  status=$?
  echo "FAIL: command/log pipeline exited $status (see $log)" >&2
  exit "$status"
fi
if ! grep -Fxq -- "$marker" "$log"; then
  echo "FAIL: missing exact PASS marker: $marker (see $log)" >&2
  exit 1
fi
