# OpenCue

OpenCue is a native macOS streaming director for solo creators who stream screen and camera workflows. It is intentionally not an OBS clone. The MVP focuses on a small, reliable studio surface: choose a scene, verify capture readiness, preview or record, and let the director suggest stream cues from local signals.

## Current Status

This repository contains the `v0.1.0` MVP.

The current real media capture path records raw `Screen` video and local composited `Screen + Face` video. Full RTMP publishing is still screen-only until the publish path uses the compositor.

## Features

- Native SwiftUI macOS app.
- Fixed scenes: `Face`, `Screen + Face`, `Screen`, and `BRB`.
- Camera preview through AVFoundation.
- Screen/window preview and recording through ScreenCaptureKit.
- Capture preflight for camera, microphone, display/window, and permission state.
- Local `.mov` recording for `Screen` and composited `Screen + Face`, with system audio and best-effort microphone audio.
- RTMP/RTMPS endpoint validation in the default dependency-light build.
- Optional HaishinKit RTMP publish build path.
- Deterministic director engine with `Suggest`, `Auto`, and `Paused` modes.
- Adaptive performance mode based on system pressure and capture health.
- Clip marker and session report JSON export with RTMP secrets redacted.
- Optional MLX local-intelligence build path for setup-rule generation.

## Requirements

- macOS 26 SDK / Xcode toolchain matching the package target.
- Swift 6.0 toolchain.
- Camera, Microphone, and Screen Recording permissions for the relevant workflows.

## Build

Default dependency-light build:

```bash
swift build
```

Run tests:

```bash
swift test
```

Build and launch the app bundle:

```bash
./script/build_and_run.sh
```

Verify bundle, signing, launch, and process presence:

```bash
./script/build_and_run.sh --verify
```

## Optional Builds

Enable HaishinKit RTMP publishing:

```bash
OPEN_CUE_ENABLE_HAISHINKIT=1 swift build
```

Enable MLX local intelligence dependencies:

```bash
OPEN_CUE_ENABLE_MLX=1 swift build
```

Both optional paths are intentionally opt-in so the default MVP stays fast and dependency-light.

## Release Artifact

The first GitHub release is a signed MVP artifact:

- `v0.1.0`
- `OpenCue-v0.1.0-macos-arm64.zip`
- https://github.com/moinulmoin/opencue/releases/tag/v0.1.0

New tagged releases are built through GitHub Actions with Developer ID signing, hardened runtime, notarization, stapling, checksum generation, and GitHub Release upload once the required Apple signing secrets are configured. See [Release process](docs/releasing.md).

OpenCue does not have an in-app auto-updater yet. The current distribution channel is GitHub Releases.

## QA Checklist

Before promoting a release:

1. Launch `OpenCue.app` from the zipped artifact.
2. Confirm bundle identifier is `com.ideaplexa.opencue`.
3. Test Camera, Microphone, and Screen Recording permission flows.
4. Confirm Screen Recording shows relaunch guidance after granting access.
5. Test `Face`, `Screen`, `Screen + Face`, and `BRB` preview scenes.
6. Start and stop a Preview session.
7. In the default build, confirm RTMP mode says endpoint check, not Go Live.
8. Start and stop local `Screen` recording and verify the `.mov` output.
9. Start and stop local `Screen + Face` recording and verify the camera PiP is baked into the `.mov`.
10. Confirm full RTMP publishing still blocks `Screen + Face` until publish composition exists.
11. Verify adaptive mode lowers capture cost under dropped frames or low FPS.
12. Verify destination/source/settings persistence across relaunch.
13. Export clip markers and session report, then confirm RTMP secrets are redacted.

## Docs

- [Product brief](docs/product-brief.md)
- [MVP scope](docs/mvp-scope.md)
- [Architecture](docs/architecture.md)
- [Technical risks](docs/technical-risks.md)
- [OBS core feature map](docs/obs-core-feature-map.md)
- [QA checklist](docs/qa-checklist.md)
- [Benchmark plan](docs/benchmark-plan.md)
- [Core app audit - 2026-05-31](docs/audits/core-app-audit-2026-05-31.md)
- [Release process](docs/releasing.md)
