#!/bin/bash
# Cold-launch the built app N times and count how many launches die.
#
# The crash is probabilistic, so a single launch proves nothing in either
# direction: the working baseline must survive every launch and the crashing
# state must die on most of them. Each iteration terminates the app first so
# every launch is cold, then waits for the mounting transaction to finish
# before asking whether the process is still alive.
set -euo pipefail

[ $# -ge 2 ] || { echo "usage: $0 <simulator-udid> <path-to-app-bundle> [launches]" >&2; exit 2; }
SIM="$1"
APP="$2"
LAUNCHES="${3:-10}"
SETTLE_SECONDS=6

[ -d "$APP" ] || { echo "not a .app bundle: $APP" >&2; exit 2; }

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")

xcrun simctl bootstatus "$SIM" -b >/dev/null
xcrun simctl terminate "$SIM" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl uninstall "$SIM" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$SIM" "$APP"

echo "simulator: $SIM"
echo "bundle:    $BUNDLE_ID"
echo "launches:  $LAUNCHES"

dead=0
for i in $(seq 1 "$LAUNCHES"); do
  xcrun simctl terminate "$SIM" "$BUNDLE_ID" >/dev/null 2>&1 || true
  out=$(xcrun simctl launch "$SIM" "$BUNDLE_ID" 2>&1)
  pid=${out##*: }
  if ! [[ "$pid" =~ ^[0-9]+$ ]]; then
    echo "launch $i: could not start: $out" >&2
    exit 1
  fi
  sleep "$SETTLE_SECONDS"
  if ps -p "$pid" >/dev/null 2>&1; then
    echo "launch $i: alive"
  else
    echo "launch $i: crashed"
    dead=$((dead + 1))
  fi
done

echo "crashed: $dead/$LAUNCHES"
