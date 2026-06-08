# Release Process

This document is the release checklist for MacStream. Keep releases boring: one version, one tag, verified artifacts, clear QA.

## Versioning

Use semver tags:

```text
vMAJOR.MINOR.PATCH
```

Examples:

- `v0.1.0` for the first MVP release.
- `v0.1.1` for a small fix.
- `v0.2.0` for a meaningful MVP feature step.

## GitHub Actions Release

Pull requests and pushes to `main` run `.github/workflows/ci.yml` on macOS 26 arm64 runners. CI runs tests, the default build, optional compile checks, and an ad-hoc hardened bundle smoke package.

Tagged releases are built by `.github/workflows/release.yml` on macOS 26 arm64 runners. The workflow:

1. Runs the Swift test suite.
2. Builds the default app plus optional HaishinKit and experimental MLX compile configurations.
3. Imports the Developer ID certificate into a temporary keychain.
4. Packages `MacStream.app` with versioned `Info.plist` values from the tag.
5. Signs with hardened runtime and release entitlements.
6. Submits the app zip to Apple notarization with `xcrun notarytool`.
7. Staples and validates the notarization ticket.
8. Creates `MacStream-vX.Y.Z-macos-arm64.zip` plus a `.sha256` file.
9. Uploads workflow artifacts and publishes or updates the GitHub Release.

Required GitHub Actions secrets:

```text
MAC_STREAM_MACOS_CERTIFICATE_P12_BASE64
MAC_STREAM_MACOS_CERTIFICATE_PASSWORD
MAC_STREAM_CODESIGN_IDENTITY
MAC_STREAM_APPLE_ID
MAC_STREAM_APPLE_TEAM_ID
MAC_STREAM_APP_SPECIFIC_PASSWORD
```

`MAC_STREAM_CODESIGN_IDENTITY` should be the full Developer ID Application identity, for example:

```text
Developer ID Application: Ideaplexa LLC (53P98M92V7)
```

`MAC_STREAM_MACOS_CERTIFICATE_P12_BASE64` is the base64-encoded `.p12` Developer ID Application certificate. `MAC_STREAM_APP_SPECIFIC_PASSWORD` is an Apple app-specific password for the Apple ID that can submit notarization requests for `MAC_STREAM_APPLE_TEAM_ID`.

MacStream does not ship Sparkle or another in-app updater yet. For now, release delivery is GitHub Releases plus a SHA256 checksum.

## Pre-Release Checks

Run these before tagging:

```bash
swift test
swift build
MAC_STREAM_ENABLE_HAISHINKIT=1 swift build
MAC_STREAM_ENABLE_MLX=1 swift build
./script/build_and_run.sh --verify
codesign --verify --strict dist/MacStream.app
```

Confirm:

- the working tree is clean,
- `MacStream.app` launches,
- the bundle identifier is `com.ideaplexa.macstream`,
- the app icon appears in Finder,
- the expected signing identity is present,
- packaged Camera, Microphone, and Screen Recording permission recovery works,
- local `Screen` and composited `Screen + Face` recordings play back correctly,
- default RTMP mode is honestly labeled as endpoint validation,
- optional HaishinKit real publish has a current smoke result,
- experimental MLX still compiles but is not treated as a release-critical AI path.

## Commit Shape

Prefer small release batches:

1. Product/app implementation.
2. Test coverage.
3. Documentation/release notes.

Do not mix generated build output into commits. `dist/`, `.build/`, and `.swiftpm/` should stay untracked.

## Tagging

Create an annotated tag:

```bash
git tag -a vX.Y.Z -m "MacStream vX.Y.Z"
```

Do not rewrite a published tag unless the release is known-bad and the owner explicitly approves the force update.

Pushing a `vMAJOR.MINOR.PATCH` tag starts the release workflow:

```bash
git push origin main
git push origin vX.Y.Z
```

Manual dry runs are available from the `Release` workflow in GitHub Actions. Manual publishing requires `publish_release=true` and an existing matching tag.

## Artifact

The release workflow creates the signed, notarized, stapled zip:

Artifact naming:

```text
MacStream-vX.Y.Z-macos-arm64.zip
```

Record the SHA256 digest from the uploaded `.sha256` file or with:

```bash
shasum -a 256 dist/MacStream-vX.Y.Z-macos-arm64.zip
```

## Local Packaging Smoke

The CI packaging helper can be smoke-tested locally with ad-hoc signing. This does not notarize and does not replace the GitHub Actions release path:

```bash
MAC_STREAM_VERSION=0.1.0 \
MAC_STREAM_BUILD_NUMBER=1 \
MAC_STREAM_BUILD_CONFIGURATION=release \
MAC_STREAM_BUILD_ARCH="$(uname -m)" \
./script/package_macos_app.sh

/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" dist/MacStream.app/Contents/Info.plist
codesign --verify --strict --verbose=2 dist/MacStream.app
```

To locally simulate release signing, provide `MAC_STREAM_CODESIGN_IDENTITY` and require hardened runtime:

```bash
MAC_STREAM_CODESIGN_IDENTITY="Developer ID Application: Ideaplexa LLC (53P98M92V7)" \
MAC_STREAM_REQUIRE_DEVELOPER_ID=1 \
MAC_STREAM_REQUIRE_HARDENED_RUNTIME=1 \
MAC_STREAM_VERSION=0.1.0 \
MAC_STREAM_BUILD_NUMBER=1 \
./script/package_macos_app.sh
```

## QA Checklist

1. Download the release zip from GitHub.
2. Unzip and launch `MacStream.app`.
3. Confirm bundle identifier `com.ideaplexa.macstream`.
4. Test Camera, Microphone, and Screen Recording permission flows.
5. Grant Screen Recording, quit/reopen, and confirm access is detected.
6. Test `Face`, `Screen`, `Screen + Face`, and `BRB` preview scenes.
7. Start and stop Preview mode.
8. In the default build, verify RTMP wording says endpoint check, not Go Live.
9. Start and stop local Screen recording, then verify the `.mov`.
10. Start and stop local Screen + Face recording, then verify the camera PiP is baked into the `.mov`.
11. In a HaishinKit build, start full RTMP publishing from Screen + Face and verify the remote output includes the camera PiP.
12. Verify adaptive mode lowers capture cost under capture pressure.
13. Verify setup/AI assistance is hidden or disabled during active capture and falls back visibly when no provider is configured.
14. Verify RTMP destination persistence and redaction in events/exports.
15. Export clip markers and session report twice in quick succession; confirm filenames do not collide.

## Rollback

If a release is broken:

1. Mark the GitHub release as pre-release or delete the release asset.
2. Open an issue with the failure and reproduction steps.
3. Fix on `main`.
4. Ship a patch tag, for example `v0.1.1`.

Avoid force-updating public tags unless explicitly approved.
