#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${MAC_STREAM_APP_NAME:-MacStream}"
BUNDLE_ID="${MAC_STREAM_BUNDLE_ID:-com.ideaplexa.macstream}"
MIN_SYSTEM_VERSION="${MAC_STREAM_MIN_SYSTEM_VERSION:-26.0}"
CONFIGURATION="${MAC_STREAM_BUILD_CONFIGURATION:-release}"
BUILD_ARCH="${MAC_STREAM_BUILD_ARCH:-$(uname -m)}"
VERSION="${MAC_STREAM_VERSION:-0.1.0}"
BUILD_NUMBER="${MAC_STREAM_BUILD_NUMBER:-0}"
SIGN_IDENTITY="${MAC_STREAM_CODESIGN_IDENTITY:-}"
TIMESTAMP_MODE="${MAC_STREAM_CODESIGN_TIMESTAMP:-auto}"
REQUIRE_DEVELOPER_ID="${MAC_STREAM_REQUIRE_DEVELOPER_ID:-0}"
REQUIRE_HARDENED_RUNTIME="${MAC_STREAM_REQUIRE_HARDENED_RUNTIME:-0}"
HARDENED_RUNTIME="${MAC_STREAM_HARDENED_RUNTIME:-1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${MAC_STREAM_DIST_DIR:-$ROOT_DIR/dist}"
ENTITLEMENTS="${MAC_STREAM_ENTITLEMENTS:-$ROOT_DIR/Resources/Entitlements/MacStream.Release.entitlements}"
INFO_TEMPLATE="${MAC_STREAM_INFO_PLIST_TEMPLATE:-$ROOT_DIR/Resources/Info.plist}"
APP_ICON="${MAC_STREAM_APP_ICON:-$ROOT_DIR/Resources/AppIcon/MacStream.icns}"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/clang-module-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

VERSION="${VERSION#v}"

if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
  echo "MAC_STREAM_VERSION must be a bundle version like 0.1.0 or v0.1.0; got '$VERSION'" >&2
  exit 2
fi

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "MAC_STREAM_BUILD_NUMBER must be numeric, optionally dotted; got '$BUILD_NUMBER'" >&2
  exit 2
fi

if [[ "$REQUIRE_DEVELOPER_ID" == "1" && ( -z "$SIGN_IDENTITY" || "$SIGN_IDENTITY" == "-" ) ]]; then
  echo "MAC_STREAM_CODESIGN_IDENTITY is required for Developer ID release signing" >&2
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
  /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile MacStream" "$INFO_PLIST"
}

copy_runtime_frameworks() {
  local build_products_dir="$1"
  local framework_found=0
  local framework

  shopt -s nullglob
  for framework in "$build_products_dir"/*.framework; do
    framework_found=1
    /usr/bin/ditto "$framework" "$APP_FRAMEWORKS/$(basename "$framework")"
  done
  shopt -u nullglob

  if [[ "$framework_found" == "1" ]] && ! /usr/bin/otool -l "$APP_BINARY" | grep -Fq "@executable_path/../Frameworks"; then
    /usr/bin/install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY"
  fi
}

build_app() {
  local swift_build_args=(-c "$CONFIGURATION")
  if [[ -n "$BUILD_ARCH" ]]; then
    swift_build_args+=(--arch "$BUILD_ARCH")
  fi

  swift build "${swift_build_args[@]}"
  local build_products_dir
  build_products_dir="$(swift build --show-bin-path "${swift_build_args[@]}")"
  local build_binary="$build_products_dir/$APP_NAME"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"
  cp "$build_binary" "$APP_BINARY"
  cp "$APP_ICON" "$APP_RESOURCES/MacStream.icns"
  chmod +x "$APP_BINARY"
  copy_runtime_frameworks "$build_products_dir"
  xattr -cr "$APP_BUNDLE" >/dev/null 2>&1 || true
  write_info_plist
  /usr/bin/plutil -lint "$INFO_PLIST" >/dev/null
}

embedded_code_paths() {
  if [[ ! -d "$APP_FRAMEWORKS" ]]; then
    return
  fi

  find "$APP_FRAMEWORKS" -depth \( \
    -name "*.xpc" -o \
    -name "*.appex" -o \
    -name "*.app" -o \
    -name "*.framework" -o \
    -name "*.dylib" \
  \) -print
}

sign_embedded_code_path() {
  local code_path="$1"
  local sign_args=(--force)

  if [[ "$HARDENED_RUNTIME" == "1" ]]; then
    sign_args+=(--options runtime)
  fi

  if [[ -n "$SIGN_IDENTITY" && "$SIGN_IDENTITY" != "-" ]]; then
    if [[ "$TIMESTAMP_MODE" == "none" ]]; then
      /usr/bin/codesign "${sign_args[@]}" --timestamp=none --sign "$SIGN_IDENTITY" "$code_path"
    else
      /usr/bin/codesign "${sign_args[@]}" --timestamp --sign "$SIGN_IDENTITY" "$code_path"
    fi
  else
    /usr/bin/codesign "${sign_args[@]}" --timestamp=none --sign - "$code_path"
  fi
}

sign_embedded_code() {
  local code_path

  while IFS= read -r code_path; do
    [[ -e "$code_path" && ! -L "$code_path" ]] || continue
    sign_embedded_code_path "$code_path"
  done < <(embedded_code_paths)
}

sign_app() {
  sign_embedded_code

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

verify_developer_id_signature() {
  local code_path="$1"
  local signing_details
  signing_details="$(/usr/bin/codesign -dv "$code_path" 2>&1)"
  if [[ "$signing_details" != *"Authority=Developer ID Application:"* ]]; then
    echo "expected Developer ID Application signature for $code_path" >&2
    exit 1
  fi
}

verify_embedded_code() {
  local code_path

  while IFS= read -r code_path; do
    [[ -e "$code_path" && ! -L "$code_path" ]] || continue
    /usr/bin/codesign --verify --strict --verbose=2 "$code_path"
    if [[ "$REQUIRE_DEVELOPER_ID" == "1" ]]; then
      verify_developer_id_signature "$code_path"
    fi
  done < <(embedded_code_paths)
}

verify_app() {
  verify_embedded_code
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
  fi

  if [[ "$REQUIRE_DEVELOPER_ID" == "1" ]]; then
    verify_developer_id_signature "$APP_BUNDLE"
  fi

  /usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$INFO_PLIST" >/dev/null
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" >/dev/null
  /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST" >/dev/null
  /usr/libexec/PlistBuddy -c "Print :NSCameraUsageDescription" "$INFO_PLIST" >/dev/null
  /usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" "$INFO_PLIST" >/dev/null
  /usr/libexec/PlistBuddy -c "Print :NSAudioCaptureUsageDescription" "$INFO_PLIST" >/dev/null
  test -f "$APP_RESOURCES/MacStream.icns"
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
