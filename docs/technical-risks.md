# Technical Risks

## Highest Risk

Stable streaming egress is the hardest part of the product. RTMP reconnects, A/V sync, encoder pressure, dropped frames, and stream health need to be proven before visual polish matters.

## Validation Gates

1. Camera + screen preview can run without overheating or UI jank.
2. Mic and system audio stay synced with video.
3. RTMP can hold a long stream.
4. Local recording can run alongside streaming.
5. Source monitoring, preview rendering, and adaptive health sampling do not
   steal resources from capture/encode.
6. AI provider setup/review work stays optional and can be paused or
   deprioritized under stream pressure.

## Streaming Egress Strategy

Full RTMP media egress must have its own capture path rather than depending on local recording. Recording can run alongside a stream, but turning recording off should not stop the publish path from receiving video/audio samples. The recording stream should remain local-only so endpoint validation and recording overlap do not spend work on no-op publisher appends. Shared sources, especially microphone capture, should be reused across stream and recording paths to avoid duplicate device sessions. RTMP sample appends must stay bounded under network or encoder pressure; dropping video samples is safer than building an unbounded async append backlog.

Transient RTMP startup failures should be retried with bounded backoff, but only before the stream is live. Cancelled startup attempts must cancel their in-flight network connection immediately instead of waiting for timeout, and must close any publisher that connects before the cancelled start can register it. Once full media egress is linked, runtime reconnects need separate transport-level health and resubscribe handling.

## Current Signal Strategy

Screen motion detection uses a separate low-resolution, low-FPS ScreenCaptureKit stream and sparse luma sampling. This is intentionally cheaper than running vision models or full-frame analysis in the director loop. The visible display preview and camera preview also follow performance mode caps so Efficiency mode avoids high-cost preview capture. Source toggles should stop disabled preview views, signal monitors, and recording audio tracks, not just hide their values in the UI.

SwiftUI rendering should keep high-frequency signal updates scoped to the preview/director column instead of invalidating the whole studio shell. The inspector should use a lazy stack and mode-aware panel selection so off-screen or irrelevant control panels do less layout work while capture is active. Setup-rule generation is disabled during capture, and the setup assistant is also hidden while streaming, connecting, stopping, recording, or stopping recording so the live side rail does not spend layout or attention on inactive model controls.

Source level controls should stay coarse enough to avoid churn. MacStream normalizes source levels to 1% steps and uses the same step in SwiftUI sliders, so tiny pointer/trackpad deltas do not repeatedly reconfigure the signal provider or media pipeline.

Active capture should not allow the selected scene to lose its required visual source or move to a scene the current media path cannot output. Required camera/screen source toggles and required source level controls are locked while streaming, connecting, recording, or stopping, and required level-controlled sources must be nonzero before real capture starts. The setup recovery action must repair both disabled needed sources and enabled-but-zero needed source levels before capture. Real ScreenCaptureKit publishing now supports Screen and composited Screen + Webcam, while Webcam/BRB remain blocked for full RTMP until the media path has a non-screen video output or slate compositor. Local recording blocks scene switching while the writer is active so the file does not mix incompatible layouts. Optional audio toggles and levels remain available so the operator can still fix sound without forcing a scene mismatch or capture restart.

Director automation must respect the same scene availability gate as manual controls. Suggest/Auto should not display or auto-take normal scene-change cues that are impossible for the active media path; urgent safety cues can remain visible only as current-stream warnings when their target scene is unavailable.

Adaptive performance must react to actual capture health, not only thermal state. Dropped frames or low capture FPS should reduce capture cost while keeping the stream live, then recover after consecutive stable capture-health samples so the app does not oscillate between capture profiles. Capture-cost changes should update active ScreenCaptureKit stream configuration where possible instead of restarting streams, reserving restarts for capture-target/filter changes. Health telemetry must avoid double-counting FPS when recording and publishing run separate ScreenCaptureKit streams.

Screen/window selection must be shared across preview, signal sampling, recording, and publishing. If these paths capture different targets, the director will make decisions from one source while the stream shows another. Capture rescans should stay idle-only because enumerating shareable screen content or changing target metadata during active capture can add avoidable ScreenCaptureKit work and operator confusion.

## Camera And Mic Enhancement Strategy

Camera mirror, rotation, and light tuning belong with the camera source controls because operators may change them while setting up a session. The current camera path uses `AVCaptureVideoPreviewLayer`, so mirror and rotation can stay as local preview transforms. Exposure Boost currently combines a lightweight Core Image preview filter with AVFoundation auto exposure, focus, and white-balance hints. Shipping the same camera look into recording or RTMP output requires the later camera composition path, because the current real media pipeline records and publishes screen capture rather than a composited camera scene.

JoyCast-style mic polish is a useful product reference, but it is not one feature. JoyCast appears as a selectable virtual microphone and promises local noise removal, subtle enhancement, consistent loudness, native 48 kHz audio, and low latency across other apps. MacStream's MVP should first process microphone audio only inside its own recording and RTMP paths. A system-wide virtual microphone requires a separate Core Audio or DriverKit style distribution surface, installer/update handling, and much heavier reliability testing.

MacStream's current microphone path receives `CMSampleBuffer` values from `AVCaptureAudioDataOutput` and appends them directly to the recorder and RTMP publisher. Built-in Smooth Mic should replace that direct append path with an `AVAudioEngine` or Audio Unit graph that can apply voice processing, a dynamics processor or limiter, EQ, and a conservative noise gate before samples reach the writer and publisher. That work should be tested against A/V sync, latency, CPU pressure, and fallback behavior before exposing a main-window Smooth Mic toggle.

## Dependency Strategy

Start dependency-free for the app spine. Add native media and AI dependencies only at boundaries:

- HaishinKit for RTMP/SRT feasibility. It is an explicit opt-in build path via `MAC_STREAM_ENABLE_HAISHINKIT=1` because the package currently resolves additional binary artifacts beyond the RTMP products MacStream needs.
- Foundation Models through Apple's system frameworks when the supported macOS 26 runtime is available.
- OpenAI-compatible providers through plain HTTP so users can bring LM Studio, Ollama, llama.cpp servers, MLX servers, local-network machines, or cloud endpoints without MacStream owning model runtime lifecycle.
- mlx-swift-lm only through the explicit `MAC_STREAM_ENABLE_MLX=1` experimental build path after the provider schema and benchmarking plan are stable.

No Python sidecar in the MVP.

## Local Model Strategy

Provider-first beats managed runtime ownership for the main app. MacStream should first support Foundation Models and OpenAI-compatible providers, then consider MLX only as an optional helper after benchmarks prove cold start, tokens/sec, memory pressure, GPU contention, unload reliability, model footprint, and crash isolation are good enough for a streaming app.

The live director should keep using typed profiles and deterministic thresholds so scene changes do not depend on model latency, token streaming, model downloads, or provider availability.

Setup-rule generation should stay disabled while streaming, connecting, recording, or missing a real stream description so provider work cannot steal CPU, memory bandwidth, GPU time, or thermal headroom from capture. If capture starts while setup generation is already in flight, MacStream cancels the task and surfaces a setup-paused warning instead of waiting for a provider to finish. Setup prompts are trimmed and bounded before reaching either the fallback rule engine or any provider prompt so pasted notes cannot create unexpectedly large requests, and results from stale prompt text are discarded before they can change director rules.

Vision models belong in a separate multimodal adapter, not the hot path. Moondream is a useful local candidate for sampled frames when MacStream needs object detection, visual question answering, screen safety checks, or "where is the user's attention" cues. OpenAI-compatible vision providers can support users who already run local VLM endpoints. Explicit cloud vision can support users who want higher quality or do not have local model headroom, but it must be visible in the UI and disabled by default. Every vision adapter must convert output into bounded typed signals and sample slowly enough that camera/screen preview, recording, and streaming stay ahead of inference.
