# Benchmark Plan

OpenCue should prove Mac-native reliability with repeatable measurements, not claims. Every benchmark should run OBS and OpenCue on the same Mac, same OS version, same devices, same capture target, same duration, and same network path when RTMP is involved.

## Benchmark Outputs

Store results under `benchmarks/` when this harness exists:

- `benchmarks/YYYY-MM-DD-machine-name.csv`
- `benchmarks/YYYY-MM-DD-machine-name.md`
- Optional screen recordings or screenshots only when they do not expose secrets.

## Test Matrix

| Area | Devices / states |
| --- | --- |
| Mac hardware | Apple Silicon laptop, Apple Silicon desktop, external display, built-in display. |
| Camera | FaceTime Camera, iPhone Continuity Camera, USB webcam, Studio Display camera if available. |
| Microphone | Built-in mic, USB mic, Bluetooth/AirPods, iPhone Continuity microphone if available. |
| Screen | Full display, selected window, multiple displays, window close/reopen. |
| Audio | Mic only, system audio only, mic + system audio, muted mic, zero-level source. |
| Runtime | Idle preview, recording, RTMP publish, recording + RTMP, sleep/wake, display change, device unplug/replug. |

## Core Scenarios

1. First launch permission path.
   - Measure time from first launch to ready preview after granting permissions.
   - Count repeated prompts or stale permission states.

2. Screen preview stability.
   - Run 30 minutes with selected display.
   - Run 30 minutes with selected window.
   - Measure black frames, frozen-frame events, capture FPS, memory, CPU, thermal pressure.

3. Camera preview stability.
   - Run 30 minutes per camera device.
   - Measure first-frame time, black frames, device disconnect recovery, CPU/memory.

4. Screen recording with audio.
   - Record 30 minutes of screen + mic.
   - Record 30 minutes of screen + system audio.
   - Record 30 minutes of screen + mic + system audio.
   - Measure A/V drift, dropped frames, file validity, file size, CPU/memory/thermal pressure.

5. Screen + Face compositor once implemented.
   - Record 10, 30, and 60 minute sessions.
   - Verify camera PiP is present in output, not only preview.
   - Measure sync between camera, screen, mic, and system audio.

6. RTMP publish.
   - Publish to a local/test RTMP endpoint for 30 and 60 minutes.
   - Measure connection time, reconnect behavior, dropped frames, bitrate stability, output validity.

7. Recovery tests.
   - Sleep/wake while idle and while active.
   - Disconnect/reconnect camera.
   - Disconnect/reconnect microphone.
   - Change display arrangement.
   - Close selected window.
   - Stop and restart capture repeatedly.

## Metrics

| Metric | Why it matters |
| --- | --- |
| Time to first preview frame | Proves setup and source startup speed. |
| Time to first recorded frame | Proves recording startup. |
| Capture FPS vs target | Shows ScreenCaptureKit/camera health. |
| Dropped frame count | Shows render/encode/backpressure health. |
| Black/frozen preview count | Directly addresses common macOS capture pain. |
| A/V drift at 10/30/60 minutes | Proves audio path reliability. |
| CPU, memory, thermal pressure | Proves local model/director work is not stealing capture budget. |
| Permission prompt recurrence | Proves TCC identity and relaunch behavior. |
| Device reconnect recovery time | Proves native Apple device reliability. |
| RTMP connect/reconnect time | Proves streaming egress readiness. |

## OBS Baseline

Use OBS as the baseline for the same scenarios:

- OBS scenes: screen only, camera only, screen + camera PiP.
- OBS sources: macOS Screen Capture, Video Capture Device, macOS Audio Capture, mic input.
- OBS settings: match output resolution, frame rate, and bitrate as closely as possible.
- Record OBS logs and Stats panel values where available.

Relevant OBS docs and issues:

- [OBS Sources Guide](https://obsproject.com/kb/sources-guide)
- [OBS Audio Mixer Guide](https://obsproject.com/kb/audio-mixer-guide)
- [OBS macOS Screen Capture Source](https://obsproject.com/kb/macos-screen-capture-source)
- [OBS macOS Desktop Audio Capture Guide](https://obsproject.com/kb/macos-desktop-audio-capture-guide)
- [OBS Encoding Performance Troubleshooting](https://obsproject.com/kb/encoding-performance-troubleshooting)
- [OBS Stream Connection Troubleshooting](https://obsproject.com/kb/stream-connection-troubleshooting)
- [obs-studio #8928](https://github.com/obsproject/obs-studio/issues/8928)
- [obs-studio #10668](https://github.com/obsproject/obs-studio/issues/10668)
- [obs-studio #11435](https://github.com/obsproject/obs-studio/issues/11435)
- [obs-studio #12044](https://github.com/obsproject/obs-studio/issues/12044)

## Pass Bar

OpenCue should not claim a Mac-native reliability advantage until it can show:

- 60 minute screen recording with mic and optional system audio without black/frozen output.
- 30 minute composited `Screen + Face` recording with stable sync.
- Clear recovery or explicit failure state after sleep/wake or device loss.
- Lower or comparable CPU/memory/thermal pressure than OBS on the same workflow.
- No repeated permission loops after a grant and relaunch.
