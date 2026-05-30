#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="OpenCue"
BUNDLE_ID="com.ideaplexa.opencue"
MIN_SYSTEM_VERSION="26.0"
DEFAULT_SIGN_IDENTITY="Developer ID Application: Ideaplexa LLC (53P98M92V7)"
REQUESTED_SIGN_IDENTITY="${OPEN_CUE_CODESIGN_IDENTITY:-$DEFAULT_SIGN_IDENTITY}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

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

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
xattr -cr "$APP_BUNDLE" >/dev/null 2>&1 || true

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSCameraUsageDescription</key>
  <string>OpenCue uses the camera for live stream preview and broadcast scenes.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>OpenCue uses the microphone to monitor speech and broadcast audio.</string>
  <key>NSAudioCaptureUsageDescription</key>
  <string>OpenCue captures Mac audio when system audio is enabled for local recordings and broadcasts.</string>
</dict>
</plist>
PLIST

sign_app() {
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    /usr/bin/codesign --force --sign - --identifier "$BUNDLE_ID" \
      --requirements "=designated => identifier \"$BUNDLE_ID\"" \
      "$APP_BUNDLE"
    return
  fi

  if ! /usr/bin/codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none "$APP_BUNDLE"; then
    echo "warning: signing with $SIGN_IDENTITY failed; falling back to stable ad-hoc signing" >&2
    /usr/bin/codesign --force --sign - --identifier "$BUNDLE_ID" \
      --requirements "=designated => identifier \"$BUNDLE_ID\"" \
      "$APP_BUNDLE"
  fi
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_info_plist() {
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

sign_app

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
