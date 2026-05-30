# OpenCue

OpenCue is a native macOS streaming director for solo creators who stream screen and camera workflows. It is intentionally not an OBS clone. The MVP focuses on a small, reliable studio surface: choose a scene, verify capture readiness, preview or record, and let the director suggest stream cues from local signals.

## Current Status

This repository contains the `v0.1.0` MVP.

The current real media capture path records and publishes raw screen video only. `Screen + Face` is available for local preview and director planning, but real recording/full RTMP publishing is blocked for that scene until camera compositing lands.

## Features

- Native SwiftUI macOS app.
- Fixed scenes: `Face`, `Screen + Face`, `Screen`, and `BRB`.
- Camera preview through AVFoundation.
- Screen/window preview and recording through ScreenCaptureKit.
- Capture preflight for camera, microphone, display/window, and permission state.
- Local `.mov` screen recording with system audio and best-effort microphone audio.
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

The first GitHub release is:

- `v0.1.0`
- `OpenCue-v0.1.0-macos-arm64.zip`
- https://github.com/moinulmoin/opencue/releases/tag/v0.1.0

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
9. Confirm real `Screen + Face` recording/publishing is blocked until compositor support exists.
10. Verify adaptive mode lowers capture cost under dropped frames or low FPS.
11. Verify destination/source/settings persistence across relaunch.
12. Export clip markers and session report, then confirm RTMP secrets are redacted.

## Docs

- [Product brief](docs/product-brief.md)
- [MVP scope](docs/mvp-scope.md)
- [Architecture](docs/architecture.md)
- [Technical risks](docs/technical-risks.md)
- [Release process](docs/releasing.md)
