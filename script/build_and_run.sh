#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="OpenCue"
BUNDLE_ID="com.ideaplexa.opencue"
DEFAULT_SIGN_IDENTITY="Developer ID Application: Ideaplexa LLC (53P98M92V7)"
REQUESTED_SIGN_IDENTITY="${OPEN_CUE_CODESIGN_IDENTITY:-$DEFAULT_SIGN_IDENTITY}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

resolve_sign_identity() {
  if [[ "$REQUESTED_SIGN_IDENTITY" == "-" ]]; then
    echo "-"
    return
  fi

  if /usr/bin/security find-identity -p codesigning -v | grep -Fq "\"$REQUESTED_SIGN_IDENTITY\""; then
    echo "$REQUESTED_SIGN_IDENTITY"
  else
    echo "-"
  fi
}

SIGN_IDENTITY="$(resolve_sign_identity)"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

package_app() {
  OPEN_CUE_BUILD_CONFIGURATION="${OPEN_CUE_BUILD_CONFIGURATION:-debug}" \
  OPEN_CUE_BUILD_ARCH="${OPEN_CUE_BUILD_ARCH:-$(uname -m)}" \
  OPEN_CUE_VERSION="${OPEN_CUE_VERSION:-0.1.0}" \
  OPEN_CUE_BUILD_NUMBER="${OPEN_CUE_BUILD_NUMBER:-0}" \
  OPEN_CUE_CODESIGN_IDENTITY="$SIGN_IDENTITY" \
  OPEN_CUE_CODESIGN_TIMESTAMP="${OPEN_CUE_CODESIGN_TIMESTAMP:-none}" \
  OPEN_CUE_HARDENED_RUNTIME="${OPEN_CUE_HARDENED_RUNTIME:-0}" \
  "$ROOT_DIR/script/package_macos_app.sh"
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_info_plist() {
  /usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$INFO_PLIST" >/dev/null
  test -f "$APP_BUNDLE/Contents/Resources/OpenCue.icns"
  /usr/libexec/PlistBuddy -c "Print :NSCameraUsageDescription" "$INFO_PLIST" >/dev/null
  /usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" "$INFO_PLIST" >/dev/null
  /usr/libexec/PlistBuddy -c "Print :NSAudioCaptureUsageDescription" "$INFO_PLIST" >/dev/null
}

verify_signature() {
  /usr/bin/codesign --verify --strict "$APP_BUNDLE"
  local actual_identifier
  actual_identifier="$(/usr/bin/codesign -dv "$APP_BUNDLE" 2>&1 | awk -F= '/^Identifier=/ { print $2 }')"
  if [[ "$actual_identifier" != "$BUNDLE_ID" ]]; then
    echo "expected code signature identifier $BUNDLE_ID, got $actual_identifier" >&2
    exit 1
  fi

  local designated_requirement
  designated_requirement="$(/usr/bin/codesign -dr - "$APP_BUNDLE" 2>&1)"
  if [[ "$designated_requirement" != *"identifier \"$BUNDLE_ID\""* ]]; then
    echo "expected designated requirement to include identifier $BUNDLE_ID" >&2
    exit 1
  fi
  if [[ "$designated_requirement" == *"# designated => cdhash "* ]]; then
    echo "expected stable designated requirement, got cdhash-only signing" >&2
    exit 1
  fi
}

package_app

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    verify_info_plist
    verify_signature
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    verify_signature
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
