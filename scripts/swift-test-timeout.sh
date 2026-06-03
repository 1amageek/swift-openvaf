#!/bin/sh
set -eu

if [ "$#" -lt 2 ]; then
  printf 'usage: %s <seconds> <command> [args...]\n' "$0" >&2
  exit 64
fi

timeout_seconds="$1"
shift

marker="${TMPDIR:-/tmp}/swift-test-timeout.$$"
rm -f "$marker"

"$@" &
child_pid=$!

(
  sleep "$timeout_seconds"
  if kill -0 "$child_pid" 2>/dev/null; then
    printf timeout > "$marker"
    kill -TERM "$child_pid" 2>/dev/null || exit 0
    sleep 2
    kill -KILL "$child_pid" 2>/dev/null || true
  fi
) &
watchdog_pid=$!

set +e
wait "$child_pid" 2>/dev/null
status=$?
set -e

kill -TERM "$watchdog_pid" 2>/dev/null || true
wait "$watchdog_pid" 2>/dev/null || true

if [ -f "$marker" ]; then
  rm -f "$marker"
  exit 124
fi

rm -f "$marker"
exit "$status"
