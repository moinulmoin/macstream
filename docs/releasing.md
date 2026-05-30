# Release Process

This document is the release checklist for OpenCue. Keep releases boring: one version, one tag, verified artifacts, clear QA.

## Versioning

Use semver tags:

```text
vMAJOR.MINOR.PATCH
```

Examples:

- `v0.1.0` for the first MVP release.
- `v0.1.1` for a small fix.
- `v0.2.0` for a meaningful MVP feature step.

## Pre-Release Checks

Run these before tagging:

```bash
swift test
OPEN_CUE_ENABLE_HAISHINKIT=1 swift build
OPEN_CUE_ENABLE_MLX=1 swift build
./script/build_and_run.sh --verify
codesign --verify --strict dist/OpenCue.app
```

Confirm:

- the working tree is clean,
- `OpenCue.app` launches,
- the bundle identifier is `com.ideaplexa.opencue`,
- the expected signing identity is present,
- optional dependency builds still compile.

## Commit Shape

Prefer small release batches:

1. Product/app implementation.
2. Test coverage.
3. Documentation/release notes.

Do not mix generated build output into commits. `dist/`, `.build/`, and `.swiftpm/` should stay untracked.

## Tagging

Create an annotated tag:

```bash
git tag -a vX.Y.Z -m "OpenCue vX.Y.Z"
git push origin main
git push origin vX.Y.Z
```

Do not rewrite a published tag unless the release is known-bad and the owner explicitly approves the force update.

## Artifact

Build and zip the signed app:

```bash
./script/build_and_run.sh --verify
ditto -c -k --sequesterRsrc --keepParent dist/OpenCue.app dist/OpenCue-vX.Y.Z-macos-arm64.zip
```

Artifact naming:

```text
OpenCue-vX.Y.Z-macos-arm64.zip
```

Record the SHA256 digest from GitHub release metadata or with:

```bash
shasum -a 256 dist/OpenCue-vX.Y.Z-macos-arm64.zip
```

## GitHub Release

Create the release:

```bash
gh release create vX.Y.Z dist/OpenCue-vX.Y.Z-macos-arm64.zip \
  --repo moinulmoin/opencue \
  --title "OpenCue vX.Y.Z" \
  --notes-file /tmp/opencue-release-notes.md
```

Release notes should include:

- Highlights.
- Known limitations.
- Verification commands.
- QA focus.
- Artifact name and SHA256 digest.

## QA Checklist

1. Download the release zip from GitHub.
2. Unzip and launch `OpenCue.app`.
3. Confirm bundle identifier `com.ideaplexa.opencue`.
4. Test Camera, Microphone, and Screen Recording permission flows.
5. Grant Screen Recording, quit/reopen, and confirm access is detected.
6. Test `Face`, `Screen`, `Screen + Face`, and `BRB` preview scenes.
7. Start and stop Preview mode.
8. In the default build, verify RTMP wording says endpoint check, not Go Live.
9. Start and stop local Screen recording, then verify the `.mov`.
10. Confirm real Screen + Face recording/publishing is blocked until compositor support exists.
11. Verify adaptive mode lowers capture cost under capture pressure.
12. Verify RTMP destination persistence and redaction in events/exports.
13. Export clip markers and session report twice in quick succession; confirm filenames do not collide.

## Rollback

If a release is broken:

1. Mark the GitHub release as pre-release or delete the release asset.
2. Open an issue with the failure and reproduction steps.
3. Fix on `main`.
4. Ship a patch tag, for example `v0.1.1`.

Avoid force-updating public tags unless explicitly approved.
