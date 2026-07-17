# Changelog

All notable changes to MacStream are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/moinulmoin/macstream/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/moinulmoin/macstream/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/moinulmoin/macstream/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/moinulmoin/macstream/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/moinulmoin/macstream/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/moinulmoin/macstream/releases/tag/v0.1.0
