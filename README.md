<div align="center">

<img src=".github/assets/macstream-logo.png" width="148" height="148" alt="MacStream icon" />

# MacStream

### A Mac-native streaming studio with a built-in director.

MacStream is a focused OBS alternative for macOS: full-bleed preview, explicit
source selection, preflight before live, local recording, RTMP targets, and a
deterministic director layer that helps without touching the hot capture path.

![macOS 26](https://img.shields.io/badge/macOS-26-111?logo=apple&logoColor=white)
![Swift 6](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0A84FF)
![ScreenCaptureKit](https://img.shields.io/badge/capture-ScreenCaptureKit-5E6AD2)
![Tests](https://img.shields.io/badge/tests-swift%20test-30A46C)

<img src=".github/assets/macstream-studio.png" width="860" alt="MacStream Studio showing preview, control room, and preflight" />

</div>

---

## The idea

OBS is powerful. MacStream is intentionally narrower: a polished Mac control room
for creators who mostly need **screen, face, recording, and clean live output** —
not a node graph and a thousand knobs.

The product line is simple:

- **Preview first.** The program monitor is the main object, not a tiny debug view.
- **Preflight before panic.** Scene, capture, sources, destination, and permissions
  are surfaced before the stream starts.
- **Choose real devices.** Camera, microphone, and display/window inputs are
  explicit pickers with refresh controls.
- **AI stays off the encoder.** Models can help plan setups, explain cues, and
  summarize sessions; live switching stays deterministic and testable.

## What works today

### Studio

- Fixed creator scenes: `Face`, `Screen + Face`, `Screen`, and `BRB`.
- Full-bleed SwiftUI program preview.
- AVFoundation camera preview.
- ScreenCaptureKit screen/window preview.
- Control Room for scene, director mode, output, recording, and performance mode.
- Inspector-side preflight checklist with the next required action.

### Sources

- Camera picker with refresh.
- Microphone picker with refresh.
- Screen/display picker with refresh.
- Selections persist and flow into preview, recording, RTMP configuration, and
  director signals.

### Recording and streaming

- Local `.mov` recording for `Screen`.
- Local composited `.mov` recording for `Screen + Face` with camera PiP baked in.
- System audio plus best-effort microphone audio where the active capture path
  supports it.
- Destination presets for Twitch, YouTube, Facebook, X, Kick, and Custom.
- RTMP/RTMPS URL validation in the default build.
- Optional HaishinKit build path for `Screen` and composited `Screen + Face` RTMP/RTMPS publishing experiments.
- Stream keys stored in Keychain and redacted in UI/log/report surfaces.

### Director layer

- `Paused`, `Suggest`, and countdown-gated `Auto` modes.
- Typed local signals: motion, speech, app focus, idle, capture health, and
  system pressure.
- Adaptive performance mode that can lower capture cost under pressure.
- Clip markers and JSON session reports with secrets redacted.

## Pre-release limits

This is still a pre-release core. The strongest proof path today is local preview
and recording. Before calling it release-grade streaming software, the real RTMP
path still needs live ingest QA for:

- remote `Screen + Face` PiP verification;
- A/V sync over long sessions;
- bitrate stability and reconnect behavior;
- packaged-app permission recovery on a fresh Mac;
- Developer ID signing, notarization, stapling, and Gatekeeper launch proof.

## Quick start

```bash
git clone git@github.com:moinulmoin/macstream.git
cd macstream

swift build
swift test
./script/build_and_run.sh
```

The packaged app is written to:

```text
dist/MacStream.app
```

Bundle id:

```text
com.ideaplexa.macstream
```

## Going live

1. Open **Settings → Destination**.
2. Pick a quick-connect platform.
3. Paste the stream key after the prefilled ingest URL, or paste the full URL for
   paste-only platforms.
4. For real RTMP publishing today, choose `Screen + Face` or `Screen`.
5. Confirm Preflight is ready.
6. Start the stream.

```bash
MAC_STREAM_ENABLE_HAISHINKIT=1 swift build
```

Real RTMP/RTMPS publishing is behind the HaishinKit build flag and currently
targets `Screen` plus composited `Screen + Face`. The default build validates the
endpoint but does not publish media.

## AI direction

MacStream's AI strategy is provider-first, but the current runtime is still
rules-first until the adapters land:

- **Rules** are available today and keep the app deterministic.
- **Foundation Models** are the planned native macOS 26 path where available.
- **OpenAI-compatible local servers** are the planned flexible path for LM Studio,
  Ollama, llama.cpp, MLX server, and other user-owned runtimes.
- **Managed MLX** is not part of the default app until cold start, tokens/sec,
  memory pressure, GPU contention, unload reliability, model footprint, and crash
  isolation are proven.

Good AI use cases for this app:

- setup assistant from natural language to a typed profile;
- preflight coach for missing permissions or dead sources;
- director explanations based on local signals;
- clip title suggestions;
- post-session health summaries;
- slow sampled-frame review outside the live hot path.

## Build variants

```bash
swift build                                  # default dependency-light build
MAC_STREAM_ENABLE_HAISHINKIT=1 swift build   # RTMP/RTMPS publishing path
MAC_STREAM_ENABLE_MLX=1 swift build          # experimental MLX adapter shell
./script/package_macos_app.sh                # signed local app bundle
```

## Architecture

```text
Sources/
  MacStream/          SwiftUI app shell, views, native previews
  MacStreamCore/      Store, media pipeline, director engine, models, services
Tests/
  MacStreamCoreTests/ Behavior tests and guardrails
Resources/            Info.plist, entitlements, app icon
script/               build, package, and icon tooling
```

Core rules:

- `StudioStore` is the single observable source of truth.
- `MediaPipeline` owns capture, recording, and publish state.
- `MediaPipelineConfiguration` carries scene kind, destination, and selected
  device IDs into the pipeline.
- `DirectorEngine` consumes typed `SignalSnapshot`s; no model drives live scene
  switching.
- Secrets are redacted before they leave the narrow destination/keychain layer.

Read more:

- [Architecture](docs/architecture.md)
- [Current state & next plan](docs/current-state.md)
- [MVP scope](docs/mvp-scope.md)
- [Technical risks](docs/technical-risks.md)
- [OBS feature map](docs/obs-core-feature-map.md)
- [QA checklist](docs/qa-checklist.md)
- [Release process](docs/releasing.md)

## Requirements

- macOS 26 SDK / matching Xcode toolchain.
- Swift 6.
- Camera, Microphone, and Screen Recording permissions for the relevant workflows.

## Status

`v0.1.0` core spine. The app has a polished studio shell, explicit source UX,
preflight, local recording, destination setup, and deterministic director logic.
The next milestone is proving long-session capture/record/RTMP behavior on real
hardware and real ingest endpoints.
