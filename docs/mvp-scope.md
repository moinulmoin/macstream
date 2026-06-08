# MVP Scope

## In

- Native macOS SwiftUI app.
- Camera, screen/window, microphone, and system audio source boundaries.
- Capture preflight for camera, microphone, display, window, and permission status.
- Capture rescans are idle-only, so device enumeration and ScreenCaptureKit target refreshes do not run while preview, streaming, or recording is active.
- Selectable display/window screen target shared by preview, motion sampling, recording, and RTMP publish capture.
- Capture preflight repair shortcuts into macOS Privacy & Security settings.
- Live camera preview through AVFoundation.
- Live display preview through ScreenCaptureKit.
- First launch opens on the non-capturing BRB scene so camera/display capture starts only after selecting a source scene.
- Four fixed scenes: Face, Screen + Face, Screen, BRB.
- Manual scene switching.
- RTMP destination model and stream state.
- Local recording boundary.
- Editable RTMP destination and recording controls.
- Recording is explicit by default; automatic record-while-streaming is opt-in for lower first-run load.
- Stream-owned automatic recordings stop with the stream; manually started recordings are preserved when a stream stops.
- Duplicate local recording starts are blocked, and pending recording startup can be cancelled.
- Recording shutdown is idempotent while the media pipeline closes, so repeated stop clicks do not duplicate local archive teardown.
- Stream startup and recording startup do not overlap while either capture setup is still pending.
- Recording failures surface their reason in the inspector.
- Local display recording to a `.mov` file through ScreenCaptureKit and AVAssetWriter, including system audio and best-effort microphone audio.
- RTMP/RTMPS endpoint validation and publisher adapter boundary, with HaishinKit full publishing available only through the explicit `MAC_STREAM_ENABLE_HAISHINKIT=1` build path.
- Endpoint-validation builds label RTMP starts as endpoint checks, not live publishing, so the default dependency-light build cannot be mistaken for a real broadcast path.
- RTMP destination validation blocks predictable malformed input before starting.
- Explicit stream transport status for Preview, endpoint validation, or full RTMP publish.
- Failed stream starts stay non-live and retryable.
- RTMP stream startup retries transient failures with bounded backoff; local preview sessions fail fast.
- Duplicate stream starts, duplicate stream stops, and destination edits are blocked while connecting or stopping, and a pending connection can be cancelled safely.
- Explicit Preview/RTMP destination mode, with a first-run preview session for the stream loop without an RTMP server or artificial startup delay.
- Redacted destination display so stream keys do not leak into timeline/session report events.
- Stream health model: bitrate, dropped frames, capture FPS, audio level, latency, with a media-pipeline telemetry handoff when capture is active.
- System performance pressure model for thermal state, Low Power Mode, and process memory.
- Deterministic director engine with Suggest, Auto, and Paused modes.
- Director sampling loop while the stream is live in Suggest or Auto, with the first live sample running immediately and Paused mode stopping live signal sampling to save capture budget.
- Real signal provider for microphone speech level, active app, user idle time, screen motion, and frozen-screen detection.
- Signal model for face presence and muted mic.
- Local intelligence provider boundary for Foundation Models, OpenAI-compatible local providers, rule fallback, and experimental MLX benchmarking.
- Rule-based setup assistance is the dependable default until provider-first adapters land.
- Future Foundation Models provider for native Apple-local setup/review assistance on supported macOS 26 systems.
- Future OpenAI-compatible provider for LM Studio, Ollama, llama.cpp servers, MLX servers, and other user-owned endpoints.
- Experimental MLX adapter remains opt-in through `MAC_STREAM_ENABLE_MLX=1`; full model loading is not part of the live path.
- Future multimodal adapter boundary for sampled-frame vision, with local or provider-backed VLMs outside the live director hot path.
- Setup-rule generation is limited to pre-capture states and any in-flight setup generation is cancelled when capture starts, so AI provider work does not compete with streaming or recording.
- The setup-rules panel is shown only while capture is idle, keeping live/recording operation focused on controls, health, sources, and timeline.
- Setup assistant applies typed director profiles for coding, demos, teaching, podcasts, and balanced streams.
- Manual and director-assisted clip markers for active capture moments worth reviewing later, with JSON export.
- New capture sessions reset clip markers and export URLs so old stream moments do not leak into current-session reports.
- Session report export with transport, health, signals, source states, selected capture target, a bounded current-session event history, recording path, and clips, excluding RTMP secrets.
- Source toggles and adjustable levels affect preview rendering, media capture, and the director's effective signals. Camera is toggle-only, screen/mic/system-audio expose levels, required scene sources must be enabled and nonzero before real capture starts, the first-run source repair action enables or raises needed sources, and required source levels are locked while capture is active. Disabled camera/screen sources avoid preview capture views, zero-level screen sources stop screen-motion sampling and display-preview capture while idle or optional, disabled microphone/screen sources stop their signal monitors, and disabled or zero-level microphone/system-audio sources are skipped by recording/publishing sample processing.
- First-run capture setup distinguishes first-time permission prompts, denied/unknown camera or microphone permissions that need System Settings, restart-scoped Screen Recording access, and missing required devices.
- RTMP destination persistence failures surface as operator-visible events instead of silently losing the configured endpoint.
- Cue timing uses the settings countdown in Suggest and Auto modes; Auto still leaves a hold window before non-safety scene changes.
- Live controls include performance modes, including Adaptive mode that tunes director cadence, screen-motion sampling, display and camera preview capture, and active ScreenCaptureKit preview, motion, recording, and publishing stream configuration from system pressure and runtime capture health.
- Adaptive runtime health monitoring continues while the director is paused during a live stream and while local recording is running without a live stream.
- The MVP uses a single main studio window so duplicate windows do not create duplicate preview and capture stacks.
- Local recording supports Screen and composited Screen + Face output. The HaishinKit RTMP publish path now uses the same compositor for Screen + Face, while the default dependency-light build stays honest as endpoint validation only.
- Runtime capture pressure from dropped frames or low capture FPS degrades the running stream, lowers Adaptive mode to Efficiency, and recovers when capture health stabilizes. System pressure from thermal state, Low Power Mode, or high MacStream memory use also lowers Adaptive mode to Efficiency with the matching reason shown in the inspector.

## Out

- General OBS plugin compatibility.
- Advanced overlays.
- Multi-platform support.
- Cloud-first AI.
- Managed MLX model loading or generation in the hot path.
- Direct VLM calls from live scene switching.
- Model-controlled live scene switching.
- Hand-rolled RTMP egress before proving whether HaishinKit fits.

## MVP Success

MacStream should be able to prove the core product loop before advanced AI or the expensive media stack is complete:

- launch as a packaged macOS 26 app with the final bundle identifier,
- guide Camera, Microphone, and Screen Recording permission recovery,
- select one display/window target shared by preview, motion sampling, recording, and publishing,
- preview the four fixed scenes,
- record `Screen` and composited `Screen + Face` `.mov` files that play back correctly,
- start a Preview session and, in default builds, label RTMP attempts as endpoint checks rather than real publishing,
- sample director signals,
- receive a cue with a reason,
- accept or hold the cue,
- see stream health, source state, and adaptive pressure state.
