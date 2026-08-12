#!/bin/bash
# Print the termination signal the simulator recorded for each launch of the
# app, so a census can be told apart from an unrelated failure.
#
# SIGTRAP (5) and SIGSEGV (11) are this bug: the heap is already corrupt by the
# time the allocator or the component-view factory notices. SIGABRT (6) is a
# dynamic-linker failure from a mismatched expo module set and invalidates the
# run - fix the pins and census again rather than counting it.
#
# The query runs inside the simulator. The host's own log store holds no
# records for simulated processes, so `log show` on the host finds nothing.
set -euo pipefail

[ $# -ge 2 ] || { echo "usage: $0 <simulator-udid> <bundle-id> [minutes]" >&2; exit 2; }
SIM="$1"
BUNDLE_ID="$2"
WINDOW="${3:-10}m"

xcrun simctl spawn "$SIM" log show \
  --last "$WINDOW" \
  --predicate "process == \"runningboardd\" AND eventMessage CONTAINS \"$BUNDLE_ID\"" \
  --style compact |
  grep 'exited with' || {
    echo "no termination records in the last $WINDOW" >&2
    exit 1
  }
