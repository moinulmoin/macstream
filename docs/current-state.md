# Current State

MacStream is a personal-use macOS 26 prototype focused on Apple Silicon
streaming performance and reliability.

## Implemented

- Native SwiftUI studio with Webcam, Screen + Webcam, Screen, and BRB scenes.
- AVFoundation camera and microphone capture.
- ScreenCaptureKit display and window capture.
- Configurable backgrounds, padding, source gap, split presets, corner radius,
  source zoom, and viewport positioning.
- Independent preview-cost and encoded-output settings.
- Permission and source preflight with idle-only device rescans.
- Local Screen and composited Screen + Webcam `.mov` recording.
- Optional record-while-streaming behavior.
- RTMP/RTMPS endpoint validation in the dependency-light build.
- HaishinKit publishing build for real RTMP/RTMPS media output.
- Runtime reconnect with interruption, outcome, and downtime metrics.
- A/V drift, throughput, dropped-frame, and RTMP append-queue health.
- Adaptive performance response to capture pressure and macOS system state.
- Clip markers and redacted session reports.
- Keychain-backed stream destination secrets.
- Sparkle updates through signed ZIP artifacts.
- Developer ID, hardened runtime, notarization, and DMG release automation.

## v0.3 Release Gates

- Complete long-duration RTMP and RTMP-plus-recording runs.
- Validate short and sustained network interruption recovery.
- Collect CPU, memory, and thread-count evidence under representative capture.
- Confirm acceptable A/V drift and no unbounded RTMP queue growth.
- Test packaged permission recovery on a clean macOS user or machine.
- Prove the final signed, notarized, and stapled DMG through Gatekeeper.

The detailed budgets and scenarios are in
[v0.3-reliability-goal.md](v0.3-reliability-goal.md).

## Deferred

- Multi-destination simultaneous streaming.
- Presenter cutout and green-screen-style webcam composition.
- Native camera effects such as Center Stage, Portrait, and Studio Light control.
- Video editing and post-production.
- AI setup, transcription, summaries, and cue explanations.

Existing experimental provider and MLX scaffolding remains optional, must compile
in CI, and cannot enter or block the live capture path.
