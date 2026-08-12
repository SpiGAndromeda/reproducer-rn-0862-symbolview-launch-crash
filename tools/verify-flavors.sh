#!/bin/bash
# Prove that a built .app embeds the RELEASE flavor of the React core and of
# hermes. CocoaPods caches a per-configuration copy of both frameworks, so a
# Release build made after a Debug build can silently embed the Debug binaries,
# which do not reproduce the crash. Only the arm64 UUID settles it.
set -u

REACT_RELEASE_0862=791C3298-6723-3FE6-B25E-4C6BD2F09175
REACT_DEBUG_0862=8DE74F15-18AF-319B-B445-3282C057039D
REACT_RELEASE_0860=61086F4A-30F5-3EA0-A72A-2C94C71C7AAC
REACT_DEBUG_0860=DFC40CD0-0682-30E6-9DE3-CE1F0A290A37
HERMES_RELEASE_016=75872184-F738-3E5C-B47A-FD4BCE09605A
HERMES_DEBUG_016=DA9F89D7-EF84-35EC-ACDD-ED23DECAAF17
HERMES_RELEASE_014=45EC9B08-1175-38E9-A03B-F3544286F1F1
HERMES_DEBUG_014=5D1E17D1-FD4F-3A96-9870-BF847F5B60B9

[ $# -eq 1 ] || { echo "usage: $0 <path-to-app-bundle>" >&2; exit 2; }
APP="$1"
[ -d "$APP" ] || { echo "not a .app bundle: $APP" >&2; exit 2; }

arm64_uuid() {
  local binary="$1"
  [ -f "$binary" ] || { echo "missing framework binary: $binary" >&2; exit 1; }
  local out uuid
  out=$(dwarfdump --uuid "$binary") || { echo "dwarfdump failed on $binary" >&2; exit 1; }
  uuid=$(echo "$out" | awk '/\(arm64\)/ { print $2 }')
  [ -n "$uuid" ] || { echo "no arm64 UUID for $binary:" >&2; echo "$out" >&2; exit 1; }
  echo "$uuid"
}

REACT_UUID=$(arm64_uuid "$APP/Frameworks/React.framework/React") || exit 1
HERMES_UUID=$(arm64_uuid "$APP/Frameworks/hermesvm.framework/hermesvm") || exit 1

echo "app:            $APP"
echo "React arm64:    $REACT_UUID"
echo "hermesvm arm64: $HERMES_UUID"

fail=0

case "$REACT_UUID" in
  "$REACT_RELEASE_0862") echo "React:    release 0.86.2  (crashing state)" ;;
  "$REACT_RELEASE_0860") echo "React:    release 0.86.0  (working baseline)" ;;
  "$REACT_DEBUG_0862"|"$REACT_DEBUG_0860")
    echo "React:    DEBUG flavor - build is invalid, delete ios/Pods/.last_build_configuration and rebuild" >&2
    fail=1 ;;
  *)
    echo "React:    UNKNOWN UUID - matches no artifact this reproduction was verified against" >&2
    fail=1 ;;
esac

case "$HERMES_UUID" in
  "$HERMES_RELEASE_016") echo "hermesvm: release 250829098.0.16 (pairs with react-native 0.86.2)" ;;
  "$HERMES_RELEASE_014") echo "hermesvm: release 250829098.0.14 (pairs with react-native 0.86.0)" ;;
  "$HERMES_DEBUG_016"|"$HERMES_DEBUG_014")
    echo "hermesvm: DEBUG flavor - build is invalid, delete ios/Pods/.last_build_configuration and rebuild" >&2
    fail=1 ;;
  *)
    echo "hermesvm: UNKNOWN UUID - matches no artifact this reproduction was verified against" >&2
    fail=1 ;;
esac

exit "$fail"
