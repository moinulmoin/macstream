# OBS Core Feature Map For OpenCue

OpenCue should learn from OBS without becoming an OBS clone. The V1 goal is a smaller Mac-native studio for solo screen + camera creators.

## OBS Core Primitives

| OBS primitive | Why users rely on it | OpenCue V1 stance |
| --- | --- | --- |
| Scenes | Fast switching between stream layouts. | Keep four fixed scenes: `Face`, `Screen + Face`, `Screen`, `BRB`. |
| Sources | Cameras, displays, windows, apps, media, browser overlays, text, audio. | Keep camera, screen/window, mic, system audio. Skip arbitrary source graph for V1. |
| Source ordering and transforms | Camera PiP, overlays, crop, fit, resize. | Implement only opinionated compositor layouts first. Skip manual canvas editing. |
| Audio mixer | See levels, mute sources, avoid clipping, monitor output. | Keep source levels and mute/toggle controls; add real loudness/metering later. |
| Recording | Local archive independent of stream destination. | Core V1 requirement. Must support composited screen + face. |
| Streaming | RTMP/RTMPS publish with health feedback. | Core V1 requirement after local recording path is reliable. |
| Stream health | Diagnose dropped frames, encoding pressure, network problems. | Keep capture FPS, dropped frames, bitrate, latency, audio level, thermal/memory pressure. |
| Hotkeys | Control stream without touching UI. | Keep menu shortcuts; expand only after core workflows stabilize. |
| Profiles / scene collections | Separate setups for different shows. | Use lightweight workflow presets, not full scene collection management. |
| Plugins | Huge ecosystem. | Explicitly out of scope. |
| Virtual camera | Send OBS output to Zoom/Meet/etc. | Out of scope until compositor and signing/release are mature. |

## What OpenCue Should Keep

- First-run setup that gets camera, mic, screen, destination, and source readiness right.
- Fixed scene model for a smaller operating surface.
- Selected display/window shared by preview, signal sampling, recording, and publishing.
- Source toggles and levels that affect preview, media capture, and director signals.
- Local recording as a first-class path.
- RTMP media publish as a separately proven path.
- Clear transport labels: Preview, Endpoint Check, RTMP Publish.
- Health telemetry visible enough to prove capture reliability.
- Honest limitations when a scene cannot be captured yet.

## What OpenCue Should Skip For V1

- Arbitrary scene graph editing.
- Plugin compatibility.
- Browser overlays.
- Advanced transition authoring.
- Guest ingest.
- Virtual microphone or virtual camera distribution.
- Cloud-first AI.
- Model-controlled live scene switching.

## Current OpenCue Gap Against This Map

The store, source controls, setup flow, preview, recording boundary, and release automation are already in place. Local recording can now compose the creator's intended `Screen + Face` scene, but the RTMP publish path still needs to use that compositor before OpenCue can claim real screen + camera streaming.

That is the next foundation feature for streaming.
