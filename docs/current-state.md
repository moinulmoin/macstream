# Current State And Next Build Plan

## Decision

The project is now MacStream. The working product direction is a macOS 26-only native streaming studio for solo screen + camera creators.

The build strategy is core-first:

1. make capture, recording, preview, streaming state, permissions, packaging, and release QA boring;
2. then add provider-first AI where it improves real user workflows;
3. keep every live scene decision deterministic.

## What Exists

- SwiftPM package renamed to `MacStream` with `MacStreamCore` as the core library.
- Single macOS studio window.
- Fixed scenes: Face, Screen + Face, Screen, BRB.
- AVFoundation camera preview.
- ScreenCaptureKit display/window preview.
- Capture preflight for camera, microphone, display/window, and permission state.
- Idle-only capture rescans so device enumeration does not fight active capture.
- Source toggles and levels wired through preview, capture, and signals.
- Local Screen recording.
- Local composited Screen + Face recording.
- Preview stream mode and RTMP endpoint-validation mode.
- Optional HaishinKit build path for full RTMP Screen and composited Screen + Face publish experiments.
- Deterministic director engine with Suggest, Auto, and Paused modes.
- Adaptive performance pressure handling from system state and capture health.
- Clip markers and session report export with RTMP secrets redacted.
- Local setup-rule seam with a rules fallback and an experimental MLX adapter shell.

## What Is Not Solid Enough Yet

- Full RTMP publish now routes `Screen + Face` through the compositor, but it is not yet the same proven quality bar as local recording.
- Real RTMP publish still needs live QA with `MAC_STREAM_ENABLE_HAISHINKIT=1`, including remote PiP verification, A/V sync, bitrate stability, reconnect behavior, and long-session health.
- Recording output still needs repeated playback/AV sync verification across long sessions.
- Fresh-Mac permission/TCC flow needs QA with the packaged app and final bundle identifier.
- Developer ID signing, notarization, stapling, and Gatekeeper launch need release-run proof.
- Provider-first AI adapters are not implemented yet; current app runtime uses rules by default.

## Core Build Priorities

1. Prove packaged app launch and permission recovery on macOS 26.
2. Prove local Screen and Screen + Face recording outputs with audio and no black/frozen frames.
3. Prove HaishinKit RTMP Screen and composited Screen + Face outputs against a real ingest endpoint.
4. Prove preview, recording, and streaming state transitions cannot overlap or get stuck.
5. Keep adaptive mode tied to real capture pressure, not cosmetic status.
6. Split high-risk media/store/release tests as implementation grows so source-text guardrails do not become the only safety net.

## AI Build Priorities

1. Add `OpenAICompatibleLocalIntelligenceProvider` for LM Studio, Ollama, llama.cpp, MLX server, and other user-owned endpoints.
2. Add Foundation Models provider for macOS 26 Apple Intelligence systems.
3. Add provider settings: base URL, model, optional API key, timeout, and capability probe.
4. Add JSON setup-plan smoke test and visible provider fallback.
5. Keep setup generation disabled during streaming, connecting, recording, or stopping.
6. Only revisit managed MLX after benchmarking cold start, tokens/sec, memory pressure, GPU contention, unload reliability, model footprint, and crash isolation.

## AI User Scenarios Worth Building

- Setup assistant: convert “I’m teaching SwiftUI with screen and camera” into a typed director profile.
- Preflight coach: explain missing permissions, muted mic, zero-level sources, wrong capture target, or missing destination.
- Director explanation: explain why a cue appeared using local signals and stream health.
- Clip review: title clip markers and summarize why they were interesting.
- Session report: summarize health drops, scene changes, frozen-screen warnings, and capture pressure after a session.
- Slow sampled-frame analysis: optional VLM review for screen safety or attention cues, converted into bounded typed signals outside the live hot path.

## Non-Negotiables

- No model-controlled live scene switching.
- No direct VLM calls from the live director loop.
- No AI work competing with capture/encode while live.
- No claim of full Screen + Face RTMP streaming until the publish path uses composition.
- No managed MLX runtime in the app until benchmarks prove it is worth owning.
