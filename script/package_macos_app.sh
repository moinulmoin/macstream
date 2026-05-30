#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${OPEN_CUE_APP_NAME:-OpenCue}"
BUNDLE_ID="${OPEN_CUE_BUNDLE_ID:-com.ideaplexa.opencue}"
MIN_SYSTEM_VERSION="${OPEN_CUE_MIN_SYSTEM_VERSION:-26.0}"
CONFIGURATION="${OPEN_CUE_BUILD_CONFIGURATION:-release}"
BUILD_ARCH="${OPEN_CUE_BUILD_ARCH:-$(uname -m)}"
VERSION="${OPEN_CUE_VERSION:-0.1.0}"
BUILD_NUMBER="${OPEN_CUE_BUILD_NUMBER:-0}"
SIGN_IDENTITY="${OPEN_CUE_CODESIGN_IDENTITY:-}"
TIMESTAMP_MODE="${OPEN_CUE_CODESIGN_TIMESTAMP:-auto}"
REQUIRE_DEVELOPER_ID="${OPEN_CUE_REQUIRE_DEVELOPER_ID:-0}"
REQUIRE_HARDENED_RUNTIME="${OPEN_CUE_REQUIRE_HARDENED_RUNTIME:-0}"
HARDENED_RUNTIME="${OPEN_CUE_HARDENED_RUNTIME:-1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${OPEN_CUE_DIST_DIR:-$ROOT_DIR/dist}"
ENTITLEMENTS="${OPEN_CUE_ENTITLEMENTS:-$ROOT_DIR/Resources/Entitlements/OpenCue.Release.entitlements}"
INFO_TEMPLATE="${OPEN_CUE_INFO_PLIST_TEMPLATE:-$ROOT_DIR/Resources/Info.plist}"
APP_ICON="${OPEN_CUE_APP_ICON:-$ROOT_DIR/Resources/AppIcon/OpenCue.icns}"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/clang-module-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

VERSION="${VERSION#v}"

if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
  echo "OPEN_CUE_VERSION must be a bundle version like 0.1.0 or v0.1.0; got '$VERSION'" >&2
  exit 2
fi

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "OPEN_CUE_BUILD_NUMBER must be numeric, optionally dotted; got '$BUILD_NUMBER'" >&2
  exit 2
fi

if [[ "$REQUIRE_DEVELOPER_ID" == "1" && ( -z "$SIGN_IDENTITY" || "$SIGN_IDENTITY" == "-" ) ]]; then
  echo "OPEN_CUE_CODESIGN_IDENTITY is required for Developer ID release signing" >&2
  exit 2
fi

if [[ "$HARDENED_RUNTIME" == "1" && ! -f "$ENTITLEMENTS" ]]; then
  echo "Release entitlements file not found: $ENTITLEMENTS" >&2
  exit 2
fi

if [[ ! -f "$INFO_TEMPLATE" ]]; then
  echo "Info.plist template not found: $INFO_TEMPLATE" >&2
  exit 2
fi

if [[ ! -f "$APP_ICON" ]]; then
  echo "App icon not found: $APP_ICON" >&2
  exit 2
fi

write_info_plist() {
  cp "$INFO_TEMPLATE" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $MIN_SYSTEM_VERSION" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile OpenCue" "$INFO_PLIST"
}

build_app() {
  local swift_build_args=(-c "$CONFIGURATION")
  if [[ -n "$BUILD_ARCH" ]]; then
    swift_build_args+=(--arch "$BUILD_ARCH")
  fi

  swift build "${swift_build_args[@]}"
  local build_binary
  build_binary="$(swift build --show-bin-path "${swift_build_args[@]}")/$APP_NAME"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES"
  cp "$build_binary" "$APP_BINARY"
  cp "$APP_ICON" "$APP_RESOURCES/OpenCue.icns"
  chmod +x "$APP_BINARY"
  xattr -cr "$APP_BUNDLE" >/dev/null 2>&1 || true
  write_info_plist
  /usr/bin/plutil -lint "$INFO_PLIST" >/dev/null
}

sign_app() {
  local sign_args=(--force --identifier "$BUNDLE_ID")

  if [[ "$HARDENED_RUNTIME" == "1" ]]; then
    sign_args+=(--options runtime --entitlements "$ENTITLEMENTS")
  fi

  if [[ -n "$SIGN_IDENTITY" && "$SIGN_IDENTITY" != "-" ]]; then
    if [[ "$TIMESTAMP_MODE" == "none" ]]; then
      /usr/bin/codesign "${sign_args[@]}" --timestamp=none --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
    else
      /usr/bin/codesign "${sign_args[@]}" --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
    fi
  else
    /usr/bin/codesign "${sign_args[@]}" --timestamp=none --sign - \
      --requirements "=designated => identifier \"$BUNDLE_ID\"" \
      "$APP_BUNDLE"
  fi
}

verify_app() {
  /usr/bin/codesign --verify --strict --verbose=2 "$APP_BUNDLE"

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

  if [[ "$REQUIRE_HARDENED_RUNTIME" == "1" ]]; then
    local signing_details
    signing_details="$(/usr/bin/codesign -dv "$APP_BUNDLE" 2>&1)"
    if [[ "$signing_details" != *"Runtime Version="* && "$signing_details" != *"runtime"* ]]; then
      echo "expected hardened runtime signature for $APP_BUNDLE" >&2
      exit 1
    fi
    if [[ "$REQUIRE_DEVELOPER_ID" == "1" && "$signing_details" != *"Authority=Developer ID Application:"* ]]; then
      echo "expected Developer ID Application signature for $APP_BUNDLE" >&2
      exit 1
    fi
  fi

  /usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$INFO_PLIST" >/dev/null
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" >/dev/null
  /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST" >/dev/null
  /usr/libexec/PlistBuddy -c "Print :NSCameraUsageDescription" "$INFO_PLIST" >/dev/null
  /usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" "$INFO_PLIST" >/dev/null
  /usr/libexec/PlistBuddy -c "Print :NSAudioCaptureUsageDescription" "$INFO_PLIST" >/dev/null
  test -f "$APP_RESOURCES/OpenCue.icns"
}

emit_github_outputs() {
  if [[ -z "${GITHUB_OUTPUT:-}" ]]; then
    return
  fi

  {
    echo "app_path=$APP_BUNDLE"
    echo "info_plist=$INFO_PLIST"
    echo "version=$VERSION"
    echo "build_number=$BUILD_NUMBER"
    echo "arch=$BUILD_ARCH"
    echo "bundle_id=$BUNDLE_ID"
  } >>"$GITHUB_OUTPUT"
}

build_app
sign_app
verify_app
emit_github_outputs

echo "Packaged $APP_BUNDLE"
