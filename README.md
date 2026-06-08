# MacStream

MacStream is a macOS 26-only native streaming studio for solo creators who stream screen and camera workflows. It is intentionally not an OBS clone. The product direction is smaller and more Mac-native: prove capture readiness, preview or record the intended scene, keep the live controls calm, and let a deterministic director surface cues from local signals.

## Current Status

This repository contains the `v0.1.0` MVP spine after the MacStream rename.

The strongest proof path today is local capture: `Screen` recording, composited `Screen + Face` recording, and the optional HaishinKit RTMP publish path that now uses the same Screen + Face compositor. The default dependency-light RTMP path remains endpoint validation only.

## Features

- Native SwiftUI macOS 26 app.
- Fixed scenes: `Face`, `Screen + Face`, `Screen`, and `BRB`.
- Camera preview through AVFoundation.
- Screen/window preview and recording through ScreenCaptureKit.
- Capture preflight for camera, microphone, display/window, and permission state.
- Local `.mov` recording for `Screen` and composited `Screen + Face`, with system audio and best-effort microphone audio.
- RTMP/RTMPS endpoint validation in the default dependency-light build.
- Optional HaishinKit RTMP publish build path for real `Screen` and composited `Screen + Face` egress validation.
- Deterministic director engine with `Suggest`, `Auto`, and `Paused` modes.
- Adaptive performance mode based on system pressure and capture health.
- Clip marker and session report JSON export with RTMP secrets redacted.
- Provider-first AI boundary for idle setup/review assistance. Foundation Models and OpenAI-compatible local providers are the intended first-class paths; MLX remains experimental and opt-in only.

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
MAC_STREAM_ENABLE_HAISHINKIT=1 swift build
```

Compile the experimental MLX adapter:

```bash
MAC_STREAM_ENABLE_MLX=1 swift build
```

Both optional paths are intentionally opt-in so the default MVP stays fast and dependency-light. MLX is not the default AI strategy; provider-first adapters land before any managed model runtime.

## Release Artifact

New tagged releases are built through GitHub Actions with Developer ID signing, hardened runtime, notarization, stapling, checksum generation, and GitHub Release upload once the required Apple signing secrets are configured. See [Release process](docs/releasing.md).

MacStream does not have an in-app auto-updater yet. The current distribution channel is GitHub Releases.

## QA Checklist

Before promoting a release:

1. Launch `MacStream.app` from the zipped artifact.
2. Confirm bundle identifier is `com.ideaplexa.macstream`.
3. Test Camera, Microphone, and Screen Recording permission flows.
4. Confirm Screen Recording shows relaunch guidance after granting access.
5. Test `Face`, `Screen`, `Screen + Face`, and `BRB` preview scenes.
6. Start and stop a Preview session.
7. In the default build, confirm RTMP mode says endpoint check, not Go Live.
8. Start and stop local `Screen` recording and verify the `.mov` output.
9. Start and stop local `Screen + Face` recording and verify the camera PiP is baked into the `.mov`.
10. In a HaishinKit build, start full RTMP publishing from `Screen + Face` and verify the remote output includes the camera PiP.
11. Verify adaptive mode lowers capture cost under dropped frames or low FPS.
12. Verify destination/source/settings persistence across relaunch.
13. Export clip markers and session report, then confirm RTMP secrets are redacted.
14. Confirm setup/AI assistance is idle-only and falls back visibly when no provider is configured.

## Docs

- [Current state and next build plan](docs/current-state.md)
- [Product brief](docs/product-brief.md)
- [MVP scope](docs/mvp-scope.md)
- [Architecture](docs/architecture.md)
- [Technical risks](docs/technical-risks.md)
- [OBS core feature map](docs/obs-core-feature-map.md)
- [QA checklist](docs/qa-checklist.md)
- [Benchmark plan](docs/benchmark-plan.md)
- [Core app audit - 2026-05-31](docs/audits/core-app-audit-2026-05-31.md)
- [Release process](docs/releasing.md)
