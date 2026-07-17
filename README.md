<div align="center">

<img src=".github/assets/macstream-logo.png" width="148" height="148" alt="MacStream icon" />

# MacStream

### A native macOS studio for screen and webcam livestreams.

![macOS 26](https://img.shields.io/badge/macOS-26-111?logo=apple&logoColor=white)
![Swift 6](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
![Release](https://img.shields.io/github/v/release/moinulmoin/macstream?display_name=tag)
![CI](https://github.com/moinulmoin/macstream/actions/workflows/ci.yml/badge.svg)
![License](https://img.shields.io/badge/License-AGPL--3.0--only-blue)

<img src=".github/assets/macstream-studio.png" width="860" alt="MacStream Studio with the program preview and control room" />

</div>

## Overview

MacStream is a focused streaming app for Apple Silicon Macs. It is built for
solo creators who combine a display or window with a webcam: coding streams,
product demos, design sessions, workshops, and similar live formats.

The project prioritizes a reliable live path over broad production-suite
features:

- native ScreenCaptureKit and AVFoundation capture;
- configurable screen and webcam layouts;
- RTMP/RTMPS publishing;
- lightweight preview and adaptive performance controls;
- local recording as an optional companion to a stream;
- stream health, reconnect, and session diagnostics.

MacStream is not a video editor and is not trying to match every OBS feature.
AI-assisted setup, transcription, summaries, and camera effects are deferred
until capture, publishing, performance, and long-session reliability are proven.

## Install

Starting with v0.3, download the signed and notarized DMG from
[the latest GitHub Release](https://github.com/moinulmoin/macstream/releases/latest),
open it, and drag `MacStream.app` to `Applications`.

The ZIP asset on each release is used by Sparkle for in-app updates. First-time
installations should use the DMG.

MacStream requires macOS 26 and Camera, Microphone, and Screen Recording
permissions for the relevant sources.

## Features

### Studio

- Webcam, Screen + Webcam, Screen, and BRB scenes
- Display and individual-window capture
- Explicit camera, microphone, display, and window selection
- Live microphone input meter
- Preflight checks for permissions, sources, and stream destination
- Tabbed Live, Layout, Sources, and Health controls

### Layout

- Side-by-side screen and webcam presets
- Adjustable source split, gap, and canvas padding
- Independent screen and webcam zoom and viewport positioning
- Adjustable source corner radius
- Preset colors, custom colors, and local background images
- Preview quality controls independent from encoded output quality

The program preview and the stream/recording compositor share the same layout
settings so the configured output is represented before going live.

### Streaming And Recording

- RTMP and RTMPS publishing with the HaishinKit release build
- Up to three simultaneous RTMP/RTMPS destinations from one composed output
- Destination presets for Twitch, YouTube, Facebook, X, Kick, and custom ingest
- Per-destination connection, throughput, queue, failure, and reconnect status
- Stream keys stored per destination in Keychain and redacted from UI, logs, and exports
- Automatic runtime reconnect with recovery outcome and downtime tracking
- Optional record-while-streaming workflow
- Local `.mov` recording for Screen and composited Screen + Webcam
- Configurable output resolution and frame rate
- Sparkle automatic updates from signed release ZIPs

### Performance And Health

- Adaptive, Efficiency, Balanced, and Responsive performance modes
- Reduced-cost preview without reducing encoded stream quality
- Thermal state, memory pressure, Low Power Mode, FPS, and dropped-frame signals
- RTMP throughput, append backlog, and backpressure monitoring
- Current and maximum observed A/V drift
- Recovery, interruption, and recording status in session reports
- Long-session process metrics recorder for CPU, memory, and thread-count QA

## Current Scope

MacStream is a personal-use prototype shared for testing. It may contain bugs,
and streams should be validated with a private or test destination before relying
on it for important broadcasts.

| Area | Current direction |
| --- | --- |
| Streaming | Primary product workflow |
| Recording | Optional local copy during or outside a stream |
| Video editing | Out of scope |
| Multi-destination streaming | Up to three independent RTMP/RTMPS targets |
| Native camera effects | Under evaluation |
| AI and transcription | Deferred roadmap work |
| Intel Macs | Not currently targeted |

## Build From Source

Prerequisites:

- Xcode with the macOS 26 SDK
- Swift 6
- Apple Silicon Mac

```bash
git clone https://github.com/moinulmoin/macstream.git
cd macstream

swift build
swift test
./script/build_and_run.sh
```

The packaged app is written to `dist/MacStream.app`.

### Build Variants

```bash
# Dependency-light development build.
swift build

# Real RTMP/RTMPS publishing.
MAC_STREAM_ENABLE_HAISHINKIT=1 swift build

# Experimental adapter compile check only; not part of the core product path.
MAC_STREAM_ENABLE_MLX=1 swift build

# Package a local signed app bundle.
./script/package_macos_app.sh

# Create a local DMG from the packaged app.
./script/package_macos_dmg.sh
```

Release artifacts are built by GitHub Actions with the HaishinKit publishing
path enabled, Developer ID signing, hardened runtime, Apple notarization, and
stapled tickets.

## Architecture

```text
Sources/
  MacStream/           SwiftUI application and native preview adapters
  MacStreamCore/       Models, StudioStore, capture, composition, and publishing
Tests/
  MacStreamCoreTests/  Swift Testing suites and injected system fakes
Resources/             Info.plist, entitlements, and application assets
script/                Build, packaging, release, and reliability tooling
```

Core rules:

- `StudioStore` is the single `@MainActor @Observable` source of truth.
- `MediaPipeline` implementations own capture, recording, and publishing state.
- Sample-buffer hot paths avoid per-frame allocations and main-thread hops.
- Stream keys remain in Keychain and are redacted from every exported surface.
- Model output cannot control live scene switching or enter the capture hot path.

## Development

Run the default and release publishing test configurations from the repository
root:

```bash
swift test
MAC_STREAM_ENABLE_HAISHINKIT=1 swift test
```

Useful project documents:

- [Changelog](CHANGELOG.md)
- [Contributing](CONTRIBUTING.md)
- [License](LICENSE)
- [Third-Party Notices](THIRD_PARTY_NOTICES.md)
- [Release Notes](docs/releases/v0.3.0.md)
- [Architecture](docs/architecture.md)
- [Current State](docs/current-state.md)
- [Reliability Goal](docs/v0.3-reliability-goal.md)
- [QA Checklist](docs/qa-checklist.md)
- [Release Process](docs/releasing.md)
- [Launch Readiness](docs/launch-readiness.md)

Issues and focused pull requests are welcome. Do not include stream keys,
credentials, signed certificates, or generated build output.

## License

MacStream is free software licensed under the
[GNU Affero General Public License v3.0 only](LICENSE). Redistribution and
qualifying remote-network use of modified versions must follow its corresponding
source requirements.
