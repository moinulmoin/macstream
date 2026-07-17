# Changelog

All notable changes to MacStream are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.0] - 2026-07-17

### Added

- Added direct first-run Camera and Microphone permission requests with precise System Settings and Screen Recording relaunch guidance.
- Added public AVFoundation status for Continuity Camera, Center Stage, Portrait, Studio Light, Background Replacement, and Reactions.
- Added a shortcut to Apple's system-owned Video Effects interface without private APIs or simulated app controls.
- Added operator guidance for failed starts, reconnecting streams, recovery failure, and current RTMP backpressure.

### Changed

- Validated every enabled RTMP destination during preflight while preserving the user's explicit RTMP intent.
- Unified camera discovery across setup, preview, effects status, recording, and publishing, including Continuity Camera and Desk View.
- Reduced microphone meter processing to a human-visible cadence while preserving every audio delivery callback.
- Skipped shared video composition when every active RTMP lane is currently saturated and no local recording needs the frame.
- Refreshed RTMP queue and aggregate health from current publisher state before render admission.

### Fixed

- Prevented local recording success from being mistaken for delivery of the first RTMP video frame.
- Prevented cumulative rejection and recovery counters from leaving stale operator guidance after a lane or later stream attempt recovered.
- Removed duplicate permission actions and routed destination setup actions to the correct Settings tab.

## [0.5.0] - 2026-07-17

### Added

- Added full-screen content with a native person-segmented presenter overlay.
- Added left, right, top, bottom, and manual presenter placement with adjustable scale.
- Added asynchronous, coalesced Vision segmentation capped at 12 FPS so inference cannot block capture or publishing.

### Changed

- Shared presenter geometry across setup preview, recording, and RTMP program output.
- Kept camera zoom and pan independent from presenter placement and scale.
- Fell back to a framed webcam overlay when a current segmentation matte is unavailable, stale, or mismatched with the latest camera frame.
- Hot-applied presenter layout changes without restarting active screen or camera capture.

## [0.4.0] - 2026-07-17

### Added

- Added up to three simultaneous RTMP/RTMPS destinations from one shared capture and composition path.
- Added per-destination connection, throughput, queue, failure, and reconnect status in the studio.
- Added UUID-keyed destination metadata and per-destination Keychain secrets.
- Added per-destination backpressure detection with visible degraded state and rejection counts.

### Changed

- Licensed MacStream under GNU AGPL v3.0 only.
- Embedded project and dependency license notices in packaged applications.
- Made release documentation strict for every tag without release-specific exceptions.
- Defined sequential v0.4, v0.5, and v0.6 core-product milestones.
- Removed pre-current layout, background, and health-payload decoding branches.
- Changed session reports to export every destination and its runtime state without endpoint URLs or stream keys.
- Redacted RTMP transport failures and separated pasted publish URLs from stream keys before persistence.

## [0.3.0] - 2026-07-17

### Added

- Signed, notarized, and stapled DMG distribution for first-time installation.
- Runtime RTMP recovery with interruption outcome and downtime tracking.
- A/V drift, RTMP throughput, append-backlog, and backpressure telemetry.
- Long-session process metrics recorder for CPU, memory, and thread-count QA.
- Real HaishinKit publishing validation against a local RTMP ingest in CI.

### Changed

- Made streaming reliability, layout fidelity, and performance the explicit
  product priorities while deferring AI features.
- Separated preview quality from encoded output quality.
- Expanded release validation for Developer ID signing, notarization,
  Gatekeeper, Sparkle signing, and artifact checksums.

### Fixed

- Stabilized composited Screen + Webcam recording.
- Bounded RTMP queue shutdown and timeout behavior.
- Hardened publisher lifecycle and release integration tests.

## [0.2.2] - 2026-07-16

### Fixed

- Stabilized the signed release gate and Sparkle signer discovery.

## [0.2.1] - 2026-07-16

### Fixed

- Signed Sparkle's updater components for notarized distribution.
- Preserved and surfaced Apple notarization diagnostics on failure.

## [0.2.0] - 2026-07-16

### Added

- Native screen, window, camera, and microphone source selection.
- Screen, Webcam, Screen + Webcam, and BRB scenes.
- Configurable canvas backgrounds, split layouts, padding, gaps, source zoom,
  viewport positioning, and corner radii.
- RTMP destination presets, Keychain-backed stream keys, and Sparkle updates.
- Local composited recording and stream health controls.

### Changed

- Renamed the app from OpenCue to MacStream.
- Unified preview, recording, and publishing around the shared canvas model.
- Reworked the studio into focused Live, Layout, Sources, and Health controls.

### Fixed

- Removed the unnecessary first-launch Keychain prompt.
- Reduced preview and capture work while live.
- Hardened RTMP media routing, source setup, and cancellation behavior.

## [0.1.0] - 2026-05-30

### Added

- Initial OpenCue macOS streaming prototype.
- SwiftUI studio, capture pipeline, local recording, CI, and packaging support.

[Unreleased]: https://github.com/moinulmoin/macstream/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/moinulmoin/macstream/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/moinulmoin/macstream/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/moinulmoin/macstream/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/moinulmoin/macstream/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/moinulmoin/macstream/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/moinulmoin/macstream/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/moinulmoin/macstream/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/moinulmoin/macstream/releases/tag/v0.1.0
