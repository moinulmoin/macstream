# Current State

MacStream is a personal-use macOS 26 prototype focused on Apple Silicon
streaming performance and reliability.

The current public release is
[v0.6.0](https://github.com/moinulmoin/macstream/releases/tag/v0.6.0). Its
[release notes](releases/v0.6.0.md), signed and notarized artifacts, checksums,
and Sparkle appcast are published. See the [changelog](../CHANGELOG.md) for
release history.

## Implemented

- Native SwiftUI studio with Webcam, Screen + Webcam, Screen, and BRB scenes.
- AVFoundation camera and microphone capture.
- ScreenCaptureKit display and window capture.
- Configurable backgrounds, padding, source gap, split presets, corner radius,
  source zoom, and viewport positioning.
- Full-screen content with native presenter cutout, edge presets, manual
  placement, adjustable scale, and framed fallback.
- Independent preview-cost and encoded-output settings.
- Permission and source preflight with idle-only device rescans.
- Native Camera and Microphone permission requests plus Screen Recording relaunch guidance.
- Continuity Camera and Desk View discovery across setup, preview, and program capture.
- Public native camera-effect status with access to Apple's Video Effects interface.
- Local Screen and composited Screen + Webcam `.mov` recording.
- Optional record-while-streaming behavior.
- RTMP/RTMPS endpoint validation in the dependency-light build.
- HaishinKit publishing build for real RTMP/RTMPS media output.
- One composed output fanned out to as many as three independently queued destinations.
- Per-destination throughput, failure, reconnect, and Keychain-backed secret state.
- Runtime reconnect with interruption, outcome, and downtime metrics.
- A/V drift, throughput, dropped-frame, and RTMP append-queue health.
- Adaptive performance response to capture pressure and macOS system state.
- Clip markers and redacted session reports.
- Keychain-backed stream destination secrets.
- Sparkle updates through signed ZIP artifacts.
- Developer ID, hardened runtime, notarization, and DMG release automation.

## Ongoing Validation

The automated release gate covers real RTMP ingest, encoded H.264 validation,
bounded queues, recovery behavior, signing, notarization, stapling, Gatekeeper,
and artifact checksums. Ongoing manual confidence work includes:

- repeated 60-minute RTMP and RTMP-plus-recording sessions;
- short and sustained network interruption recovery on real destinations;
- CPU, memory, thermal, thread-count, and A/V drift comparisons across Macs;
- packaged permission recovery on clean macOS users or machines.

The detailed budgets, scenarios, and evidence requirements remain in
[v0.3-reliability-goal.md](v0.3-reliability-goal.md).

## Sequential Roadmap

MacStream works on one release goal at a time. The next milestone does not begin
until the current milestone is implemented, reviewed, validated, and shipped.
Scope can change after each release based on real usage.

### v0.4 - Multi-Destination Streaming (shipped)

- Configure and persist multiple RTMP/RTMPS destinations.
- Publish the same composed program output to selected destinations.
- Track connection, throughput, failure, and reconnect state independently.
- Keep publisher queues bounded so one slow destination cannot stall the others.
- Provide clear start, partial-failure, retry, and stop behavior in the studio.

### v0.5 - Presenter Composition (shipped)

- Add full-screen content with a movable presenter cutout overlay.
- Provide left, right, top, and bottom placement presets plus manual positioning.
- Keep captured program preview, stream, and recording output visually identical;
  use a framed fallback in the idle setup preview.
- Fall back cleanly when person segmentation is unavailable or too expensive.

### [v0.6 - Workflow Polish And Measured Performance](v0.6-workflow-performance-goal.md) (shipped)

- Tighten first-run permissions, destination setup, and recovery guidance.
- Report native camera-effect status and open system-owned controls only where
  public macOS APIs provide reliable support.
- Optimize CPU, memory, and latency from measured real-session bottlenecks
  instead of speculative micro-optimization.

The next milestone will be selected from real streaming evidence after v0.6,
rather than stacking speculative roadmap work before this release is used.

## Deferred

- Video editing and post-production.
- AI setup, transcription, summaries, and cue explanations.

Existing experimental provider and MLX scaffolding remains optional, must compile
in CI, and cannot enter or block the live capture path.
