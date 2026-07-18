<div align="center">

<img src=".github/assets/macstream-logo.png" width="144" height="144" alt="MacStream app icon" />

# MacStream

**A focused, Mac-native studio for screen and camera livestreams.**

[![Latest release](https://img.shields.io/github/v/release/moinulmoin/macstream?label=download)](https://github.com/moinulmoin/macstream/releases/latest)
[![CI](https://github.com/moinulmoin/macstream/actions/workflows/ci.yml/badge.svg)](https://github.com/moinulmoin/macstream/actions/workflows/ci.yml)
[![macOS 26](https://img.shields.io/badge/macOS-26%2B-black?logo=apple)](https://github.com/moinulmoin/macstream/releases/latest)
[![AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue)](LICENSE)

<img src=".github/assets/macstream-studio.png" width="960" alt="MacStream studio showing a screen and webcam composition" />

**[Download MacStream](https://github.com/moinulmoin/macstream/releases/latest)**

</div>

MacStream brings source setup, layout, streaming controls, and live health into
one native macOS workspace. Compose a screen or window with your camera and
microphone, then send exactly what you see in the preview to one or more
streaming services.

> **Early release:** MacStream is under active development and uses `0.x`
> versioning. Test your complete setup with a private stream before an important
> broadcast, and keep a fallback available for critical events.

## Features

- **Native capture:** Stream a display or individual window alongside built-in,
  external, or Continuity cameras.
- **Flexible layouts:** Use split-screen presets, picture-in-picture, or a
  freely positioned presenter overlay.
- **Presenter Cutout:** Use on-device person segmentation to remove the webcam
  background and place the presenter over shared content. Cutout is experimental;
  edge quality depends on the camera, lighting, movement, and background.
- **Direct canvas editing:** Select, drag, resize, crop, zoom, and pan sources in
  the preview.
- **Custom scenes:** Adjust source framing, padding, gaps, corner radius,
  background colors, and background images.
- **Multi-destination streaming:** Publish the same output to as many as three
  RTMP or RTMPS destinations simultaneously.
- **Local recording:** Save the composed output while streaming, or record it
  independently.
- **Output controls:** Choose resolution, frame rate, preview quality, and a
  capture-performance profile.
- **Live diagnostics:** Monitor microphone level, connection state, network
  throughput, dropped frames, audio/video timing, and reconnect attempts.
- **Private credentials:** Stream keys are stored in the macOS Keychain and
  redacted from the interface, logs, and exported reports.

## Compatibility

| Area | Current support |
| --- | --- |
| Streaming | RTMP and RTMPS using a server URL and stream key |
| Service presets | Twitch, YouTube, Facebook, Kick, X, and custom RTMP |
| Video | H.264 at 720p, 1080p, 2K, or 4K |
| Frame rate | 24, 30, or 60 FPS |
| Audio | AAC |
| Recording | QuickTime `.mov` with the same composed output |

Available resolution and frame rate combinations are not a guarantee that every
Mac, camera, network, or streaming service can sustain them. MacStream currently
uses stream keys and does not sign in to streaming-platform accounts.

## Getting Started

1. Download the latest `.dmg` from [GitHub Releases](https://github.com/moinulmoin/macstream/releases/latest).
2. Open the disk image and drag `MacStream.app` into `Applications`.
3. Launch MacStream and grant access to the camera, microphone, and screen
   sources you intend to use. Denied permissions can be changed later in
   **System Settings > Privacy & Security**.
4. Choose your sources and arrange the output from the **Layout** tab.
5. Add the server URL and stream key supplied by your streaming service, run a
   private test, and go live.

Official releases are signed with Developer ID, notarized by Apple, and include
published SHA-256 checksums. MacStream can install subsequent signed updates
through its built-in updater.

## Requirements

- Apple silicon Mac
- macOS 26 or later
- Camera, Microphone, and Screen Recording permissions as required by your setup
- An RTMP or RTMPS server URL and stream key for livestreaming

MacStream currently targets the macOS 26 SDK and APIs. Earlier macOS versions
and Intel Macs are not supported.

## Privacy

- Camera, microphone, and screen capture are processed on the Mac.
- Captured media is sent only to the streaming servers you configure.
- MacStream has no account system, advertising SDK, product analytics, or
  telemetry service.
- Stream keys are stored in the macOS Keychain. macOS may request Keychain
  approval when a key is first saved or accessed.
- Recordings and exported reports are written under `~/Movies/MacStream`.
- Update checks read the public MacStream update feed hosted on GitHub.

## Project Scope

The project is focused on live capture, composition, publishing, and optional
recording. It is not a post-production video editor or a replacement for a
full broadcast automation suite.

Bug reports and focused contributions are welcome in
[GitHub Issues](https://github.com/moinulmoin/macstream/issues).

## Build From Source

Building MacStream requires Xcode with Swift 6 and the macOS 26 SDK.

```bash
git clone https://github.com/moinulmoin/macstream.git
cd macstream

MAC_STREAM_ENABLE_HAISHINKIT=1 swift build
swift test
MAC_STREAM_ENABLE_HAISHINKIT=1 ./script/build_and_run.sh
```

Running `swift build` without the environment variable creates a smaller
development build without the RTMP publishing dependency. Official downloads
include RTMP publishing.

To create a local application bundle:

```bash
MAC_STREAM_ENABLE_HAISHINKIT=1 ./script/package_macos_app.sh
```

## Documentation

- [Changelog](CHANGELOG.md)
- [Contributing](CONTRIBUTING.md)
- [Architecture](docs/architecture.md)
- [QA checklist](docs/qa-checklist.md)
- [Release process](docs/releasing.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

## License

MacStream is licensed under the [GNU Affero General Public License v3.0](LICENSE).
