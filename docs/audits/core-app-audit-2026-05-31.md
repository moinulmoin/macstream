# Core App Audit - 2026-05-31

## Scope

This audit checks MacStream against real creator workflows before adding more AI features. It combines repository review, current OBS research, and read-only subagent review. The key standard is simple: can a solo Mac creator reliably preview, record, or stream the scene they think they are sending?

## Product Truth

MacStream has a solid native app spine:

- SwiftPM package with `MacStream` app and `MacStreamCore` library targets.
- Fixed V1 scenes: `Face`, `Screen + Face`, `Screen`, and `BRB`.
- Native camera preview through AVFoundation.
- Native screen/window preview and local screen recording through ScreenCaptureKit.
- Source readiness, first-run setup, relaunch-scoped Screen Recording handling, and stable bundle identity for TCC.
- Local `.mov` recording for screen output with system audio and best-effort microphone audio.
- Default RTMP endpoint validation and optional HaishinKit full RTMP build path.
- Deterministic director rules, adaptive performance, clip markers, session reports, and signed/notarized release automation.

The central product gap at the time of this audit was also clear:

- The real media output was screen-only.
- `Screen + Face` was available in preview and director planning, but local recording and full RTMP publishing blocked it until camera/screen composition existed.
- `Face` and `BRB` were not real media output scenes yet for recording/publishing.

Status update: MacStream now has local `Screen + Face` recording composition and the HaishinKit RTMP path uses the same Screen + Face compositor. The remaining proof is live-ingest QA, long-session A/V sync, and non-screen output support for Face/BRB.

## User Scene Audit

| User scene | Current fit | Main blockers | Next proof |
| --- | --- | --- | --- |
| Solo product demo / screen + face | Preview, local recording, and HaishinKit RTMP can use screen with camera PiP. | Long-run composed recording and live RTMP remote-output QA still need proof. | Run 30-60 minute `Screen + Face` local and RTMP sessions with camera PiP, mic, optional system audio, no drift. |
| Coding/tutorial stream | Screen target, screen motion, coding profile, and screen recording exist. | No zoom/annotation path, no explicit camera/mic source selection, long-session sync not proven. | 30 minute coding recording with selected app/window, mic sync, no black frames, stable FPS. |
| Remote workshop/class | Teaching profile exists and first-run setup can guide capture readiness. | `Face` is preview-only for real output. Guest/remote-participant source should stay out of V1. | Workshop recording and RTMP test using screen + face compositor, pause/BRB safety, clear recovery if screen capture freezes. |
| Founder/webinar/podcast | Face preview and podcast-style profile exist. | Face cannot be recorded/published as real media output yet. Smooth Mic is not implemented in the media path. | 20 minute face-first local recording with mic processing disabled/enabled comparison once audio graph exists. |
| Local clip recording | Local screen recording, Screen + Face recording, clip markers, and session report export exist. | No in-app playback/trim/export workflow. | Mark clips during recording and export report that links to playable media and marker timestamps. |

## Codebase Findings

### P0: Real Composited Streaming Is Missing

`PreviewCanvasView` visually composes camera over screen. `SystemMediaPipeline` now records local `Screen + Face` output through a pixel-buffer compositor, while RTMP publishing still uses the raw ScreenCaptureKit path. `StudioStore` still blocks real `Screen + Face` streaming instead of silently lying to the user.

Relevant files:

- `Sources/MacStream/Views/PreviewCanvasView.swift`
- `Sources/MacStreamCore/Services/MediaPipeline.swift`
- `Sources/MacStreamCore/Stores/StudioStore.swift`
- `docs/mvp-scope.md`
- `docs/technical-risks.md`

Decision: keep compositor work ahead of AI polish. Local recording now has the first compositor pass; next, wire the same composed frames into RTMP.

### P0: RTMP Is Not Proven In The Default Build

The default app validates RTMP reachability. Full media publish requires `MAC_STREAM_ENABLE_HAISHINKIT=1`, and that path still needs real long-run validation.

Relevant files:

- `Package.swift`
- `Sources/MacStreamCore/Services/MediaPipeline.swift`
- `.github/workflows/ci.yml`
- `.github/workflows/release.yml`

Decision: keep endpoint validation language honest, but promote one real RTMP media path after screen recording is stable.

### P0: Device Selection Is Too Shallow

Capture preflight lists camera and microphone devices, but the actual preview/media paths mostly use default devices. Real creators need to pick an iPhone Continuity Camera, external webcam, USB mic, or built-in mic and know that preview, recording, publishing, and signal sampling use the same selection.

Relevant files:

- `Sources/MacStreamCore/Services/CaptureDeviceProvider.swift`
- `Sources/MacStream/NativePreview/CameraPreviewView.swift`
- `Sources/MacStreamCore/Services/MediaPipeline.swift`
- `Sources/MacStreamCore/Services/SignalProvider.swift`

Decision: explicit source device selection should land before Smooth Mic or vision models.

### P0: Long-Run Capture Health Is Not Proven

The architecture already models dropped frames, capture FPS, thermal pressure, memory pressure, and adaptive capture settings. The remaining gap is benchmark evidence, especially for ScreenCaptureKit freeze/restart behavior, A/V sync, sleep/wake, display changes, and system audio.

Relevant files:

- `Sources/MacStreamCore/Services/SystemPerformanceMonitor.swift`
- `Sources/MacStreamCore/Services/MediaPipeline.swift`
- `Sources/MacStreamCore/Services/SignalProvider.swift`
- `Sources/MacStream/NativePreview/ScreenCapturePreviewView.swift`

Decision: create repeatable benchmark artifacts before claiming OBS reliability advantages.

### P1: Test Coverage Is Broad But Too Centralized

The test suite covers many core behaviors, including permissions, setup, source gating, RTMP validation/retry, adaptive performance, recording ownership, exports, and release scripts. The risk is maintainability: most coverage is concentrated in `Tests/MacStreamCoreTests/DirectorEngineTests.swift`, with many source-text assertions that protect architecture but can become brittle during refactors.

Decision: keep current tests, but split future media/store/release tests into focused files as implementation grows.

### P1: Clip Workflow Is Only Export-Oriented

Clip markers and session reports exist, but local clip recording is not yet a creator workflow. Users still need playback, marker timestamps tied to the media file, trim/export, and failure-safe file handling.

Relevant files:

- `Sources/MacStreamCore/Services/ClipMarkerExporter.swift`
- `Sources/MacStreamCore/Services/SessionReportExporter.swift`
- `Sources/MacStream/Views/EventLogView.swift`

Decision: after compositor and recording stability, make clips reviewable inside the app.

### P2: AI Boundaries Are Correct

The current local intelligence plan is sane. MLX is setup-time only, falls back honestly when not linked, and does not enter the live director hot path. Vision models are documented as a later adapter producing typed signals.

Relevant files:

- `Sources/MacStreamCore/Services/LocalIntelligenceProvider.swift`
- `Sources/MacStreamCore/Services/DirectorEngine.swift`
- `docs/technical-risks.md`

Decision: keep AI out of frame-by-frame switching. Use it for setup, summaries, post-session help, and later slow sampled-frame signals.

## OBS Research Context

OBS's core model is scenes, sources, source ordering, audio mixer, recording/streaming controls, hotkeys, and performance troubleshooting. Official OBS docs call scenes and sources the core setup surface, list screen/window/app/camera/audio source types, and treat audio meters/mute/monitoring as central operating controls:

- [OBS Sources Guide](https://obsproject.com/kb/sources-guide)
- [OBS Audio Mixer Guide](https://obsproject.com/kb/audio-mixer-guide)
- [OBS macOS Screen Capture Source](https://obsproject.com/kb/macos-screen-capture-source)
- [OBS macOS Desktop Audio Capture Guide](https://obsproject.com/kb/macos-desktop-audio-capture-guide)

The macOS reliability wedge is real but must be proven. Public OBS issues show user pain around ScreenCaptureKit freezes, black preview/audio despite permissions, wake-from-sleep capture freezes, and macOS 15.4 preview/system-audio freezes:

- [obs-studio #8928: macOS Screen Capture stops working after waking from sleep](https://github.com/obsproject/obs-studio/issues/8928)
- [obs-studio #10668: macOS screen capture and audio capture not working anymore](https://github.com/obsproject/obs-studio/issues/10668)
- [obs-studio #11435: macOS screen capture freezes randomly](https://github.com/obsproject/obs-studio/issues/11435)
- [obs-studio #12044: macOS 15.4 preview freezes and system audio stops](https://github.com/obsproject/obs-studio/issues/12044)

MacStream should not claim superiority until the benchmark plan produces comparable data.

## Recommended Build Order

1. Prove local and RTMP `Screen + Face` composition under long-session capture pressure.
2. Add explicit camera and microphone device selection.
3. Long-run local recording QA with screen, camera, mic, and optional system audio.
4. Real RTMP media publish QA against live ingest, including remote PiP verification and reconnect behavior.
5. OBS-vs-MacStream benchmark reports on the same Macs and devices.
6. Clip review workflow.
7. Smooth Mic inside MacStream's own media path.
8. AI setup and post-session improvements.

The next code sprint should start at item 1, not UI polish.
