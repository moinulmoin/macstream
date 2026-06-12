# Plan 002: Surface recording failures and degraded audio instead of silently producing broken files

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 03ae477..HEAD -- Sources/MacStreamCore/Services/MediaPipeline.swift Sources/MacStreamCore/Stores/StudioStore.swift Sources/MacStream/NativePreview/CameraPreviewView.swift Sources/MacStream/Views/PreviewCanvasView.swift Sources/MacStream/Views/StudioView.swift Tests/MacStreamCoreTests/TestSupport.swift Tests/MacStreamCoreTests/StreamLifecycleTests.swift Tests/MacStreamCoreTests/MediaPipelinePolicyTests.swift plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/001-split-test-monolith.md
- **Category**: bug
- **Planned at**: commit `03ae477`, 2026-06-11

## Why this matters

Local recording can currently fail or lose requested audio while the UI keeps reporting success. A failed `AVAssetWriterInput.append` moves the writer toward `.failed`; later callbacks are skipped and `stopRecording()` still reports "Local archive closed." The result is a corrupt, truncated, or silent `.mov` with no warning event. This plan makes recorder integrity observable at the pipeline boundary, propagates that failure to `StudioStore.recordingState`, and surfaces camera-preview setup failures instead of leaving a black preview with no retry.

## Current state

- `Sources/MacStreamCore/Services/MediaPipeline.swift` — owns capture, recording, writer inputs, and the `MediaPipeline` protocol.
- `Sources/MacStreamCore/Stores/StudioStore.swift` — `@MainActor @Observable` single source of truth for stream/recording state and event logging.
- `Sources/MacStream/NativePreview/CameraPreviewView.swift` — app-target native camera preview wrapper.
- `Sources/MacStream/Views/PreviewCanvasView.swift` — constructs `CameraPreviewView` inside the preview canvas.
- `Sources/MacStream/Views/StudioView.swift` — top-level studio layout; `PreviewColumnView` wires store state into the preview canvas.
- `Tests/MacStreamCoreTests/TestSupport.swift` — post-Plan-001 shared fakes; contains `ConfigurableMediaPipeline`, `FixedSignalProvider`, and `SpyMediaPipeline` as internal helpers.
- `Tests/MacStreamCoreTests/StreamLifecycleTests.swift` — post-Plan-001 home for recording/stream lifecycle store tests.
- `Tests/MacStreamCoreTests/MediaPipelinePolicyTests.swift` — post-Plan-001 home for `SystemMediaPipeline` static policy/helper tests.

`MediaPipeline` has no recorder-failure or setup-warning surface today, but it already has a default-extension pattern that keeps conformers compiling:

```swift
// Sources/MacStreamCore/Services/MediaPipeline.swift:14-28
public protocol MediaPipeline: Sendable {
    var streamTransport: StreamTransportKind { get }
    var currentHealth: StreamHealth? { get }
    var requiresCaptureReadinessForStart: Bool { get }
    var requiresScreenCaptureVideoForStream: Bool { get }
    var requiresScreenCaptureVideoForRecording: Bool { get }
    var supportedSceneKindsForStream: Set<SceneKind> { get }
    var supportedSceneKindsForRecording: Set<SceneKind> { get }

    func update(configuration: MediaPipelineConfiguration)
    func startStream(destination: StreamDestination) async throws
    func stopStream() async
    func startRecording() async throws -> URL
    func stopRecording() async
}

// Sources/MacStreamCore/Services/MediaPipeline.swift:30-37
public extension MediaPipeline {
    var streamTransport: StreamTransportKind { .endpointValidation }
    var currentHealth: StreamHealth? { nil }
    var requiresCaptureReadinessForStart: Bool { false }
    var requiresScreenCaptureVideoForStream: Bool { false }
    var requiresScreenCaptureVideoForRecording: Bool { false }
    var supportedSceneKindsForStream: Set<SceneKind> { Set(SceneKind.allCases) }
    var supportedSceneKindsForRecording: Set<SceneKind> { Set(SceneKind.allCases) }
```

`SystemMediaPipeline` state is queue-guarded. Add new recorder-integrity fields beside the existing writer/input fields:

```swift
// Sources/MacStreamCore/Services/MediaPipeline.swift:373-407
public final class SystemMediaPipeline: NSObject, MediaPipeline, SCStreamOutput, AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.macstream.media.recording", qos: .userInitiated)
    private let rtmpPublisherFactory: @Sendable (RTMPPublishTarget) -> any RTMPPublisher
    private var mediaConfiguration = MediaPipelineConfiguration()
    private var stream: SCStream?
    private var publishingStream: SCStream?
    private var recordingCaptureGeometry: MediaCaptureGeometry?
    ...
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var videoPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var audioInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?
    ...
    private var mediaHealth = StreamHealth()
    private var frameWindowStartedAt = Date()
    private var frameWindowCount = 0
}
```

Requested audio can be silently omitted during `startRecording()`: system audio `canAdd` failure is ignored, microphone capture absence is accepted, microphone `canAdd` failure is ignored, and `SCStream.addStreamOutput(.audio)` errors are swallowed:

```swift
// Sources/MacStreamCore/Services/MediaPipeline.swift:651-668
let audioInput: AVAssetWriterInput?
if mediaConfiguration.capturesSystemAudio {
    let input = AVAssetWriterInput(...)
    input.expectsMediaDataInRealTime = true
    if writer.canAdd(input) {
        writer.add(input)
        audioInput = input
    } else {
        audioInput = nil
    }
} else {
    audioInput = nil
}

// Sources/MacStreamCore/Services/MediaPipeline.swift:676-700
let usesPublishingMicrophoneSession = mediaConfiguration.capturesMicrophone && publishingMicrophoneCapture != nil
let microphoneCapture = usesPublishingMicrophoneSession
    ? nil
    : (mediaConfiguration.capturesMicrophone ? await makeMicrophoneCaptureIfAvailable(deviceID: mediaConfiguration.microphoneDeviceID) : nil)
let hasMicrophoneCapture = usesPublishingMicrophoneSession || microphoneCapture != nil
...
if writer.canAdd(input) {
    writer.add(input)
    microphoneInput = input
} else {
    microphoneInput = nil
}

// Sources/MacStreamCore/Services/MediaPipeline.swift:725-729
let stream = SCStream(filter: selection.filter, configuration: configuration, delegate: nil)
try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
if mediaConfiguration.capturesSystemAudio {
    try? stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
}
```

`stopRecording()` tears down the writer and never inspects `writer.error` or the finish outcome. The existing static-policy convention to match is `shouldCancelWriterOnStop`:

```swift
// Sources/MacStreamCore/Services/MediaPipeline.swift:774-849
public func stopRecording() async {
    let state = queue.sync {
        let stream = stream
        ...
        let writer = writer
        ...
        self.writer = nil
        ...
        return RecordingWriterState(...)
    }

    try? await state.stream?.stopCapture()

    await withCheckedContinuation { continuation in
        ...
        guard let writer = state.writer else {
            continuation.resume()
            return
        }

        if writer.status == .writing {
            writer.finishWriting {
                continuation.resume()
            }
            return
        }

        if Self.shouldCancelWriterOnStop(status: writer.status) {
            writer.cancelWriting()
        }

        continuation.resume()
    }
}

// Sources/MacStreamCore/Services/MediaPipeline.swift:851-853
static func shouldCancelWriterOnStop(status: AVAssetWriter.Status) -> Bool {
    status == .unknown
}
```

Append failures are ignored. The composited video path already treats a false append as a dropped frame; the direct video, system-audio, and microphone paths do not:

```swift
// Sources/MacStreamCore/Services/MediaPipeline.swift:1312-1321
guard Self.shouldProcessRecordingStreamSample(
          isRecordingStream: self.stream === stream,
          hasWriter: writer != nil
      ),
      let writer,
      writer.status != .failed,
      writer.status != .cancelled
else {
    return
}

// Sources/MacStreamCore/Services/MediaPipeline.swift:1343-1360
if mediaConfiguration.sceneKind == .screenAndFace {
    guard appendCompositedVideoSample(sampleBuffer, presentationTime: presentationTime) else {
        recordDroppedFrameIfNeeded(outputType)
        return
    }
    return
}
videoInput.append(sampleBuffer)
...
audioInput.append(sampleBuffer)

// Sources/MacStreamCore/Services/MediaPipeline.swift:1540-1543
private func recordDroppedFrameIfNeeded(_ outputType: SCStreamOutputType) {
    guard outputType == .screen else { return }
    mediaHealth.droppedFrames += 1
}

// Sources/MacStreamCore/Services/MediaPipeline.swift:1764-1771
guard let writer,
      let microphoneInput,
      didStartSession,
      writer.status == .writing,
      microphoneInput.isReadyForMoreMediaData
else { return }

microphoneInput.append(sampleBuffer)
```

`StudioStore` already has `RecordingState.failed(String)`:

```swift
// Sources/MacStreamCore/Models/StudioModels.swift:217-237
public enum RecordingState: Equatable, Sendable {
    case stopped
    case starting
    case recording
    case failed(String)

    public var detail: String {
        switch self {
        case .stopped: "Ready"
        case .starting: "Preparing local file"
        case .recording: "Writing local archive"
        case let .failed(reason): reason
        }
    }
}
```

Recording start sets `.recording`, but does not surface degraded capture setup. Stop always sets `.stopped` and always logs success:

```swift
// Sources/MacStreamCore/Stores/StudioStore.swift:856-873
recordingStartTask = Task {
    do {
        let url = try await mediaPipeline.startRecording()
        ...
        recordingState = .recording
        beginCaptureSession(...)
        health = mediaPipeline.currentHealth ?? health
        addEvent(kind: .stream, title: "Recording", detail: url.lastPathComponent)
        syncMediaHealthLoop()
    } catch {
```

```swift
// Sources/MacStreamCore/Stores/StudioStore.swift:889-905
public func stopRecording() {
    guard canStopRecording else { return }
    recordingStartTask?.cancel()
    ...
    isRecordingStopping = true
    Task {
        await mediaPipeline.stopRecording()
        isRecordingStopping = false
        recordingState = .stopped
        if !streamState.isLive {
            resetCaptureHealthPressure()
        }
        syncMediaHealthLoop()
        addEvent(kind: .stream, title: "Recording stopped", detail: "Local archive closed.")
        endCaptureSessionIfIdle()
    }
}
```

The `canStopRecording` guard currently allows the stop flow when recording is active or starting, unless a stop is already in flight:

```swift
// Sources/MacStreamCore/Stores/StudioStore.swift:191-201
public var canStartRecording: Bool {
    recordingState != .recording
        && recordingState != .starting
        && !isRecordingStopping
        && !isStreamConnecting
        && !isStreamStopping
        && recordingStartBlockedReason == nil
}

public var canStopRecording: Bool {
    (recordingState == .recording || recordingState == .starting) && !isRecordingStopping
}
```

The media-health loop already ticks while recording-only capture is active, and event deduplication already exists:

```swift
// Sources/MacStreamCore/Stores/StudioStore.swift:1402-1405
private var shouldRunMediaHealthLoop: Bool {
    (streamState.isLive && directorMode == .paused)
        || (recordingState == .recording && !streamState.isLive)
}

// Sources/MacStreamCore/Stores/StudioStore.swift:1439-1447
private func advanceMediaHealthIfNeeded() {
    guard shouldRunMediaHealthLoop else {
        stopMediaHealthLoopIfNeeded()
        return
    }

    sampleSystemPressure()
    refreshStreamHealth()
}

// Sources/MacStreamCore/Stores/StudioStore.swift:1449-1464
private func addEvent(kind: StudioEventKind, title: String, detail: String) {
    events.insert(StudioEvent(kind: kind, title: title, detail: detail), at: 0)
    ...
}

private func addWarningEventIfNeeded(title: String, detail: String) {
    guard events.first?.kind != .warning
        || events.first?.title != title
        || events.first?.detail != detail
    else {
        return
    }
```

`CameraPreviewView` has no failure callback, and `update()` returns immediately when a previous setup failed before `isConfigured` became true:

```swift
// Sources/MacStream/NativePreview/CameraPreviewView.swift:7-13
struct CameraPreviewView: NSViewRepresentable {
    var configuration = PreviewCaptureConfiguration()
    var cameraEnhancements = CameraEnhancementSettings()
    var cameraDeviceID: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(configuration: configuration, cameraEnhancements: cameraEnhancements, cameraDeviceID: cameraDeviceID)
    }
```

```swift
// Sources/MacStream/NativePreview/CameraPreviewView.swift:70-110
func update(configuration: PreviewCaptureConfiguration, cameraEnhancements: CameraEnhancementSettings, cameraDeviceID: String?) {
    let preset = Self.sessionPreset(for: configuration)
    let framesPerSecond = Self.frameRateLimit(for: configuration)

    queue.async { [weak self] in
        ...
        guard shouldUpdateSession || shouldUpdateCameraTuning || shouldSwitchDevice else { return }
        ...
        guard self.isConfigured else { return }
        ...
        if self.wantsRunning, !self.session.isRunning {
            self.session.startRunning()
        }
    }
}
```

Initial and reconfiguration failures are silent, and `session.startRunning()` can still run with no input:

```swift
// Sources/MacStream/NativePreview/CameraPreviewView.swift:123-150
private func configureAndStart() {
    queue.async { [weak self] in
        guard let self else { return }
        guard self.wantsRunning else { return }

        if !self.isConfigured {
            self.session.beginConfiguration()
            self.applyRequestedPreset()
            defer { self.session.commitConfiguration() }

            guard let device = Self.resolveDevice(matching: self.requestedDeviceID),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input)
            else {
                return
            }
            ...
            self.isConfigured = true
        }

        if self.wantsRunning, !self.session.isRunning {
            self.session.startRunning()
        }
    }
}

// Sources/MacStream/NativePreview/CameraPreviewView.swift:153-165
private func reconfigureInput() {
    session.beginConfiguration()
    defer { session.commitConfiguration() }
    for input in session.inputs {
        session.removeInput(input)
    }
    guard let device = Self.resolveDevice(matching: requestedDeviceID),
          let input = try? AVCaptureDeviceInput(device: device),
          session.canAddInput(input)
    else {
        videoDevice = nil
        return
    }
```

`PreviewCanvasView` currently has no preview-failure passthrough:

```swift
// Sources/MacStream/Views/PreviewCanvasView.swift:4-15
struct PreviewCanvasView: View {
    var scene: StudioScene
    var signals: SignalSnapshot
    var previewConfiguration = PreviewCaptureConfiguration()
    var cameraEnhancements = CameraEnhancementSettings()
    var cameraDeviceID: String?
    var isCameraEnabled = true
    var isCameraCaptureReady = true
    var isScreenEnabled = true
    var screenLevel = 1.0
    var isScreenCaptureReady = true
    var screenCaptureTarget: ScreenCaptureTarget?
```

```swift
// Sources/MacStream/Views/PreviewCanvasView.swift:128-139
private var cameraFill: some View {
    Group {
        if !isCameraEnabled {
            disabledSourceLayer(.camera)
        } else if !isCameraCaptureReady {
            cameraCaptureUnavailableLayer
        } else {
            CameraPreviewView(
                configuration: previewConfiguration,
                cameraEnhancements: cameraEnhancements,
                cameraDeviceID: cameraDeviceID
            )
```

`PreviewColumnView` constructs the canvas and has direct access to `store`:

```swift
// Sources/MacStream/Views/StudioView.swift:53-73
private struct PreviewColumnView: View {
    var store: StudioStore

    var body: some View {
        VStack(spacing: 14) {
            SessionStatusStripView(store: store)

            ZStack(alignment: .topTrailing) {
                PreviewCanvasView(
                    scene: store.selectedScene,
                    signals: store.latestSignals,
                    previewConfiguration: previewConfiguration,
                    cameraEnhancements: store.preferences.cameraEnhancements,
                    cameraDeviceID: store.selectedCameraDeviceID,
                    isCameraEnabled: store.isSourceEnabled(.camera),
                    isCameraCaptureReady: store.captureReport.hasGrantedPermission(for: .camera),
                    isScreenEnabled: store.isSourceEnabled(.screen),
                    screenLevel: store.sourceLevel(.screen),
                    isScreenCaptureReady: store.captureReport.isScreenCapturePermissionGranted,
                    screenCaptureTarget: store.selectedScreenCaptureTarget
                )
```

Test convention after Plan 001: Swift Testing top-level tests remain `@Test` functions. The store-test pattern to copy lives at original line 3804 before Plan 001 moves it to `Tests/MacStreamCoreTests/StreamLifecycleTests.swift`:

```swift
// Tests/MacStreamCoreTests/DirectorEngineTests.swift:3802-3825 at 03ae477
@Test
@MainActor
func recordingOnlySamplesCaptureHealthWithoutDirectorLoop() async {
    let pipeline = ConfigurableMediaPipeline()
    pipeline.currentHealth = StreamHealth(
        bitrateKbps: 0,
        droppedFrames: 4,
        captureFPS: 30,
        audioLevel: 0.2,
        roundTripMs: 0
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        preferences: StudioPreferences(performanceMode: .adaptive)
    )

    store.startRecording()
    try? await Task.sleep(for: .milliseconds(80))

    #expect(store.recordingState == .recording)
    #expect(store.streamState == .offline)
    #expect(store.effectivePerformanceMode == .efficiency)
    #expect(pipeline.lastConfiguration == expectedMediaConfiguration(.efficiency))
    #expect(store.events.contains { $0.title == "Capture health" })
}
```

The shared fake to extend after Plan 001 is `ConfigurableMediaPipeline` from original lines 5486-5512:

```swift
// Tests/MacStreamCoreTests/DirectorEngineTests.swift:5486-5512 at 03ae477
private final class ConfigurableMediaPipeline: MediaPipeline, @unchecked Sendable {
    let streamTransport: StreamTransportKind
    var currentHealth: StreamHealth?
    var lastConfiguration: MediaPipelineConfiguration?
    var configurationAtStartStream: MediaPipelineConfiguration?
    var updateCount = 0

    init(streamTransport: StreamTransportKind = .endpointValidation) {
        self.streamTransport = streamTransport
    }

    func update(configuration: MediaPipelineConfiguration) {
        updateCount += 1
        lastConfiguration = configuration
    }

    func startStream(destination: StreamDestination) async throws {
        configurationAtStartStream = lastConfiguration
    }

    func stopStream() async {}

    func startRecording() async throws -> URL {
        URL(fileURLWithPath: "/tmp/macstream-configurable.mov")
    }

    func stopRecording() async {}
}
```

Repo conventions and invariants for this plan:

- macOS 26-only SwiftPM app, Swift 6 strict concurrency, SwiftUI.
- Tests use Swift Testing (`@Test` and `#expect`), not XCTest.
- `StudioStore` is `@MainActor @Observable` and is the single source of truth.
- Keep the live sample-buffer hot path free of per-frame allocations and main-actor hops. Build failure strings only when an append actually fails, not for every sample.
- No model output drives live scene switching.
- Stream keys/secrets stay in Keychain and redacted everywhere; do not log secret values.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift check | `git diff --stat 03ae477..HEAD -- Sources/MacStreamCore/Services/MediaPipeline.swift Sources/MacStreamCore/Stores/StudioStore.swift Sources/MacStream/NativePreview/CameraPreviewView.swift Sources/MacStream/Views/PreviewCanvasView.swift Sources/MacStream/Views/StudioView.swift Tests/MacStreamCoreTests/TestSupport.swift Tests/MacStreamCoreTests/StreamLifecycleTests.swift Tests/MacStreamCoreTests/MediaPipelinePolicyTests.swift plans/README.md` | no output; if output exists, compare excerpts before editing |
| Build | `swift build` | exit 0, `Build complete!` |
| Tests | `swift test` (from repo root) | exit 0; final line contains `Test run with 238 tests in 0 suites passed` |
| New store test count | `grep -c 'recording.*Failure\|captureSetupWarnings\|Recording.*failed\|stream.*recording.*failed' Tests/MacStreamCoreTests/StreamLifecycleTests.swift` | at least `4` matches for the new store coverage |
| Helper test exists | `grep -c 'writerFailureDetail' Tests/MacStreamCoreTests/MediaPipelinePolicyTests.swift` | at least `1` |
| Removed silent audio swallow | `grep -c 'try? stream.addStreamOutput(self, type: .audio' Sources/MacStreamCore/Services/MediaPipeline.swift` | `0` |
| Status scope | `git status --short` | only in-scope files are modified |

## Scope

**In scope** (the only files you should modify):

- `Sources/MacStreamCore/Services/MediaPipeline.swift`
- `Sources/MacStreamCore/Stores/StudioStore.swift`
- `Sources/MacStream/NativePreview/CameraPreviewView.swift`
- `Sources/MacStream/Views/PreviewCanvasView.swift`
- `Sources/MacStream/Views/StudioView.swift`
- `Tests/MacStreamCoreTests/TestSupport.swift`
- `Tests/MacStreamCoreTests/StreamLifecycleTests.swift`
- `Tests/MacStreamCoreTests/MediaPipelinePolicyTests.swift`
- `plans/README.md` (status row only)

**Out of scope** (do NOT touch):

- `Sources/MacStreamCore/Models/StudioModels.swift` — `RecordingState.failed(String)` already exists.
- Publish transport behavior and RTMP publisher code — this plan only observes recording writer failures; do not alter stream publishing semantics.
- Keychain, destination, and stream-secret code — no credential behavior is part of this fix.
- Test split/move work from Plan 001 — this plan assumes Plan 001 already produced the post-001 test layout.
- Adding broad camera-permission UX, alerts, or settings deep links — only add the failure callback and retry path described here.
- Creating compatibility shims or deprecated API aliases — clean cutover only.

## Git workflow

- Commit directly on `main` (repo convention — no PRs unless asked).
- Message style follows conventional prefixes used in this repo, e.g. `fix: surface recording writer failures`.
- Do NOT push unless the operator explicitly instructed it.

## Steps

### Step 1: Add defaulted recorder-integrity surfaces to `MediaPipeline`

Edit `Sources/MacStreamCore/Services/MediaPipeline.swift`.

Add two protocol requirements after `currentHealth` so the store can read recorder integrity from any pipeline:

```swift
// shape, adapt to surrounding code
public protocol MediaPipeline: Sendable {
    var streamTransport: StreamTransportKind { get }
    var currentHealth: StreamHealth? { get }
    var recordingFailureDetail: String? { get }
    var captureSetupWarnings: [String] { get }
    ...
}
```

Add default implementations in the existing `public extension MediaPipeline` immediately after `currentHealth`:

```swift
// shape, adapt to surrounding code
public extension MediaPipeline {
    var streamTransport: StreamTransportKind { .endpointValidation }
    var currentHealth: StreamHealth? { nil }
    var recordingFailureDetail: String? { nil }
    var captureSetupWarnings: [String] { [] }
    ...
}
```

This must be the first code step so every existing fake/conformer still compiles before they opt into custom behavior.

**Verify**: `swift build` → exit 0, `Build complete!`.

### Step 2: Track setup warnings and writer failures inside `SystemMediaPipeline`

Edit `Sources/MacStreamCore/Services/MediaPipeline.swift` only.

Add queue-guarded stored fields near the other recording/writer fields:

```swift
// shape, adapt to surrounding code
private var recordingFailureReason: String?
private var setupWarnings: [String] = []
```

Expose them through protocol properties using `queue.sync`:

```swift
// shape, adapt to surrounding code
public var recordingFailureDetail: String? {
    queue.sync { recordingFailureReason }
}

public var captureSetupWarnings: [String] {
    queue.sync { setupWarnings }
}
```

At the start of `startRecording()` clear both fields before work can fail or warnings can accumulate. Do this after the `isRecording` check and before permission/content setup:

```swift
// shape, adapt to surrounding code
queue.sync {
    self.recordingFailureReason = nil
    self.setupWarnings = []
}
```

Within `startRecording()`, collect setup warnings in a local `[String]` so there are no partial cross-thread updates during setup, then assign the collected array into `self.setupWarnings` in the existing `queue.sync` block that stores `self.writer`, inputs, sessions, and `currentURL`.

Populate warnings for every requested-audio degraded case:

- System audio requested and `writer.canAdd(input)` is false:
  `"System audio could not be attached; this recording will not include system audio."`
- System audio requested and `stream.addStreamOutput(self, type: .audio, ...)` throws:
  `"System audio capture could not start; this recording will not include system audio."`
- Microphone requested but `makeMicrophoneCaptureIfAvailable(...)` returns `nil` and the recording is not sharing the publishing microphone session:
  `"Microphone capture could not be attached; this recording will not include microphone audio."`
- Microphone capture is present/shared but `writer.canAdd(input)` is false:
  `"Microphone audio could not be attached; this recording will not include microphone audio."`

Replace the `try?` system-audio stream-output call with `do/catch` so the error is not swallowed:

```swift
// shape, adapt to surrounding code
if mediaConfiguration.capturesSystemAudio {
    do {
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
    } catch {
        setupWarnings.append("System audio capture could not start; this recording will not include system audio.")
    }
}
```

Add the pure static helper beside `shouldCancelWriterOnStop(status:)`:

```swift
// shape, adapt to surrounding code
static func writerFailureDetail(status: AVAssetWriter.Status, errorDescription: String?) -> String? {
    guard status == .failed else { return nil }
    if let errorDescription, !errorDescription.isEmpty {
        return "Recording failed: \(errorDescription)"
    }
    return "Recording failed because the local media writer failed."
}
```

Add a queue-only setter helper or inline assignments that only write `recordingFailureReason` when `writerFailureDetail(...)` returns non-nil. Do not overwrite an existing failure detail with `nil`; preserving the first concrete failure is safer for the user and for tests.

After every append whose return value can be false, inspect the result:

```swift
// shape, adapt to surrounding code
if !videoInput.append(sampleBuffer) {
    recordDroppedFrameIfNeeded(outputType)
    if let detail = Self.writerFailureDetail(status: writer.status, errorDescription: writer.error?.localizedDescription) {
        recordingFailureReason = detail
    }
    return
}
```

Apply the same false-append handling to:

- direct screen video at current line 1350. This one must also call `recordDroppedFrameIfNeeded(outputType)`.
- composited screen video failure at current lines 1344-1347. It already records a dropped frame; additionally set `recordingFailureReason` when the writer status is `.failed`.
- system audio at current line 1360. Do not count dropped video frames for audio.
- microphone at current line 1771 inside `captureOutput(_:didOutput:from:)`. Do not count dropped video frames for microphone audio.

When `writer.startWriting()` returns false at current line 1324, also set `recordingFailureReason` if `writer.status == .failed`.

In `stopRecording()`, inspect writer status/error after `finishWriting` completes and before resuming the continuation. Because the existing `queue.sync` block nils out `self.writer`, keep the `RecordingWriterState.writer` reference and write back only `recordingFailureReason` on `self.queue` from the completion:

```swift
// shape, adapt to surrounding code
if writer.status == .writing {
    writer.finishWriting { [weak self] in
        if let detail = Self.writerFailureDetail(status: writer.status, errorDescription: writer.error?.localizedDescription) {
            self?.queue.sync {
                if self?.recordingFailureReason == nil {
                    self?.recordingFailureReason = detail
                }
            }
        }
        continuation.resume()
    }
    return
}

if let detail = Self.writerFailureDetail(status: writer.status, errorDescription: writer.error?.localizedDescription) {
    queue.sync {
        if recordingFailureReason == nil {
            recordingFailureReason = detail
        }
    }
}
```

Use the existing serial `queue` for these assignments; do not hop to the main actor from sample-buffer callbacks. Keep the hot path allocation-free unless an append actually returns false.

**Verify**: `swift build` → exit 0, `Build complete!`.

### Step 3: Propagate recording warnings and failures through `StudioStore`

Edit `Sources/MacStreamCore/Stores/StudioStore.swift`.

After `recordingState = .recording` in the successful `startRecording()` task, emit one warning event for each pipeline setup warning before or after the normal "Recording" event. Use `addWarningEventIfNeeded` to avoid duplicates:

```swift
// shape, adapt to surrounding code
recordingState = .recording
for warning in mediaPipeline.captureSetupWarnings {
    addWarningEventIfNeeded(title: "Recording degraded", detail: warning)
}
```

Add one public app-facing method wrapping the private warning helper for preview setup issues:

```swift
// shape, adapt to surrounding code
public func notePreviewSetupIssue(_ detail: String) {
    addWarningEventIfNeeded(title: "Camera preview unavailable", detail: detail)
}
```

Keep this as the only new public store API for camera preview plumbing.

Add one shared private store helper that detects `mediaPipeline.recordingFailureDetail` while recording is active, emits the failure warning, and stops only the recording. The helper must return whether it handled a failure so the media-health-loop caller can skip duplicate health work after it enqueues the recording stop:

```swift
// shape, adapt to surrounding code
@discardableResult
private func handleRecordingFailureIfNeeded() -> Bool {
    guard recordingState == .recording,
          let detail = mediaPipeline.recordingFailureDetail
    else {
        return false
    }

    addWarningEventIfNeeded(title: "Recording failed", detail: detail)
    if canStopRecording {
        stopRecording()
    }
    return true
}
```

Call this helper from both paths that can observe pipeline health:

- In `advanceMediaHealthIfNeeded()`, call `handleRecordingFailureIfNeeded()` before the `shouldRunMediaHealthLoop` guard so recording-only capture and paused live streams still fail fast. If it returns `true`, return immediately.
- In the live director/health path, call the same helper before the store refreshes stream health for an active director tick. Prefer the least invasive local hook in the live code: place it at the start of `refreshStreamHealth()` if that method is already shared by `advanceDirector()`/director ticks; otherwise place it inside `advanceDirector()` immediately before the existing `refreshStreamHealth()` call. Do not return early from the live director path just because the helper returns `true`: the recording stop must not take the stream offline, must not stop the stream, and must not bypass normal director/stream-health behavior.

Target shape for the media-health loop:

```swift
// shape, adapt to surrounding code
private func advanceMediaHealthIfNeeded() {
    if handleRecordingFailureIfNeeded() {
        return
    }

    guard shouldRunMediaHealthLoop else {
        stopMediaHealthLoopIfNeeded()
        return
    }

    sampleSystemPressure()
    refreshStreamHealth()
}
```

The key invariant is that record-while-streaming failures are handled even when `streamState.isLive == true` and `directorMode != .paused`, because `shouldRunMediaHealthLoop` is false in that state.

In the `stopRecording()` task completion, inspect `mediaPipeline.recordingFailureDetail` after `await mediaPipeline.stopRecording()` and before setting `recordingState`. If non-nil, set `.failed(detail)` and emit a warning event instead of the success event. If nil, preserve the current `.stopped` + "Local archive closed." behavior.

Target shape:

```swift
// shape, adapt to surrounding code
Task {
    await mediaPipeline.stopRecording()
    let failureDetail = mediaPipeline.recordingFailureDetail
    isRecordingStopping = false
    if let failureDetail {
        recordingState = .failed(failureDetail)
    } else {
        recordingState = .stopped
    }
    if !streamState.isLive {
        resetCaptureHealthPressure()
    }
    syncMediaHealthLoop()
    if let failureDetail {
        addWarningEventIfNeeded(title: "Recording failed", detail: failureDetail)
    } else {
        addEvent(kind: .stream, title: "Recording stopped", detail: "Local archive closed.")
    }
    endCaptureSessionIfIdle()
}
```

Do not set `.stopped` first and then `.failed`; UI observers should not see a false success transition.

**Verify**: `swift build` → exit 0, `Build complete!`.

### Step 4: Surface camera preview setup failures and retry configuration

Edit `Sources/MacStream/NativePreview/CameraPreviewView.swift`, `Sources/MacStream/Views/PreviewCanvasView.swift`, and `Sources/MacStream/Views/StudioView.swift`.

In `CameraPreviewView`, add a main-actor setup-failure callback property:

```swift
// shape, adapt to surrounding code
var onSetupFailure: (@MainActor (String) -> Void)? = nil
```

Pass it into `Coordinator` from `makeCoordinator()` and store it as a private property:

```swift
// shape, adapt to surrounding code
private let onSetupFailure: (@MainActor (String) -> Void)?
```

In `Coordinator`, report input-setup failures once per distinct failure detail. Use a small stored `lastReportedSetupFailure: String?` and call the callback with `Task { @MainActor in ... }` from the capture queue:

```swift
// shape, adapt to surrounding code
private func reportSetupFailure(_ detail: String) {
    guard lastReportedSetupFailure != detail else { return }
    lastReportedSetupFailure = detail
    guard let onSetupFailure else { return }
    Task { @MainActor in
        onSetupFailure(detail)
    }
}
```

Use human-readable failure strings that contain no device secret or path values, for example:

- `"Camera preview input could not be created; the preview will retry when camera settings change."`
- `"Camera preview input could not be reconfigured; the preview will retry when camera settings change."`

Extract the configuration body so `configureAndStart()` and retry from `update()` share it. Avoid nested `queue.async` when already executing on `queue`; do not call `configureAndStart()` from inside the `update()` queue block if `configureAndStart()` itself enqueues another block.

A safe shape is:

```swift
// shape, adapt to surrounding code
private func configureAndStart() {
    queue.async { [weak self] in
        self?.configureAndStartOnQueue()
    }
}

private func configureAndStartOnQueue() {
    guard wantsRunning else { return }
    if !isConfigured {
        session.beginConfiguration()
        applyRequestedPreset()
        defer { session.commitConfiguration() }
        guard configureInputOnQueue(failureDetail: "Camera preview input could not be created; the preview will retry when camera settings change.") else {
            return
        }
        isConfigured = true
    }
    if wantsRunning, !session.isRunning {
        session.startRunning()
    }
}
```

In `update(...)`, update requested values first, then if `wantsRunning && !isConfigured`, call `configureAndStartOnQueue()` directly from the same queue block and return. This is the retry path for an earlier black preview:

```swift
// shape, adapt to surrounding code
self.requestedPreset = preset
self.requestedFramesPerSecond = framesPerSecond
self.requestedCameraEnhancements = cameraEnhancements
self.requestedDeviceID = cameraDeviceID

if self.wantsRunning, !self.isConfigured {
    self.configureAndStartOnQueue()
    return
}

guard self.isConfigured else { return }
```

For `reconfigureInput()`, replace the silent `videoDevice = nil; return` with `reportSetupFailure(...)`, keep `isConfigured` false if no input is attached, and do not call `session.startRunning()` with no configured input.

In `PreviewCanvasView`, add a passthrough property:

```swift
// shape, adapt to surrounding code
var onCameraPreviewFailure: ((String) -> Void)? = nil
```

Pass it to `CameraPreviewView` at the construction site:

```swift
// shape, adapt to surrounding code
CameraPreviewView(
    configuration: previewConfiguration,
    cameraEnhancements: cameraEnhancements,
    cameraDeviceID: cameraDeviceID,
    onSetupFailure: onCameraPreviewFailure
)
```

If Swift's function type conversion complains because `CameraPreviewView.onSetupFailure` is explicitly `@MainActor`, make `PreviewCanvasView.onCameraPreviewFailure` use the same type: `(@MainActor (String) -> Void)?`.

In `StudioView.swift`, pass a closure from `PreviewColumnView` to the canvas:

```swift
// shape, adapt to surrounding code
PreviewCanvasView(
    ...,
    screenCaptureTarget: store.selectedScreenCaptureTarget,
    onCameraPreviewFailure: { detail in
        store.notePreviewSetupIssue(detail)
    }
)
```

Because `StudioStore` is main-actor isolated and the callback is invoked on the main actor, do not use `Task.detached` or a background queue here.

**Verify**: `swift build` → exit 0, `Build complete!`.

### Step 5: Add pipeline and store tests

Edit only the post-Plan-001 test files named below.

In `Tests/MacStreamCoreTests/TestSupport.swift`, extend `ConfigurableMediaPipeline` with settable properties:

```swift
// shape, adapt to surrounding code
var recordingFailureDetail: String?
var captureSetupWarnings: [String] = []
```

In `Tests/MacStreamCoreTests/MediaPipelinePolicyTests.swift`, add one static helper test for `SystemMediaPipeline.writerFailureDetail`. Cover at least:

- `.failed` plus a non-empty error description returns a non-nil detail containing the description.
- `.failed` with `nil` description returns a non-nil generic detail.
- `.writing`, `.completed`, `.cancelled`, and `.unknown` return `nil`.

Use the existing policy-test style in that file after Plan 001. Keep the helper `internal`/module-visible as needed for tests; do not make it `public`.

In `Tests/MacStreamCoreTests/StreamLifecycleTests.swift`, add four `@Test @MainActor` store tests:

1. **Start recording with setup warnings emits warning events**
   - Create `ConfigurableMediaPipeline()`.
   - Set `pipeline.captureSetupWarnings = ["System audio could not be attached; this recording will not include system audio.", "Microphone capture could not be attached; this recording will not include microphone audio."]`.
   - Create `StudioStore(mediaPipeline: pipeline)`.
   - Call `store.startRecording()` and `try? await Task.sleep(for: .milliseconds(80))`.
   - Expect `store.recordingState == .recording`.
   - Expect warning events with title `"Recording degraded"` and both details.

2. **Failure detail appearing mid-recording transitions to failed on health tick**
   - Model structure after `recordingOnlySamplesCaptureHealthWithoutDirectorLoop`, original `Tests/MacStreamCoreTests/DirectorEngineTests.swift:3804` at `03ae477`; after Plan 001 this function lives in `Tests/MacStreamCoreTests/StreamLifecycleTests.swift`.
   - Create `ConfigurableMediaPipeline()` and `StudioStore(mediaPipeline: pipeline, preferences: StudioPreferences(performanceMode: .adaptive))`.
   - Call `store.startRecording()` and sleep long enough for the start task to set `.recording`.
   - Set `pipeline.recordingFailureDetail = "Recording failed: disk full"`.
   - Sleep long enough for one media-health tick. The existing adaptive-mode test sleeps `80ms`; if the default performance interval is longer in live code, use a mode/configuration that makes the health loop tick quickly, or call the same public actions the existing test uses. Do not expose `advanceMediaHealthIfNeeded()`.
   - Expect `store.recordingState == .failed("Recording failed: disk full")`.
   - Expect a warning event with title `"Recording failed"` and that detail.
   - Expect no success event `"Recording stopped"` with detail `"Local archive closed."` after the failure.

3. **Failure detail appearing during live stream and active director fails recording only**
   - Create `ConfigurableMediaPipeline()` and a `StudioStore(mediaPipeline: pipeline, preferences: StudioPreferences(performanceMode: .adaptive))`.
   - Start streaming through the existing public stream-start helper/pattern in `StreamLifecycleTests.swift`, then start recording and sleep until `streamState.isLive == true`, `recordingState == .recording`, and the director mode is not `.paused`.
   - Set `pipeline.recordingFailureDetail = "Recording failed: disk full while streaming"`.
   - Trigger or wait for the existing live director/health tick; do not call private store methods and do not pause the director to make `shouldRunMediaHealthLoop` true.
   - Expect `store.recordingState == .failed("Recording failed: disk full while streaming")`.
   - Expect `store.streamState.isLive == true`; the stream must not transition offline and no stream-stop event should be emitted by this recording failure path.
   - Expect a warning event with title `"Recording failed"` and that detail.
   - Expect no success event `"Recording stopped"` with detail `"Local archive closed."` after the failure.

4. **Stop recording with failure detail reports failed instead of stopped**
   - Create pipeline/store.
   - Start recording, sleep until `.recording`.
   - Set `pipeline.recordingFailureDetail = "Recording failed: writer closed"`.
   - Call `store.stopRecording()` and sleep for the async stop task.
   - Expect `store.recordingState == .failed("Recording failed: writer closed")`.
   - Expect a `"Recording failed"` warning event and no false success event for `"Local archive closed."`.

Use `#expect`, not XCTest assertions. Do not use mocks; `ConfigurableMediaPipeline` is the existing shared fake.

**Verify**: `swift test` → exit 0; final line contains `Test run with 238 tests in 0 suites passed`.

### Step 6: Update the implementation-plan index row

Edit `plans/README.md` status row for Plan 002 only. Change its status to `DONE` if all verification commands in this plan passed. If the index file does not exist because Plan 001 was not applied, stop; do not create or redesign it in this plan.

**Verify**: `git status --short` → only the files listed in Scope are modified.

## Test plan

- Extend `Tests/MacStreamCoreTests/TestSupport.swift` so `ConfigurableMediaPipeline` has settable `recordingFailureDetail` and `captureSetupWarnings`.
- Add one helper-policy test in `Tests/MacStreamCoreTests/MediaPipelinePolicyTests.swift` for `SystemMediaPipeline.writerFailureDetail(status:errorDescription:)`.
- Add four store lifecycle tests in `Tests/MacStreamCoreTests/StreamLifecycleTests.swift`:
  - start recording with setup warnings emits `Recording degraded` warning events;
  - failure detail appearing mid-recording is picked up by the media-health loop and transitions to `.failed(detail)`;
  - failure detail appearing while streaming live with an active, non-paused director transitions only the recording to `.failed(detail)` and leaves `streamState.isLive == true`;
  - explicit stop with failure detail set results in `.failed(detail)`, not `.stopped`.
- Use `recordingOnlySamplesCaptureHealthWithoutDirectorLoop` from original `Tests/MacStreamCoreTests/DirectorEngineTests.swift:3804` as the structural pattern; after Plan 001 it lives in `Tests/MacStreamCoreTests/StreamLifecycleTests.swift`.
- Verification: `swift test` from repo root → exit 0; final line contains `Test run with 238 tests in 0 suites passed` (233 existing + exactly 5 new tests).

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `swift build` exits 0 and prints `Build complete!`.
- [ ] `swift test` exits 0 and the final summary contains `Test run with 238 tests in 0 suites passed`.
- [ ] `grep -c 'try? stream.addStreamOutput(self, type: .audio' Sources/MacStreamCore/Services/MediaPipeline.swift` prints `0`.
- [ ] `grep -c 'writerFailureDetail' Tests/MacStreamCoreTests/MediaPipelinePolicyTests.swift` prints at least `1`.
- [ ] `grep -c 'recordingFailureDetail\|captureSetupWarnings' Tests/MacStreamCoreTests/TestSupport.swift` prints at least `2`.
- [ ] `grep -c 'var onCameraPreviewFailure' Sources/MacStream/Views/PreviewCanvasView.swift` prints exactly `1`, and `grep -c 'onSetupFailure: onCameraPreviewFailure' Sources/MacStream/Views/PreviewCanvasView.swift` prints exactly `1`.
- [ ] `grep -c 'onCameraPreviewFailure: { detail in' Sources/MacStream/Views/StudioView.swift` prints exactly `1`, and `grep -c 'store.notePreviewSetupIssue(detail)' Sources/MacStream/Views/StudioView.swift` prints exactly `1`.
- [ ] `git status --short` shows modifications only to the in-scope files listed in this plan.
- [ ] `plans/README.md` row for Plan 002 is updated to `DONE`.
- [ ] No secret value, stream key, destination credential, or file path from a user credential store appears in any new event detail or test fixture.

## STOP conditions

Stop and report back (do not improvise) if:

- The drift check shows changes in any in-scope file and the live code no longer matches the excerpts in "Current state".
- Plan 001 has not landed, so `Tests/MacStreamCoreTests/TestSupport.swift`, `StreamLifecycleTests.swift`, or `MediaPipelinePolicyTests.swift` do not exist in the post-001 layout.
- `canStopRecording` no longer allows stopping while `recordingState == .recording`, or the failure-triggered stop path would be blocked by changed guard semantics in either recording-only capture or live stream + active director mode.
- Handling append failure requires changing RTMP publish behavior, `RTMPPublisher`, HaishinKit code, or any publish-path semantics. That is out of scope.
- Camera-preview failure plumbing requires more `StudioStore` public API than the single `notePreviewSetupIssue(_:)` method.
- Fixing setup warnings requires exposing or logging raw device identifiers, stream keys, Keychain contents, or other secrets.
- A verification command fails twice after a reasonable fix attempt.
- The post-Plan-001 baseline test count is no longer `233`, so `238` would not mean exactly five new tests.
- Any needed change falls outside the Scope list.

## Maintenance notes

- `recordingFailureReason` intentionally survives `stopRecording()` and is cleared only at the next `startRecording()`, so `StudioStore` can read it after teardown.
- Keep failure-detail construction off the per-frame hot path. It is acceptable after a failed append; it is not acceptable on every sample callback.
- Review the exact event ordering: users should see degraded setup warnings after recording starts, failed recordings must not also emit a success-style "Local archive closed." event, and a record-while-streaming failure must leave the live stream online while transitioning only `recordingState` to `.failed(detail)`.
- Keep the test-count arithmetic consistent: this plan adds exactly five tests total, so all summaries and done checks should expect `238` tests from a `233`-test baseline.
- If future work adds richer recorder diagnostics, extend `MediaPipeline.recordingFailureDetail` into a typed status in one clean cutover; do not add parallel ad-hoc properties.
- If camera-preview UX later grows an alert or settings action, keep this plan's callback as the low-level failure signal and implement presentation in the app layer.
