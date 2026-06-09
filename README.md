<div align="center">

<img src=".github/assets/macstream-logo.png" width="128" height="128" alt="MacStream icon" />

# MacStream

**A calm, native macOS streaming studio — with a director that watches the signals so you don't have to.**

Stream and record your screen + camera from a Mac-native app that proves it's ready before you go live, keeps the live controls quiet, and lets a deterministic director surface scene cues from local motion, speech, and focus.

![macOS 26](https://img.shields.io/badge/macOS-26-111?logo=apple&logoColor=white)
![Swift 6](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0A84FF)
![ScreenCaptureKit](https://img.shields.io/badge/capture-ScreenCaptureKit-5E6AD2)
![Tests](https://img.shields.io/badge/tests-229%20passing-30A46C)

<img src=".github/assets/macstream-studio.png" width="760" alt="MacStream studio" />

</div>

---

## Why MacStream

It is **not** an OBS clone. The direction is smaller and more Mac-native:

- **Preflight that means it.** Camera, mic, screen, and permissions are checked up front — you can't "go live" into a black frame.
- **A program monitor, not a node graph.** Four honest scenes (`Face`, `Screen + Face`, `Screen`, `BRB`) and a full-bleed preview. No endless source trees.
- **A deterministic director.** `Suggest` / `Auto` / `Paused` cues come from typed local signals (motion, speech, app focus, idle) — never from a model in the hot path.
- **Local-first AI, on the side.** Setup plans and session summaries run on-device via Foundation Models or any OpenAI-compatible local server. The capture/encode path stays AI-free.

## Features

**Capture & record**
- Native SwiftUI app with a full-bleed program preview.
- Camera preview via AVFoundation; screen/window capture via ScreenCaptureKit.
- Local `.mov` recording for `Screen` and **composited `Screen + Face`** (camera PiP baked in), with system + best-effort mic audio.

**Inputs — pick and refresh**
- Per-input **device pickers** for camera, microphone, and screen — choose the exact device, with a one-click **Refresh** to re-scan.
- Selections are honored end-to-end (preview, recording, and RTMP) and persist across launches.

**Go live**
- **One-click destination presets:** Twitch, YouTube, Facebook, X, Kick, Custom — prefilled ingest URLs where they're stable, paste-only where they're account-specific.
- RTMP/RTMPS endpoint validation in the default build; optional HaishinKit path for real `Screen` and composited `Screen + Face` egress.
- Stream keys are redacted everywhere they're displayed, logged, or persisted (Keychain).

**Director & performance**
- Deterministic director engine with countdown-gated `Auto` switching.
- Adaptive performance mode that lowers capture cost under system pressure or dropped frames.
- Clip markers and session reports exported as JSON (secrets redacted).

## Quickstart

```bash
git clone git@github.com:moinulmoin/macstream.git
cd macstream

swift build          # default, dependency-light
swift test           # 229 tests
./script/build_and_run.sh           # build + launch the app bundle
./script/build_and_run.sh --verify  # + bundle/signing/launch checks
```

The packaged app lands at `dist/MacStream.app` (bundle id `com.ideaplexa.macstream`).

## Going live

1. **Settings → Destination → Quick connect** — pick your platform; the ingest URL is prefilled (or you get a hint where to grab it).
2. Paste your **stream key** after the prefilled base.
3. Pick your **Scene** and confirm **Sources** are armed in the Control Room.
4. Hit **Go Live**.

> Real RTMP egress requires the optional HaishinKit build. The default build validates the endpoint without publishing media.

## Optional builds

```bash
MAC_STREAM_ENABLE_HAISHINKIT=1 swift build   # real RTMP/RTMPS publishing
MAC_STREAM_ENABLE_MLX=1 swift build          # experimental on-device MLX adapter
```

Both are opt-in so the default MVP stays fast and dependency-light. The default AI runtime is rule-based; provider adapters (Foundation Models + OpenAI-compatible) are the first-class path, and managed MLX is explicitly experimental.

## Architecture

```
Sources/
  MacStream/         SwiftUI app — views, native AV/SC previews, app shell
  MacStreamCore/     Store, media pipeline, director engine, models, services
Tests/
  MacStreamCoreTests/  Behavior + guardrail tests
Resources/           Info.plist, entitlements, app icon
script/              build_and_run.sh, package_macos_app.sh, generate_app_icon.py
```

- `StudioStore` is the single observable source of truth; the UI is a pure projection of it.
- `MediaPipeline` owns capture/record/publish; device IDs and scene kind flow in via `MediaPipelineConfiguration`.
- The director consumes typed `SignalSnapshot`s — deterministic and testable, off the encode path.

See [docs/architecture.md](docs/architecture.md) for the full picture.

## Requirements

- macOS 26 SDK / matching Xcode toolchain, Swift 6.0.
- Camera, Microphone, and Screen Recording permissions for the relevant workflows.

## Docs

- [Current state & next plan](docs/current-state.md) · [Product brief](docs/product-brief.md) · [MVP scope](docs/mvp-scope.md)
- [Architecture](docs/architecture.md) · [Technical risks](docs/technical-risks.md) · [OBS feature map](docs/obs-core-feature-map.md)
- [QA checklist](docs/qa-checklist.md) · [Benchmark plan](docs/benchmark-plan.md) · [Release process](docs/releasing.md)

## Status

`v0.1.0` MVP spine. Strongest proof path today is local capture: `Screen` and composited `Screen + Face` recording, plus the optional HaishinKit RTMP publish through the same compositor. Distribution is via GitHub Releases (signed, notarized, stapled); no in-app updater yet.
