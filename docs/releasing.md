# Release Process

This document is the release checklist for MacStream. Keep releases boring: one version, one tag, verified artifacts, clear QA.

## Versioning

Use semver tags:

```text
vMAJOR.MINOR.PATCH
```

Examples:

- `v0.2.0` for a meaningful MVP feature step.
- `v0.2.1` for a small fix.

## GitHub Actions Release

Pull requests and pushes to `main` run `.github/workflows/ci.yml` on macOS 26 arm64 runners. CI builds the default, HaishinKit, MLX, and combined HaishinKit+MLX configurations, runs the default and combined test suites, and performs one ad-hoc hardened HaishinKit bundle smoke package.

Tagged releases are built by `.github/workflows/release.yml` on macOS 26 arm64 runners. The workflow:

1. Runs the Swift test suite.
2. Runs the real HaishinKit publisher against a local RTMP ingest and uses FFmpeg to verify the decoded H.264 stream.
3. Builds the default, HaishinKit, MLX, and combined compile configurations.
4. Imports the Developer ID certificate into a temporary keychain.
5. Packages `MacStream.app` with `MAC_STREAM_ENABLE_HAISHINKIT=1`, versioned `Info.plist` values from the tag, project and dependency license notices, and release-only guards for the Sparkle public key and HaishinKit variant.
6. Signs with hardened runtime and release entitlements.
7. Submits the app zip to Apple notarization with `xcrun notarytool`.
8. Staples and validates the notarization ticket.
9. Creates `MacStream-vX.Y.Z-macos-arm64.zip` for Sparkle, plus its `.sha256` file, then verifies the zip contains the HaishinKit RTMP release variant.
10. Creates and Developer-ID signs `MacStream-vX.Y.Z-macos-arm64.dmg` with `MacStream.app` and an `/Applications` link.
11. Notarizes, staples, and Gatekeeper-validates the DMG, then generates its post-staple `.sha256` file.
12. Uploads both distribution formats and publishes or updates the GitHub Release.

Required GitHub Actions secrets:

```text
MAC_STREAM_MACOS_CERTIFICATE_P12_BASE64
MAC_STREAM_MACOS_CERTIFICATE_PASSWORD
MAC_STREAM_CODESIGN_IDENTITY
MAC_STREAM_APPLE_ID
MAC_STREAM_APPLE_TEAM_ID
MAC_STREAM_APP_SPECIFIC_PASSWORD
SPARKLE_PRIVATE_KEY
```

`MAC_STREAM_CODESIGN_IDENTITY` should be the full Developer ID Application identity, for example:

```text
Developer ID Application: Ideaplexa LLC (53P98M92V7)
```

`MAC_STREAM_MACOS_CERTIFICATE_P12_BASE64` is the base64-encoded `.p12` Developer ID Application certificate. `MAC_STREAM_APP_SPECIFIC_PASSWORD` is an Apple app-specific password for the Apple ID that can submit notarization requests for `MAC_STREAM_APPLE_TEAM_ID`.

MacStream ships Sparkle auto-updates. The EdDSA-signed ZIP is the Sparkle update payload. The signed, notarized, and stapled DMG is the first-time installer. Both formats and their SHA256 checksums are published on GitHub Releases.

## Release Documentation

Every release has two checked-in documentation updates:

1. Move notable entries from `CHANGELOG.md` under `Unreleased` into a dated
   `vX.Y.Z` section and refresh the comparison links.
2. Add user-facing notes at `docs/releases/vX.Y.Z.md`.

The GitHub release workflow reads the versioned notes from the release tag and
appends artifact names, checksums, and verification commands. This keeps the
GitHub Release body reviewable in git and prevents one release's highlights
from being reused for a later version. Every tag is treated the same: the
workflow fails before building when either release document is missing.

## Sparkle Auto-Updates

### One-time setup

1. Download the Sparkle 2.9.3 tools release and run `./bin/generate_keys`. This stores the **private** key in the login Keychain and prints the **public** key.
2. Paste the printed public key into `Resources/Info.plist` under `SUPublicEDKey`, replacing the `REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY` placeholder. The public key is safe to commit.
3. Export the private key for CI: `./bin/generate_keys -x sparkle_private_key.txt`, then store the file contents as the GitHub Actions secret `SPARKLE_PRIVATE_KEY`. **Never** commit the private key.

`SUFeedURL` in `Resources/Info.plist` points to:

```text
https://raw.githubusercontent.com/moinulmoin/macstream/main/appcast.xml
```

### Per-release flow

When you push a `vX.Y.Z` tag, `.github/workflows/release.yml` still Developer-ID signs and notarizes `MacStream.app` as today. It also signs the release zip with Sparkle’s `sign_update` and appends a signed `<item>` to `appcast.xml`, then commits `appcast.xml` back to `main`.

Auto-update in the app only works after at least one Sparkle-signed release exists on that feed (for example, cut `v0.2.0` through the pipeline after the public key is committed). Installed builds must remain Developer-ID signed and notarized — the release workflow already handles that.

In-app UX: **Settings → About & Updates** includes **Check for Updates…**, and a daily automatic background check is enabled (`SUEnableAutomaticChecks`).

## Pre-Release Checks

Run these before tagging:

```bash
swift test
swift build
MAC_STREAM_ENABLE_HAISHINKIT=1 swift build
MAC_STREAM_ENABLE_MLX=1 swift build
MAC_STREAM_ENABLE_HAISHINKIT=1 MAC_STREAM_ENABLE_MLX=1 swift build
./script/build_and_run.sh --verify
codesign --verify --strict dist/MacStream.app
```

Confirm:

- the working tree is clean,
- `CHANGELOG.md` contains the version and release date,
- `docs/releases/vX.Y.Z.md` exists and describes the shipped version,
- `MacStream.app` launches,
- the bundle identifier is `com.ideaplexa.macstream`,
- the app icon appears in Finder,
- the packaged app contains `LICENSE`, `THIRD_PARTY_NOTICES.md`, and fetched
  dependency license files under `Contents/Resources`,
- the expected signing identity is present,
- packaged Camera, Microphone, and Screen Recording permission recovery works,
- local `Screen` and composited `Screen + Webcam` recordings play back correctly,
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

Manual non-publishing release builds are available from the `Release` workflow
in GitHub Actions. They still use production signing credentials, submit the app
and DMG to Apple notarization, and sign the Sparkle update; they only skip the
GitHub Release and appcast publication steps. Manual publishing requires
`publish_release=true` and an existing matching tag.

## Artifacts

The release workflow creates two signed and notarized distribution formats:

```text
MacStream-vX.Y.Z-macos-arm64.dmg
MacStream-vX.Y.Z-macos-arm64.dmg.sha256
MacStream-vX.Y.Z-macos-arm64.zip
MacStream-vX.Y.Z-macos-arm64.zip.sha256
```

Use the DMG for first-time installation. Keep the ZIP as the Sparkle update
payload because Sparkle signs and references that exact archive in `appcast.xml`.

Verify either artifact with:

```bash
shasum -a 256 dist/MacStream-vX.Y.Z-macos-arm64.dmg
shasum -a 256 dist/MacStream-vX.Y.Z-macos-arm64.zip
```

## Local Packaging Smoke

The CI packaging helper can be smoke-tested locally with ad-hoc signing. This does not notarize and does not replace the GitHub Actions release path:

```bash
MAC_STREAM_VERSION=0.7.0 \
MAC_STREAM_BUILD_NUMBER=1 \
MAC_STREAM_BUILD_CONFIGURATION=release \
MAC_STREAM_BUILD_ARCH="$(uname -m)" \
./script/package_macos_app.sh

/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" dist/MacStream.app/Contents/Info.plist
codesign --verify --strict --verbose=2 dist/MacStream.app
./script/package_macos_dmg.sh
hdiutil verify dist/MacStream-v0.7.0-macos-"$(uname -m)".dmg
```

To locally simulate release signing, provide `MAC_STREAM_CODESIGN_IDENTITY` and require hardened runtime:

```bash
MAC_STREAM_CODESIGN_IDENTITY="Developer ID Application: Ideaplexa LLC (53P98M92V7)" \
MAC_STREAM_ENABLE_HAISHINKIT=1 \
MAC_STREAM_REQUIRE_DEVELOPER_ID=1 \
MAC_STREAM_REQUIRE_HARDENED_RUNTIME=1 \
MAC_STREAM_REQUIRE_HAISHINKIT=1 \
MAC_STREAM_REQUIRE_RELEASE_SPARKLE_PUBLIC_KEY=1 \
MAC_STREAM_VERSION=0.7.0 \
MAC_STREAM_BUILD_NUMBER=1 \
./script/package_macos_app.sh
```

The release simulation fails if `Resources/Info.plist` contains the
`REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY` placeholder. The committed value is the
public update key; the private Sparkle signing key remains only in GitHub
Actions secrets.

## QA Checklist

1. Download the release DMG from GitHub.
2. Verify its SHA256, open it, and drag `MacStream.app` to `Applications`.
3. Confirm bundle identifier `com.ideaplexa.macstream`.
4. Test Camera, Microphone, and Screen Recording permission flows.
5. Grant Screen Recording, quit/reopen, and confirm access is detected.
6. Test `Webcam`, `Screen`, `Screen + Webcam`, and `BRB` preview scenes.
7. Start and stop Preview mode.
8. In the default build, verify RTMP wording says endpoint check, not Go Live.
9. Start and stop local Screen recording, then verify the `.mov`.
10. Start and stop local Screen + Webcam recording, then verify the camera composition is baked into the `.mov`.
11. In a HaishinKit build, start full RTMP publishing from Screen + Webcam and verify the remote output includes the camera composition.
12. Verify adaptive mode lowers capture cost under capture pressure.
13. Verify no optional provider or Keychain prompt appears on first launch and capture never depends on provider state.
14. Verify RTMP destination persistence and redaction in events/exports.
15. Export clip markers and session report twice in quick succession; confirm filenames do not collide.
16. Confirm the Sparkle ZIP remains downloadable and matches the enclosure URL and signature in `appcast.xml`.
17. Confirm the packaged app contains the AGPL text and third-party license notices.

## Rollback

If a release is broken:

1. Mark the GitHub release as pre-release or delete the release asset.
2. Open an issue with the failure and reproduction steps.
3. Fix on `main`.
4. Ship a patch tag, for example `v0.1.1`.

Avoid force-updating public tags unless explicitly approved.
