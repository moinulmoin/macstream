#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${MAC_STREAM_APP_NAME:-MacStream}"
APP_PATH="${MAC_STREAM_APP_PATH:-}"
VERSION="${MAC_STREAM_VERSION:-}"
BUILD_ARCH="${MAC_STREAM_BUILD_ARCH:-$(uname -m)}"
VOLUME_NAME="${MAC_STREAM_DMG_VOLUME_NAME:-$APP_NAME}"
SIGN_IDENTITY="${MAC_STREAM_CODESIGN_IDENTITY:-}"
TIMESTAMP_MODE="${MAC_STREAM_CODESIGN_TIMESTAMP:-auto}"
REQUIRE_DEVELOPER_ID="${MAC_STREAM_REQUIRE_DEVELOPER_ID:-0}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${MAC_STREAM_DIST_DIR:-$ROOT_DIR/dist}"

if [[ -z "$APP_PATH" ]]; then
  APP_PATH="$DIST_DIR/$APP_NAME.app"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 2
fi

if [[ -z "$VERSION" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")"
fi
VERSION="${VERSION#v}"

if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
  echo "MAC_STREAM_VERSION must be a bundle version like 0.4.0 or v0.4.0; got '$VERSION'" >&2
  exit 2
fi

if [[ "$REQUIRE_DEVELOPER_ID" == "1" && ( -z "$SIGN_IDENTITY" || "$SIGN_IDENTITY" == "-" ) ]]; then
  echo "MAC_STREAM_CODESIGN_IDENTITY is required for Developer ID DMG signing" >&2
  exit 2
fi

DMG_NAME="${MAC_STREAM_DMG_NAME:-$APP_NAME-v$VERSION-macos-$BUILD_ARCH.dmg}"
DMG_PATH="${MAC_STREAM_DMG_PATH:-$DIST_DIR/$DMG_NAME}"
WORK_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/macstream-dmg.XXXXXX")"
STAGE_DIR="$WORK_DIR/root"
MOUNT_DIR="$WORK_DIR/mount"
IS_MOUNTED=0

cleanup() {
  if [[ "$IS_MOUNTED" == "1" ]]; then
    /usr/bin/hdiutil detach "$MOUNT_DIR" -quiet || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

verify_developer_id_signature() {
  local code_path="$1"
  local certificate_dir
  certificate_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/macstream-dmg-signature.XXXXXX")"
  local certificate_prefix="$certificate_dir/certificate"

  if ! /usr/bin/codesign -d --extract-certificates="$certificate_prefix" "$code_path" >/dev/null 2>&1; then
    rm -rf "$certificate_dir"
    echo "Could not extract signing certificate for $code_path" >&2
    exit 1
  fi

  local certificate_subject
  certificate_subject="$(/usr/bin/openssl x509 -inform DER -in "${certificate_prefix}0" -noout -subject 2>/dev/null || true)"
  rm -rf "$certificate_dir"

  if [[ "$certificate_subject" != *"CN=Developer ID Application:"* ]]; then
    echo "Expected Developer ID Application signature for $code_path" >&2
    exit 1
  fi
}

mkdir -p "$DIST_DIR" "$STAGE_DIR" "$MOUNT_DIR"
rm -f "$DMG_PATH"

/usr/bin/ditto "$APP_PATH" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"

/usr/bin/hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGE_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH"

/usr/bin/hdiutil attach \
  -readonly \
  -nobrowse \
  -mountpoint "$MOUNT_DIR" \
  "$DMG_PATH" >/dev/null
IS_MOUNTED=1

test -d "$MOUNT_DIR/$APP_NAME.app"
test -L "$MOUNT_DIR/Applications"
if [[ "$(readlink "$MOUNT_DIR/Applications")" != "/Applications" ]]; then
  echo "DMG Applications link does not target /Applications" >&2
  exit 1
fi

/usr/bin/hdiutil detach "$MOUNT_DIR" -quiet
IS_MOUNTED=0

if [[ -n "$SIGN_IDENTITY" && "$SIGN_IDENTITY" != "-" ]]; then
  sign_args=(--force --sign "$SIGN_IDENTITY")
  if [[ "$TIMESTAMP_MODE" == "none" ]]; then
    sign_args+=(--timestamp=none)
  else
    sign_args+=(--timestamp)
  fi
  /usr/bin/codesign "${sign_args[@]}" "$DMG_PATH"
  /usr/bin/codesign --verify --strict --verbose=2 "$DMG_PATH"
  if [[ "$REQUIRE_DEVELOPER_ID" == "1" ]]; then
    verify_developer_id_signature "$DMG_PATH"
  fi
fi

/usr/bin/hdiutil verify "$DMG_PATH"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "dmg_name=$DMG_NAME"
    echo "dmg_path=$DMG_PATH"
  } >>"$GITHUB_OUTPUT"
fi

echo "Packaged $DMG_PATH"
