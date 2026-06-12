# Plan 006: Cache composited publish objects and serialize RTMP appends FIFO

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the existing status row for
> this plan in `plans/README.md`. The index is created by the advisor; if the
> file or Plan 006 row is missing, stop instead of inventing the structure.
>
> **Drift check (run first)**: `git diff --stat 03ae477..HEAD -- Sources/MacStreamCore/Services/MediaPipeline.swift Tests/MacStreamCoreTests/MediaPipelinePolicyTests.swift Tests/MacStreamCoreTests/TestSupport.swift plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/001-split-test-monolith.md, plans/002-recording-integrity.md
- **Category**: perf / bug
- **Planned at**: commit `03ae477`, 2026-06-11

## Why this matters

The Screen + Face RTMP publish path currently rebuilds CoreMedia/CoreImage objects for every video frame, even though the composed output size and pixel format are stable for a configured stream. That is avoidable hot-path churn in the live sample-buffer callback path. The optional HaishinKit publisher also starts one unstructured task per append and allows up to three concurrent appends, which preserves backpressure but not FIFO delivery; under load, samples can reach the mixer out of presentation order and cause live A/V jitter. This plan keeps the existing drop-when-full behavior while making appends single-consumer FIFO and caching only objects whose keys are stable and invalidated on reconfiguration.

## Current state

- `Sources/MacStreamCore/Services/MediaPipeline.swift` — owns the capture/record/publish pipeline, compositor, RTMP publisher protocol, default-build backpressure gate, and optional HaishinKit publisher.
- `Tests/MacStreamCoreTests/MediaPipelinePolicyTests.swift` — post-001 home for media-pipeline policy tests. At `03ae477`, these tests are still in `DirectorEngineTests.swift`; after plan 001, use the same functions and shared support moved into subsystem files.
- `Tests/MacStreamCoreTests/TestSupport.swift` — post-001 shared fakes, internal not private. Use existing fakes such as `ConfigurableMediaPipeline`, `FixedSignalProvider`, and `SpyMediaPipeline` as patterns if a test needs support code.
- `plans/README.md` — execution index to update when this plan is done.

Relevant excerpts at `03ae477`:

```swift
// Sources/MacStreamCore/Services/MediaPipeline.swift:373-399
public final class SystemMediaPipeline: NSObject, MediaPipeline, SCStreamOutput, AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.macstream.media.recording", qos: .userInitiated)
    private let rtmpPublisherFactory: @Sendable (RTMPPublishTarget) -> any RTMPPublisher
    private var mediaConfiguration = MediaPipelineConfiguration()
    private var stream: SCStream?
    private var publishingStream: SCStream?
    ...
    private var rtmpPublisher: RTMPPublisher?
    private var videoCompositor: RecordingVideoCompositor?
    private var publishingVideoCompositor: RecordingVideoCompositor?
    private var publishingPixelBufferPool: CVPixelBufferPool?
    private var latestCameraPixelBuffer: CVPixelBuffer?
    private var latestPublishingCameraPixelBuffer: CVPixelBuffer?
```

The sample-buffer callbacks run on `queue`: recording adds `self` as an `SCStreamOutput` with `sampleHandlerQueue: queue`, and publishing does the same.

```swift
// Sources/MacStreamCore/Services/MediaPipeline.swift:725-728
try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
if mediaConfiguration.capturesSystemAudio {
    try? stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
}

// Sources/MacStreamCore/Services/MediaPipeline.swift:1014-1017
let stream = SCStream(filter: selection.filter, configuration: configuration, delegate: nil)
try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
if mediaConfiguration.capturesSystemAudio {
    try? stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
}
```

The composited publishing path creates a video format description and a ready sample buffer every frame. The ready sample buffer is inherently per-frame; the format description is keyed only by the output image buffer's dimensions and pixel format and should be reused until those change.

```swift
// Sources/MacStreamCore/Services/MediaPipeline.swift:1413-1455
private func publishCompositedVideoSample(
    _ sampleBuffer: CMSampleBuffer,
    presentationTime: CMTime
) -> Bool {
    guard let outputPixelBuffer = makeCompositedPixelBuffer(
        sampleBuffer,
        pixelBufferPool: publishingPixelBufferPool,
        videoCompositor: publishingVideoCompositor,
        cameraPixelBuffer: latestPublishingCameraPixelBuffer
    ) else {
        return false
    }

    var formatDescription: CMVideoFormatDescription?
    guard CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: outputPixelBuffer,
        formatDescriptionOut: &formatDescription
    ) == noErr,
          let formatDescription
    else {
        return false
    }

    var timing = CMSampleTimingInfo(
        duration: sampleBuffer.duration.isValid ? sampleBuffer.duration : .invalid,
        presentationTimeStamp: presentationTime,
        decodeTimeStamp: .invalid
    )
    var compositedSampleBuffer: CMSampleBuffer?
    guard CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: outputPixelBuffer,
        formatDescription: formatDescription,
        sampleTiming: &timing,
        sampleBufferOut: &compositedSampleBuffer
    ) == noErr,
          let compositedSampleBuffer
    else {
        return false
    }

    return publish(compositedSampleBuffer)
}
```

Publishing composition is configured and cleared on the same pipeline queue. Add the format-description cache next to `publishingPixelBufferPool`, and clear it anywhere the pool/compositor is cleared or recreated.

```swift
// Sources/MacStreamCore/Services/MediaPipeline.swift:531-557
public func stopStream() async {
    let state = queue.sync {
        let publisher = rtmpPublisher
        let stream = publishingStream
        ...
        rtmpPublisher = nil
        publishingStream = nil
        publishingCaptureGeometry = nil
        publishingCameraSession = nil
        publishingCameraOutput = nil
        publishingMicrophoneSession = nil
        publishingMicrophoneOutput = nil
        publishingVideoCompositor = nil
        publishingPixelBufferPool = nil
        latestPublishingCameraPixelBuffer = nil
```

```swift
// Sources/MacStreamCore/Services/MediaPipeline.swift:1019-1030
let usesCompositedPublishing = Self.shouldPublishCompositedVideoSample(sceneKind: mediaConfiguration.sceneKind)
let publishingOutputWidth = selection.geometry.width(for: mediaConfiguration.maxVideoWidth)
let publishingOutputHeight = selection.geometry.height(for: mediaConfiguration.maxVideoWidth)
let publishingPixelBufferPool = usesCompositedPublishing
    ? Self.makePixelBufferPool(width: publishingOutputWidth, height: publishingOutputHeight)
    : nil
let publishingVideoCompositor = usesCompositedPublishing
    ? RecordingVideoCompositor(
        outputWidth: publishingOutputWidth,
        outputHeight: publishingOutputHeight,
        cameraEnhancements: mediaConfiguration.cameraEnhancements
    )
    : nil
```

```swift
// Sources/MacStreamCore/Services/MediaPipeline.swift:1066-1079
queue.sync {
    self.publishingStream = stream
    self.publishingCaptureGeometry = selection.geometry
    self.publishingCameraSession = cameraCapture?.session
    self.publishingCameraOutput = cameraCapture?.output
    self.publishingMicrophoneSession = microphoneSession
    self.publishingMicrophoneOutput = microphoneOutput
    self.publishingVideoCompositor = publishingVideoCompositor
    self.publishingPixelBufferPool = publishingPixelBufferPool
    self.latestPublishingCameraPixelBuffer = nil
    self.publishingOwnsMicrophoneSession = ownsMicrophoneSession
    self.firstPublishingVideoContinuation = nil
    self.didPublishFirstVideoFrame = false
    self.resetHealth(using: mediaConfiguration)
}
```

```swift
// Sources/MacStreamCore/Services/MediaPipeline.swift:1651-1671
private func configurePublishingVideoComposition(using configuration: MediaPipelineConfiguration) {
    guard let publishingCaptureGeometry else {
        publishingVideoCompositor = nil
        publishingPixelBufferPool = nil
        return
    }

    let outputWidth = publishingCaptureGeometry.width(for: configuration.maxVideoWidth)
    let outputHeight = publishingCaptureGeometry.height(for: configuration.maxVideoWidth)
    guard let pixelBufferPool = Self.makePixelBufferPool(width: outputWidth, height: outputHeight) else {
        publishingVideoCompositor = nil
        publishingPixelBufferPool = nil
        return
    }

    publishingPixelBufferPool = pixelBufferPool
    publishingVideoCompositor = RecordingVideoCompositor(
        outputWidth: outputWidth,
        outputHeight: outputHeight,
        cameraEnhancements: configuration.cameraEnhancements
    )
}
```

`RecordingVideoCompositor` already reuses `CIContext`; extend that pattern to background/filter state. The `outputRect` is fixed by `init(outputWidth:outputHeight:cameraEnhancements:)`, so a background keyed by that rect is valid for the compositor instance.

```swift
// Sources/MacStreamCore/Services/MediaPipeline.swift:1846-1855
private final class RecordingVideoCompositor {
    private let context = CIContext()
    private let outputRect: CGRect
    private let cameraEnhancements: CameraEnhancementSettings
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    init(outputWidth: Int, outputHeight: Int, cameraEnhancements: CameraEnhancementSettings) {
        self.outputRect = CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight)
        self.cameraEnhancements = cameraEnhancements
    }
```

Per-frame object churn inside the compositor today:

```swift
// Sources/MacStreamCore/Services/MediaPipeline.swift:1857-1888
func render(
    screenPixelBuffer: CVPixelBuffer,
    cameraPixelBuffer: CVPixelBuffer?,
    to outputPixelBuffer: CVPixelBuffer
) {
    let background = CIImage(color: CIColor(red: 0, green: 0, blue: 0))
        .cropped(to: outputRect)
    let screen = aspectFill(
        normalized(CIImage(cvPixelBuffer: screenPixelBuffer)),
        in: outputRect
    )
    var composed = screen.composited(over: background)
    ...
    } else {
        let placeholder = CIImage(color: CIColor(red: 0.02, green: 0.02, blue: 0.02))
            .cropped(to: pictureInPictureRect)
        composed = placeholder.composited(over: composed)
    }

    context.render(
        composed.cropped(to: outputRect),
        to: outputPixelBuffer,
        bounds: outputRect,
        colorSpace: colorSpace
    )
}
```

```swift
// Sources/MacStreamCore/Services/MediaPipeline.swift:1904-1914
guard cameraEnhancements.usesAutoLight,
      let filter = CIFilter(name: "CIColorControls")
else {
    return image
}

filter.setValue(image, forKey: kCIInputImageKey)
filter.setValue(cameraEnhancements.autoLightAmount * 0.18, forKey: kCIInputBrightnessKey)
filter.setValue(1 + cameraEnhancements.autoLightAmount * 0.08, forKey: kCIInputContrastKey)
filter.setValue(1 + cameraEnhancements.autoLightAmount * 0.10, forKey: kCIInputSaturationKey)
return filter.outputImage.map(normalized) ?? image
```

The compositor render method has exactly two call sites, both reached from the `SCStream` sample callback path that is registered on `queue` above:

```swift
// Sources/MacStreamCore/Services/MediaPipeline.swift:1291-1293
let didPublish = Self.shouldPublishCompositedVideoSample(sceneKind: mediaConfiguration.sceneKind)
    ? publishCompositedVideoSample(sampleBuffer, presentationTime: presentationTime)
    : publish(sampleBuffer)

// Sources/MacStreamCore/Services/MediaPipeline.swift:1343-1344
if mediaConfiguration.sceneKind == .screenAndFace {
    guard appendCompositedVideoSample(sampleBuffer, presentationTime: presentationTime) else {
```

```swift
// Sources/MacStreamCore/Services/MediaPipeline.swift:1479-1509
private func makeCompositedPixelBuffer(
    _ sampleBuffer: CMSampleBuffer,
    pixelBufferPool: CVPixelBufferPool?,
    videoCompositor: RecordingVideoCompositor?,
    cameraPixelBuffer: CVPixelBuffer?
) -> CVPixelBuffer? {
    guard let screenPixelBuffer = sampleBuffer.imageBuffer,
          let pixelBufferPool,
          let videoCompositor
    else {
        return nil
    }
    ...
    videoCompositor.render(
        screenPixelBuffer: screenPixelBuffer,
        cameraPixelBuffer: cameraPixelBuffer,
        to: outputPixelBuffer
    )
    return outputPixelBuffer
}
```

Camera enhancement settings are captured into each new compositor instance and cause active stream reconfiguration, so caching inside the compositor must not outlive an enhancement change.

```swift
// Sources/MacStreamCore/Services/MediaPipeline.swift:1811-1813
|| previous.capturesSystemAudio != next.capturesSystemAudio
|| previous.cameraEnhancements != next.cameraEnhancements
|| previous.screenCaptureTarget != next.screenCaptureTarget
```

The current RTMP append gate is default-build code and already tested. It allows bounded in-flight work but has no ordering guarantee by itself.

```swift
// Sources/MacStreamCore/Services/MediaPipeline.swift:2001-2039
protocol RTMPPublisher: AnyObject, Sendable {
    func configure(configuration: MediaPipelineConfiguration) async throws
    func connect() async throws
    func append(_ sampleBuffer: CMSampleBuffer, track: UInt8) -> Bool
    func close() async
}
...
final class RTMPAppendBackpressureGate: @unchecked Sendable {
    private let lock = NSLock()
    private let maxPendingAppends: Int
    private var pendingAppends = 0

    init(maxPendingAppends: Int = 3) {
        self.maxPendingAppends = max(1, maxPendingAppends)
    }

    func tryBeginAppend() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard pendingAppends < maxPendingAppends else { return false }
        pendingAppends += 1
        return true
    }

    func finishAppend() {
        lock.lock()
        pendingAppends = max(0, pendingAppends - 1)
        lock.unlock()
    }
}
```

The optional HaishinKit path spawns an unstructured task for every sample buffer append. With `maxPendingAppends` greater than 1, those tasks can race each other into `mixer.append`.

```swift
// Sources/MacStreamCore/Services/MediaPipeline.swift:2042-2109
#if MAC_STREAM_HAS_HAISHINKIT
private final class HaishinKitRTMPPublisher: RTMPPublisher, @unchecked Sendable {
    private let target: RTMPPublishTarget
    private let connection = RTMPConnection()
    private let stream: RTMPStream
    private let mixer = MediaMixer(captureSessionMode: .manual, multiTrackAudioMixingEnabled: true)
    private let appendGate = RTMPAppendBackpressureGate()
    ...
    func append(_ sampleBuffer: CMSampleBuffer, track: UInt8) -> Bool {
        guard appendGate.tryBeginAppend() else { return false }
        Task {
            defer { appendGate.finishAppend() }
            await mixer.append(sampleBuffer, track: track)
        }
        return true
    }

    func close() async {
        await mixer.removeOutput(stream)
        await mixer.stopRunning()
        _ = try? await stream.close()
        _ = try? await connection.close()
    }
}
#endif
```

Existing default-build tests to model after, originally in `DirectorEngineTests.swift` at `03ae477` and moved by plan 001 into `MediaPipelinePolicyTests.swift`:

```swift
// Tests/MacStreamCoreTests/DirectorEngineTests.swift:1208-1219
@Test
func rtmpAppendBackpressureGateRejectsWorkWhenPublishQueueIsFull() {
    let gate = RTMPAppendBackpressureGate(maxPendingAppends: 2)

    #expect(gate.tryBeginAppend())
    #expect(gate.tryBeginAppend())
    #expect(!gate.tryBeginAppend())

    gate.finishAppend()

    #expect(gate.tryBeginAppend())
}
```

```swift
// Tests/MacStreamCoreTests/DirectorEngineTests.swift:1221-1239
@Test
func rtmpConnectionCancellationBoxResumesPendingConnectionAttempt() async {
    let cancellation = RTMPConnectionCancellationBox()
    let connection = NWConnection(host: "127.0.0.1", port: 9, using: .tcp)
    var didThrowCancellation = false
    ...
    #expect(didThrowCancellation)
}
```

Repo conventions that matter:

- macOS 26-only SwiftPM app, Swift 6 strict concurrency, SwiftUI.
- Tests use Swift Testing (`@Test` and `#expect`), not XCTest.
- `StudioStore` is `@MainActor @Observable` and remains the single source of truth; do not route live sample callbacks through the main actor.
- The live sample-buffer hot path must stay free of avoidable per-frame allocations and main-actor hops.
- No model output drives live scene switching.
- Stream keys/secrets remain in Keychain and redacted everywhere; do not print or persist secrets.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift check | `git diff --stat 03ae477..HEAD -- Sources/MacStreamCore/Services/MediaPipeline.swift Tests/MacStreamCoreTests/MediaPipelinePolicyTests.swift Tests/MacStreamCoreTests/TestSupport.swift plans/README.md` | no output, or only changes you have reviewed against this plan's excerpts |
| Default build | `swift build` | exit 0, `Build complete!` |
| Default tests | `swift test` | exit 0; final summary includes all tests passed (baseline at planning time: `Test run with 233 tests in 0 suites passed`; expect baseline + this plan's new tests after implementation) |
| HaishinKit flag build | `MAC_STREAM_ENABLE_HAISHINKIT=1 swift build` | exit 0, `Build complete!` |
| Count new queue tests | `grep -c '^func orderedMediaAppendQueue' Tests/MacStreamCoreTests/MediaPipelinePolicyTests.swift` | `3` |
| Queue shutdown API check | `grep -E 'func (finishAndClose|closeAndWait)\(\) async' Sources/MacStreamCore/Services/MediaPipeline.swift` | one async drain/shutdown method on `OrderedMediaAppendQueue` |
| Scope check | `git status --short` | only in-scope files modified |

## Scope

**In scope** (the only files you should modify or create):

- `Sources/MacStreamCore/Services/MediaPipeline.swift`
- `Tests/MacStreamCoreTests/MediaPipelinePolicyTests.swift`
- `Tests/MacStreamCoreTests/TestSupport.swift` only if a new reusable test helper is genuinely needed; prefer putting tiny one-off helpers in `MediaPipelinePolicyTests.swift`.
- `plans/README.md` status row for Plan 006 only.

**Out of scope** (do NOT touch):

- Any UI files under `Sources/MacStream/`.
- Any store/model files outside `MediaPipeline.swift`.
- Recording-integrity changes from plan 002. This plan executes after 002; if 002 already changed nearby hunks, adapt by re-reading live code, not by reverting 002.
- Secrets, destination configuration, Keychain behavior, or logging redaction.
- Replacing HaishinKit APIs, changing codecs/settings, or changing RTMP connection behavior beyond append ordering and close cancellation.
- Adding new dependencies or changing `Package.swift`.

## Git workflow

- Commit directly on `main` (no PRs unless asked).
- Use conventional-prefix commit messages (`feat:`, `fix:`, `refactor:`, `test:`, `ci:`), e.g. `fix: serialize rtmp media appends`.
- Do NOT push unless the operator explicitly consented.

## Steps

### Step 1: Add a default-build FIFO append queue beside the existing gate

In `Sources/MacStreamCore/Services/MediaPipeline.swift`, add a small flag-independent type near `RTMPAppendBackpressureGate` (around line 2016). Do not put it inside `#if MAC_STREAM_HAS_HAISHINKIT`; the default test target must compile and test it.

Keep the existing `RTMPAppendBackpressureGate` surface unless the new queue can preserve the same semantics more simply. The required behavior is:

- `enqueue` is synchronous and returns `false` immediately when the bounded pending count is already full.
- Capacity defaults to `3`, matching today's `RTMPAppendBackpressureGate()` default.
- Accepted items are processed by one long-lived consumer `Task`, one at a time, in FIFO order.
- `finishAppend`/pending decrement happens after the consumer finishes each item.
- `finishAndClose() async` or `closeAndWait() async` stops accepting new items, finishes/cancels the stream, and awaits consumer shutdown before returning.
- Once close has started, later `enqueue` calls return `false`; no item accepted after close may be processed.
- No per-sample `Task { ... }` is created by the call site.

Target shape, adapt to surrounding code:

```swift
// shape, adapt to surrounding code
final class OrderedMediaAppendQueue<Element: Sendable>: @unchecked Sendable {
    typealias Handler = @Sendable (Element) async -> Void

    private let lock = NSLock()
    private let gate: RTMPAppendBackpressureGate
    private var isClosed = false
    private let continuation: AsyncStream<Element>.Continuation
    private let consumerTask: Task<Void, Never>

    init(maxPendingAppends: Int = 3, handler: @escaping Handler) {
        self.gate = RTMPAppendBackpressureGate(maxPendingAppends: maxPendingAppends)
        let streamAndContinuation = AsyncStream<Element>.makeStream(of: Element.self)
        self.continuation = streamAndContinuation.continuation
        self.consumerTask = Task {
            for await item in streamAndContinuation.stream {
                await handler(item)
                self.gate.finishAppend()
            }
        }
    }

    func enqueue(_ item: Element) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed, gate.tryBeginAppend() else { return false }
        continuation.yield(item)
        return true
    }

    func closeAndWait() async {
        lock.lock()
        guard !isClosed else {
            lock.unlock()
            await consumerTask.value
            return
        }
        isClosed = true
        lock.unlock()
        continuation.finish()
        consumerTask.cancel()
        await consumerTask.value
    }
}
```

Important: the shape above shows the intended ownership, not exact final code. You may need to avoid capturing `self` before all stored properties are initialized. A safe implementation is to create a private `State` box for the lock/gate/closed flag and let the consumer task capture that box plus the stream. If you keep `AsyncStream`, use `.bufferingPolicy: .unbounded` only if the gate is the single bound; do not rely on `AsyncStream` dropping policy because the current surface returns a synchronous Bool for accepted vs dropped.

If `continuation.yield` can fail after `tryBeginAppend`, decrement the gate before returning `false`; do not leak pending count.

**Verify**: `swift build` → exit 0, `Build complete!`.

### Step 2: Add default-build tests for FIFO, drop-when-full, and close

In `Tests/MacStreamCoreTests/MediaPipelinePolicyTests.swift` (post-001 layout), add three Swift Testing tests near the existing `rtmpAppendBackpressureGateRejectsWorkWhenPublishQueueIsFull` test. Keep the existing gate test; the new queue tests complement it.

Name the functions so this command is stable:

- `orderedMediaAppendQueuePreservesFIFOOrderUnderAsyncConsumer`
- `orderedMediaAppendQueueRejectsWhenPendingCapacityIsFull`
- `orderedMediaAppendQueueStopsAcceptingAndProcessingAfterClose`

Test shapes, adapt to the exact final queue API:

```swift
// shape, adapt to surrounding code
@Test
func orderedMediaAppendQueuePreservesFIFOOrderUnderAsyncConsumer() async {
    let recorder = OrderedAppendRecorder()
    let queue = OrderedMediaAppendQueue<Int>(maxPendingAppends: 10) { value in
        await recorder.append(value)
    }

    for value in 0..<8 {
        #expect(queue.enqueue(value))
    }

    await recorder.waitForCount(8)
    #expect(await recorder.values == Array(0..<8))
    await queue.closeAndWait()
}
```

For the capacity test, make the consumer block on a continuation/actor gate so accepted items remain pending. With `maxPendingAppends: 3`, the first three enqueues should return `true` and the fourth should return `false`. Then unblock the consumer and `await queue.closeAndWait()` or `await queue.finishAndClose()`.

For the close test, enqueue one item that blocks in the consumer, wait until it starts, call `closeAndWait()`/`finishAndClose()` from a child task, then assert a later `enqueue` returns `false` while shutdown is in progress. Unblock the consumer, await the close task, and assert the later value never appears. If the implementation intentionally lets the already-started item complete after close, the test should assert exactly that and no more; the acceptance requirement is **no appends accepted or processed after close begins, and close does not return until the consumer task is drained/cancelled**.

If you need a tiny helper actor, put it in `MediaPipelinePolicyTests.swift` unless multiple files need it. Use the existing async cancellation test `rtmpConnectionCancellationBoxResumesPendingConnectionAttempt` (original `DirectorEngineTests.swift:1222`) as the style pattern: no XCTest expectations, just async Swift Testing and `#expect`.

**Verify**: `swift test` → exit 0; final summary reports all tests passed, with 3 more tests than the post-001/002 baseline.

### Step 3: Wire the FIFO queue into the HaishinKit publisher and close lifecycle

Still in `Sources/MacStreamCore/Services/MediaPipeline.swift`, update only the optional HaishinKit publisher call site behind `#if MAC_STREAM_HAS_HAISHINKIT`.

Replace the per-sample `Task` in `HaishinKitRTMPPublisher.append(_:track:)` with a synchronous enqueue into `OrderedMediaAppendQueue`. The enqueued payload should contain the `CMSampleBuffer` and `track`. The consumer should await the real HaishinKit call in FIFO order:

```swift
// shape, adapt to surrounding code
private struct PendingMediaAppend: Sendable {
    var sampleBuffer: CMSampleBuffer
    var track: UInt8
}

private lazy var appendQueue = OrderedMediaAppendQueue<PendingMediaAppend>(maxPendingAppends: 3) { [mixer] pending in
    await mixer.append(pending.sampleBuffer, track: pending.track)
}

func append(_ sampleBuffer: CMSampleBuffer, track: UInt8) -> Bool {
    appendQueue.enqueue(PendingMediaAppend(sampleBuffer: sampleBuffer, track: track))
}

func close() async {
    await appendQueue.closeAndWait()
    await mixer.removeOutput(stream)
    await mixer.stopRunning()
    _ = try? await stream.close()
    _ = try? await connection.close()
}
```

Use `finishAndClose()` instead of `closeAndWait()` if that name better fits the final queue API, but it must be `async` and must not return until the queue has stopped accepting appends and the consumer task has drained or cancelled all accepted work. Do not expose only a synchronous `close()` on the queue.

Cancellation/close requirement: `HaishinKitRTMPPublisher.close()` is the lifecycle boundary. It currently calls `mixer.removeOutput(stream)`, `mixer.stopRunning()`, `stream.close()`, and `connection.close()` at lines 2105-2109; await queue shutdown before removing/stopping outputs so no accepted append can race with HaishinKit teardown.

**Verify**: `swift build` → exit 0, `Build complete!`.

### Step 4: Cache the composited-publish video format description by pixel-buffer key

In `Sources/MacStreamCore/Services/MediaPipeline.swift`, add a cache for composited publishing output format descriptions. Keep it confined to the existing `SystemMediaPipeline.queue`; do not add a new lock.

Implementation requirements:

- Add a small private key/cache type near pipeline state or near `publishCompositedVideoSample`:

```swift
// shape, adapt to surrounding code
private struct VideoFormatDescriptionCache {
    var width: Int
    var height: Int
    var pixelFormat: OSType
    var formatDescription: CMVideoFormatDescription

    func matches(_ pixelBuffer: CVPixelBuffer) -> Bool {
        width == CVPixelBufferGetWidth(pixelBuffer)
            && height == CVPixelBufferGetHeight(pixelBuffer)
            && pixelFormat == CVPixelBufferGetPixelFormatType(pixelBuffer)
    }
}
```

- Add `private var publishingVideoFormatDescriptionCache: VideoFormatDescriptionCache?` next to `publishingPixelBufferPool`.
- In `publishCompositedVideoSample`, replace the unconditional `CMVideoFormatDescriptionCreateForImageBuffer` with a named cache-miss helper so the final shape is easy to inspect:

```swift
// shape, adapt to surrounding code
private static func makeVideoFormatDescription(
    for pixelBuffer: CVPixelBuffer
) -> CMVideoFormatDescription? {
    var formatDescription: CMVideoFormatDescription?
    guard CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescriptionOut: &formatDescription
    ) == noErr else {
        return nil
    }
    return formatDescription
}

let formatDescription: CMVideoFormatDescription
if let cache = publishingVideoFormatDescriptionCache, cache.matches(outputPixelBuffer) {
    formatDescription = cache.formatDescription
} else {
    guard let created = Self.makeVideoFormatDescription(for: outputPixelBuffer) else { return false }
    publishingVideoFormatDescriptionCache = VideoFormatDescriptionCache(
        width: CVPixelBufferGetWidth(outputPixelBuffer),
        height: CVPixelBufferGetHeight(outputPixelBuffer),
        pixelFormat: CVPixelBufferGetPixelFormatType(outputPixelBuffer),
        formatDescription: created
    )
    formatDescription = created
}
```

- Keep `CMSampleBufferCreateReadyWithImageBuffer` per-frame. The sample timing changes every frame; do not cache sample buffers.
- Clear `publishingVideoFormatDescriptionCache = nil` anywhere `publishingVideoCompositor`/`publishingPixelBufferPool` is set to `nil` or recreated:
  - `stopStream()` queue block around lines 548-557.
  - `startRTMPCapture` registration block around lines 1066-1079.
  - `startRTMPCapture` catch cleanup around lines 1091-1099.
  - `configurePublishingVideoComposition(using:)` around lines 1651-1671, both failure branches and successful recreation.
  - `startPublishingCameraCaptureIfNeeded` only indirectly calls `configurePublishingVideoComposition`; do not duplicate invalidation there if the helper handles it.

If you expose pure helper functions such as `VideoFormatDescriptionCache.matches(width:height:pixelFormat:)`, keep them `internal` only if tests need them; otherwise keep them `private`.

**Verify**: `swift build` → exit 0, `Build complete!`.

### Step 5: Cache compositor background and auto-light filter per compositor instance

In `RecordingVideoCompositor` in `Sources/MacStreamCore/Services/MediaPipeline.swift`, extend the existing `CIContext` reuse pattern with two additional caches:

- A black background `CIImage` keyed by `outputRect`. Because `outputRect` is set once in `init(outputWidth:outputHeight:cameraEnhancements:)` and never changes, this can be a `let` image initialized from that rect, or a tiny `(rect, image)` cache if that fits the code better.
- A `CIColorControls` filter instance reused only when `cameraEnhancements.usesAutoLight` is true, with all input values reset on every frame before reading `outputImage`.

Target shape, adapt to surrounding code:

```swift
// shape, adapt to surrounding code
private final class RecordingVideoCompositor {
    private let context = CIContext()
    private let outputRect: CGRect
    private let cameraEnhancements: CameraEnhancementSettings
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let background: CIImage
    private lazy var colorControlsFilter: CIFilter? = CIFilter(name: "CIColorControls")

    init(outputWidth: Int, outputHeight: Int, cameraEnhancements: CameraEnhancementSettings) {
        self.outputRect = CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight)
        self.cameraEnhancements = cameraEnhancements
        self.background = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: outputRect)
    }
```

If Swift initialization order rejects using `outputRect` before all stored properties are initialized, compute a local `rect` first, assign `outputRect = rect`, then initialize `background` from `rect`.

In `render`, remove the per-frame black `CIImage(color:)` creation and use the cached background. In `enhancedCameraImage`, replace `CIFilter(name:)` construction with the cached filter:

```swift
// shape, adapt to surrounding code
guard cameraEnhancements.usesAutoLight,
      let filter = colorControlsFilter
else { return image }

filter.setValue(image, forKey: kCIInputImageKey)
filter.setValue(cameraEnhancements.autoLightAmount * 0.18, forKey: kCIInputBrightnessKey)
filter.setValue(1 + cameraEnhancements.autoLightAmount * 0.08, forKey: kCIInputContrastKey)
filter.setValue(1 + cameraEnhancements.autoLightAmount * 0.10, forKey: kCIInputSaturationKey)
let output = filter.outputImage.map(normalized) ?? image
filter.setValue(nil, forKey: kCIInputImageKey)
return output
```

Thread-safety constraint: this is safe only because all known `render` call paths run from `stream(_:didOutputSampleBuffer:of:)`, and both recording and publishing streams register `sampleHandlerQueue: queue`. If a new off-queue render call appears during drift review, STOP.

Enhancement invalidation: do not mutate `cameraEnhancements` on an existing compositor. The current code builds a new `RecordingVideoCompositor` from `mediaConfiguration.cameraEnhancements` for recording setup (`MediaPipeline.swift:641-645`), publishing setup (`MediaPipeline.swift:1025-1030`), and publishing reconfiguration (`MediaPipeline.swift:1666-1671`), and `shouldUpdateActiveStreamConfiguration` includes `cameraEnhancements` (`MediaPipeline.swift:1811-1813`). Preserve that model.

Optional: cache the dark picture-in-picture placeholder keyed by `pictureInPictureRect` if the code is straightforward, but do not expand the plan just for that; the required cache is the output background and color-controls filter.

**Verify**: `swift build` → exit 0, `Build complete!`.

### Step 6: Run default tests and the HaishinKit flag build

Run the full default suite from the repo root, then compile the optional HaishinKit path.

**Verify**: `swift test` → exit 0; final summary reports all tests passed, including the 3 new `orderedMediaAppendQueue...` tests.

**Verify**: `MAC_STREAM_ENABLE_HAISHINKIT=1 swift build` → exit 0, `Build complete!`.

### Step 7: Update the existing plan index row and inspect scope

Update only the existing Plan 006 row in `plans/README.md` to `DONE` after all commands pass. Do not create `plans/README.md`, do not add a new table, and do not invent a Plan 006 row. If the file or the Plan 006 row is missing, STOP and report that the advisor index was not generated.

**Verify**: `test -f plans/README.md && grep -Ec '006.*DONE|DONE.*006' plans/README.md` → `1`.

**Verify**: `git status --short` → only these paths changed: `Sources/MacStreamCore/Services/MediaPipeline.swift`, `Tests/MacStreamCoreTests/MediaPipelinePolicyTests.swift`, optionally `Tests/MacStreamCoreTests/TestSupport.swift`, and `plans/README.md`.

## Test plan

New tests, all default-build and all in `Tests/MacStreamCoreTests/MediaPipelinePolicyTests.swift` after plan 001:

- `orderedMediaAppendQueuePreservesFIFOOrderUnderAsyncConsumer` — enqueue tagged values and assert the consumer records them in the same order.
- `orderedMediaAppendQueueRejectsWhenPendingCapacityIsFull` — capacity `3`; block the consumer so the first three values are pending and assert the fourth enqueue returns `false`.
- `orderedMediaAppendQueueStopsAcceptingAndProcessingAfterClose` — start async queue shutdown, assert later enqueue returns `false`, unblock the consumer, await shutdown, and assert no later value is processed.

Use these existing tests as style patterns:

- `rtmpAppendBackpressureGateRejectsWorkWhenPublishQueueIsFull`, originally `Tests/MacStreamCoreTests/DirectorEngineTests.swift:1209`, post-001 file `MediaPipelinePolicyTests.swift`.
- `rtmpConnectionCancellationBoxResumesPendingConnectionAttempt`, originally `Tests/MacStreamCoreTests/DirectorEngineTests.swift:1222`, post-001 file `MediaPipelinePolicyTests.swift`.

Cache behavior:

- If `VideoFormatDescriptionCache` or its key comparison is exposed as a pure internal helper, add focused tests in `MediaPipelinePolicyTests.swift` for matching/mismatching width, height, and pixel format.
- If the cache remains private inside `MediaPipeline.swift`, do not contort production visibility just to test it. Verify Part A and Part B with `swift build`, the existing suite, and manual live QA below.

Manual live QA checklist for the operator after implementation, because CoreMedia/CoreImage object reuse is mostly hot-path behavior:

1. Build the optional publisher path: `MAC_STREAM_ENABLE_HAISHINKIT=1 swift build`.
2. Run a Screen + Face RTMP publish to a local or test endpoint.
3. Confirm the composed output has no visual regression: screen fills the frame, camera picture-in-picture appears, missing-camera placeholder still appears when applicable.
4. Toggle camera enhancements mid-stream; confirm reconfiguration invalidates/replaces compositor state and the stream continues without stale mirror/rotation/auto-light values.
5. Under load, watch the live stream for reduced A/V jitter; dropped-frame accounting may still report drops when the bounded queue is full, which is expected.

Verification commands:

- `swift build` → exit 0.
- `swift test` → exit 0; all tests pass, including 3 new ordered append queue tests.
- `MAC_STREAM_ENABLE_HAISHINKIT=1 swift build` → exit 0.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `swift build` exits 0.
- [ ] `swift test` exits 0 and the final summary reports all tests passed.
- [ ] `grep -c '^func orderedMediaAppendQueue' Tests/MacStreamCoreTests/MediaPipelinePolicyTests.swift` prints `3`.
- [ ] `MAC_STREAM_ENABLE_HAISHINKIT=1 swift build` exits 0.
- [ ] `test -f plans/README.md && grep -Ec '006.*DONE|DONE.*006' plans/README.md` prints `1`.
- [ ] `git status --short` shows no modified files outside the in-scope list.
- [ ] `grep -Ec 'func (finishAndClose|closeAndWait)\(\) async' Sources/MacStreamCore/Services/MediaPipeline.swift` prints `1`.
- [ ] `grep -En 'await appendQueue\.(finishAndClose|closeAndWait)\(\)' Sources/MacStreamCore/Services/MediaPipeline.swift` prints the call in `HaishinKitRTMPPublisher.close()` before `mixer.removeOutput(stream)`, `mixer.stopRunning()`, `stream.close()`, and `connection.close()`.
- [ ] `grep -c 'CIFilter(name: "CIColorControls")' Sources/MacStreamCore/Services/MediaPipeline.swift` prints `1`.
- [ ] `grep -c 'CMVideoFormatDescriptionCreateForImageBuffer' Sources/MacStreamCore/Services/MediaPipeline.swift` prints `1`, and `grep -n 'makeVideoFormatDescription' Sources/MacStreamCore/Services/MediaPipeline.swift` prints the named cache-miss helper and its call site.

## STOP conditions

Stop and report back (do not improvise) if:

- The drift check shows changes in `Sources/MacStreamCore/Services/MediaPipeline.swift` from plan 002 and the live append/composition code no longer matches the excerpts above. Re-read the live code and report the overlap instead of reverting or overwriting plan 002.
- The code at the HaishinKit append site no longer calls `await mixer.append(sampleBuffer, track: track)`, or the mixer append signature is different from the excerpt.
- You find any `RecordingVideoCompositor.render` call path that does not run on `SystemMediaPipeline.queue` or another single serial executor. The cached `CIFilter` is not thread-safe enough for concurrent render calls.
- It is unclear how append drops are recorded after your changes, or `RTMPPublisher.append` can no longer synchronously return `false` when full.
- Swift concurrency rejects moving `CMSampleBuffer` through the ordered queue and the only apparent fix is broad `@unchecked Sendable` on public types or disabling strict concurrency.
- A verification command fails twice after a reasonable fix attempt.
- `plans/README.md` does not exist, or it exists but has no Plan 006 row to update. The advisor owns index creation; do not invent the index format or add a missing row.
- The fix appears to require changing files outside the in-scope list.

## Maintenance notes

- The ordered queue intentionally preserves the existing max-pending/drop behavior; it fixes ordering, not throughput. If future work changes capacity, update both the queue default and the tests.
- Keep the queue type outside `#if MAC_STREAM_HAS_HAISHINKIT` so default CI continues to test ordering and close semantics.
- Do not cache `CMSampleBuffer` instances in the publish path. Timing is frame-specific.
- Any future compositor cache must be keyed by immutable compositor state or invalidated when `cameraEnhancements`, output dimensions, or pixel format change.
- Reviewer focus: no new locks on the live pipeline queue for Part A/B, no main-actor hops in sample callbacks, no per-sample unstructured `Task` in `HaishinKitRTMPPublisher.append`, and no secrets/logging changes.
