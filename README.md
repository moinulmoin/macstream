<div align="center">

<img src=".github/assets/macstream-logo.png" width="148" height="148" alt="MacStream icon" />

# MacStream

### Build the stream layout, preview it, and go live with confidence.

A Mac-native streaming studio for solo creators who stream camera and screen,
with recording and AI as secondary, optional layers.

![macOS 26](https://img.shields.io/badge/macOS-26-111?logo=apple&logoColor=white)
![Swift 6](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0A84FF)
![ScreenCaptureKit](https://img.shields.io/badge/capture-ScreenCaptureKit-5E6AD2)
![Tests](https://img.shields.io/badge/tests-14%20suites-30A46C)
![Version](https://img.shields.io/badge/version-v0.2.0-6366F1)

<img src=".github/assets/macstream-studio.png" width="860" alt="MacStream Studio showing preview, control room, and preflight" />

</div>

---

## What is MacStream?

MacStream is a macOS-native streaming studio for solo creators who do coding
streams, product demos, design streams, workshops, founder livestreams,
screen-share podcasts — any format that pairs a camera with a screen.

It is deliberately narrower than OBS. Instead of a node graph and a thousand knobs,
you get a polished Mac control room built around the actual solo-creator live
streaming workflow:

- **Preview first.** The program monitor fills the window — not a tiny debug thumbnail.
- **Layout is core.** Background, canvas padding, split ratios, source zoom, and
  preview cost are first-class controls.
- **Preflight before panic.** Scene, capture, sources, destination, and permissions are
  checked before the stream starts.
- **Explicit device pickers.** Choose your real camera, microphone, and display or
  window with refresh controls — no guessing what "Desktop Audio" means.
- **AI stays out of the core.** AI-assisted setup and transcription belong on the
  roadmap, but the live path remains deterministic, testable, and optimized first.

---

## Features

### Studio & Preview

- **Four fixed scenes:** `Face`, `Screen + Face`, `Screen`, and `BRB`
- Full-bleed SwiftUI program preview
- AVFoundation camera preview pipeline
- ScreenCaptureKit display and window capture
- Control Room panel with scene deck, stream/recording output, live mic input,
  and output performance controls
- Tabbed inspector for Live, Layout, Sources, and Health
- Studio Chrome design system: dark color scheme, glass-morphism cards,
  status badges with pulse animation, adaptive layout via `ViewThatFits`

### Source Management

- Camera picker with refresh (supports all AVCaptureDevice cameras)
- Microphone picker with refresh (supports all audio inputs)
- Screen and window picker with refresh (up to 6 shareable windows)
- Per-source enable/disable toggle with active-capture locking
- Adjustable levels for camera and microphone with live mic meter
- Camera enhancement controls: mirror toggle, exposure boost with brightness slider,
  rotation picker
- Selections persist across preview, recording, RTMP configuration, director
  signals, and session reports

### Recording & Streaming

- Local `.mov` recording for `Screen` (system audio + mic audio)
- Local composited `.mov` recording for `Screen + Face` (camera PiP baked into
  the video frame)
- Destination presets for Twitch, YouTube, Facebook, X, Kick, and Custom
- RTMP/RTMPS endpoint validation in the default build
- Full RTMP/RTMPS publishing for `Screen` and composited `Screen + Face`
  behind the HaishinKit build flag
- Stream keys stored in Keychain and redacted in UI, logs, events, and exports
- Live capture health monitoring: TX bytes/sec, dropped frames, capture FPS
- Rich stream state: `offline → connecting → live → degraded → failed`
- In-app auto-update via Sparkle — **Check for Updates…** in **Settings → About & Updates**, with updates delivered from EdDSA-signed GitHub Releases (`appcast.xml`)

### AI Roadmap

- AI-assisted setup, live transcription, summaries, and cue explanations are
  roadmap features.
- Any automated scene intelligence must stay deterministic and outside the hot
  capture path.
- Model-backed features must never compete with streaming, capture, publishing,
  or Apple Silicon performance work.

### Adaptive Performance

- Four performance modes: `Adaptive`, `Efficiency`, `Balanced`, `Responsive`
- `Adaptive` watches real-time system state: dropped frames, capture FPS,
  thermal pressure, Low Power Mode, memory pressure
- Lowers capture resolution, preview frame rate, and signal sampling under pressure
- Recovers to full quality when system health stabilizes
- Lock-free: capture, recording, and publishing state machines never overlap or
  get stuck

### Clip Markers & Session Reports

- Manual clip markers during capture (Cmd+Shift+M)
- Stream cue markers for scene changes and signal spikes
- JSON clip export with timestamp, scene, source state, and signal snapshot
- Session reports: destination, transport, recording path, source states,
  health timeline, signal history, clip markers, system pressure
- RTMP secrets redacted in all exports
- Duplicate-safe filenames: no collision on rapid re-export

### Future AI Setup Assistant

- Provider-first architecture is planned for optional setup help and future
  transcription workflows.
- Local and OpenAI-compatible providers remain opt-in, disabled during capture,
  and outside the live hot path.
- Experimental MLX adapter scaffolding is behind the `MAC_STREAM_ENABLE_MLX=1`
  build flag.

---

## Getting Started

### Prerequisites

- **macOS 26** SDK and matching Xcode toolchain
- **Swift 6.0**
- Camera, Microphone, and Screen Recording permissions granted in System Settings

### Quick Start

```bash
git clone git@github.com:moinulmoin/macstream.git
cd macstream

swift build
swift test
./script/build_and_run.sh
```

The packaged app lands at:

```text
dist/MacStream.app
```

Bundle identifier:

```text
com.ideaplexa.macstream
```

### Going Live

1. Open **Settings → Destination**
2. Pick a quick-connect platform preset (Twitch, YouTube, Facebook, etc.)
3. Confirm or paste the **Server URL**
4. Paste your private **Stream Key** in the dedicated field — it's stored in Keychain
   and never shown in plaintext
5. Build with the HaishinKit flag enabled for real RTMP publishing:

   ```bash
   MAC_STREAM_ENABLE_HAISHINKIT=1 swift build
   ```

6. Choose `Screen + Face` or `Screen` as your scene
7. Confirm **Preflight** is green — all permissions granted, sources active, destination ready
8. Click **Start Stream** in the Control Room

**Important:** The default build validates RTMP endpoints but does not publish media.
You must build with `MAC_STREAM_ENABLE_HAISHINKIT=1` to send video and audio to your
ingest server. The Control Room label reflects this honestly: "Endpoint Check" in the
default build, "Go Live" in the HaishinKit build.

**Recording without streaming** works in all builds — no flags required:

1. Choose `Screen` or `Screen + Face` as your scene
2. Click **Start Recording** in the Control Room
3. Local `.mov` files appear in `~/Movies/MacStream/`

---

## Build Variants

| Variant | Command | What you get |
|---------|---------|--------------|
| **Default** | `swift build` | Dependency-light. Full studio, preview, recording, endpoint validation. No media published. |
| **HaishinKit** | `MAC_STREAM_ENABLE_HAISHINKIT=1 swift build` | Full RTMP/RTMPS publish for Screen and composited Screen+Face |
| **MLX** | `MAC_STREAM_ENABLE_MLX=1 swift build` | Experimental on-device MLX adapter for setup plan generation |
| **Full** | `MAC_STREAM_ENABLE_HAISHINKIT=1 MAC_STREAM_ENABLE_MLX=1 swift build` | Both HaishinKit and MLX |

All four configurations are validated in CI on every push to `main`.

```bash
# Dependency-light default
swift build

# RTMP publishing path
MAC_STREAM_ENABLE_HAISHINKIT=1 swift build

# Experimental MLX adapter
MAC_STREAM_ENABLE_MLX=1 swift build

# Signed local app bundle (ad-hoc signing by default)
./script/package_macos_app.sh

# Signed local app bundle with Developer ID
MAC_STREAM_CODESIGN_IDENTITY="Developer ID Application: Ideaplexa LLC (53P98M92V7)" \
MAC_STREAM_VERSION=0.2.0 \
MAC_STREAM_BUILD_NUMBER=1 \
./script/package_macos_app.sh
```

---

## Architecture

```
Sources/
  MacStream/          SwiftUI app shell, 13 views, native preview wrappers, support utilities
  MacStreamCore/      Library: models, StudioStore (single source of truth), 11 services
Tests/
  MacStreamCoreTests/ 14 test suites (Swift Testing), shared fakes in TestSupport.swift
Resources/            Info.plist template, release entitlements, app icon source
script/               build, package, and icon generation tooling
```

**Core design rules:**

- `StudioStore` is the single `@MainActor @Observable` source of truth — all state
  mutations flow through it
- `MediaPipeline` owns capture, recording, and publish state — the live hot path
  stays free of per-frame allocations and main-thread hops
- `DirectorEngine` consumes typed `SignalSnapshot`s — no model output drives
  live scene switching
- Stream keys live in Keychain and are redacted in every surface: UI, logs, events,
  reports, and exports
- All service dependencies are injected via protocol abstractions — preview stubs
  and real system implementations share the same interface

Read the full specs:

- [Architecture](docs/architecture.md)
- [MVP Scope](docs/mvp-scope.md)
- [Product Brief](docs/product-brief.md)
- [Technical Risks](docs/technical-risks.md)
- [OBS Core Feature Map](docs/obs-core-feature-map.md)
- [Benchmark Plan](docs/benchmark-plan.md)
- [Current State](docs/current-state.md)

---

## Status

**v0.2.0 core streaming candidate — layout and performance first.**

What is production-quality today:

- Studio shell: full-bleed preview, explicit scene deck, responsive layout
- Source UX: real device pickers, per-source controls, live mic level, persistence
- Layout controls: background, canvas padding, split presets, screen/webcam zoom
- Preflight: capture permissions, device readiness, destination validation
- Local recording: Screen and composited Screen+Face with audio
- Adaptive performance: thermal/memory/pressure-aware capture scaling
- Clip markers and session reports with secret redaction
- AI/provider scaffolding is present but optional and outside the core live path
- 14 test suites, CI on every push, release pipeline with signing and notarization

Before calling this release-grade streaming software, the remaining gates are
concrete verification items — not architecture unknowns:

- Live RTMP ingest QA: remote Screen+Face PiP, long-session A/V sync, bitrate
  stability, reconnect
- Packaged-app permission recovery on a fresh Mac
- Developer ID signing → notarization → stapling → Gatekeeper end-to-end proof

Track progress on the [Launch Readiness Checklist](docs/launch-readiness.md).

---

## Operations

- [Release Process](docs/releasing.md) — versioning, tagging, CI/CD pipeline, signing, notarization
- [QA Checklist](docs/qa-checklist.md) — full pre-release quality gate
- [Launch Readiness Checklist](docs/launch-readiness.md) — all gates before public release

---

## Requirements

- macOS 26
- Swift 6.0
- Camera, Microphone, and Screen Recording permissions for relevant workflows
