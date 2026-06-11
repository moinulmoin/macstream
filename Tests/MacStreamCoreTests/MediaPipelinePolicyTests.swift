import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import Network
import Testing
@testable import MacStreamCore

@Test
func mediaPipelinesReportStreamTransport() {
    #expect(PreviewMediaPipeline().streamTransport == .preview)
    #if MAC_STREAM_HAS_HAISHINKIT
    #expect(SystemMediaPipeline().streamTransport == .rtmpPublish)
    #else
    #expect(SystemMediaPipeline().streamTransport == .endpointValidation)
    #endif
}

@Test
func systemMediaPipelineSkipsZeroLevelAudioSamples() {
    var configuration = MediaPipelineConfiguration()

    #expect(SystemMediaPipeline.shouldProcessSystemAudioSample(configuration: configuration))
    #expect(SystemMediaPipeline.shouldProcessMicrophoneAudioSample(configuration: configuration))
    #expect(SystemMediaPipeline.shouldProcessMicrophoneOutputSample(isActiveOutput: true, configuration: configuration))
    #expect(!SystemMediaPipeline.shouldProcessMicrophoneOutputSample(isActiveOutput: false, configuration: configuration))

    configuration.systemAudioLevel = 0
    #expect(!SystemMediaPipeline.shouldProcessSystemAudioSample(configuration: configuration))
    #expect(SystemMediaPipeline.shouldProcessMicrophoneAudioSample(configuration: configuration))
    #expect(SystemMediaPipeline.shouldProcessMicrophoneOutputSample(isActiveOutput: true, configuration: configuration))

    configuration.microphoneLevel = 0
    #expect(!SystemMediaPipeline.shouldProcessSystemAudioSample(configuration: configuration))
    #expect(!SystemMediaPipeline.shouldProcessMicrophoneAudioSample(configuration: configuration))
    #expect(!SystemMediaPipeline.shouldProcessMicrophoneOutputSample(isActiveOutput: true, configuration: configuration))
}

@Test
func systemMediaPipelinePublishesOnlyFromPublishingCaptureOutputs() {
    #expect(SystemMediaPipeline.shouldPublishStreamSample(isPublishingStream: true, hasPublisher: true))
    #expect(!SystemMediaPipeline.shouldPublishStreamSample(isPublishingStream: false, hasPublisher: true))
    #expect(!SystemMediaPipeline.shouldPublishStreamSample(isPublishingStream: true, hasPublisher: false))
    #expect(!SystemMediaPipeline.shouldPublishStreamSample(isPublishingStream: false, hasPublisher: false))
    #expect(SystemMediaPipeline.shouldPublishScreenStreamSample(
        isPublishingStream: true,
        hasPublisher: true,
        hasImageBuffer: true
    ))
    #expect(!SystemMediaPipeline.shouldPublishScreenStreamSample(
        isPublishingStream: true,
        hasPublisher: true,
        hasImageBuffer: false
    ))

    #expect(SystemMediaPipeline.shouldPublishMicrophoneOutputSample(isPublishingOutput: true, hasPublisher: true))
    #expect(!SystemMediaPipeline.shouldPublishMicrophoneOutputSample(isPublishingOutput: false, hasPublisher: true))
    #expect(!SystemMediaPipeline.shouldPublishMicrophoneOutputSample(isPublishingOutput: true, hasPublisher: false))
    #expect(!SystemMediaPipeline.shouldPublishMicrophoneOutputSample(isPublishingOutput: false, hasPublisher: false))

    #expect(SystemMediaPipeline.shouldPublishCompositedVideoSample(sceneKind: .screenAndFace))
    #expect(!SystemMediaPipeline.shouldPublishCompositedVideoSample(sceneKind: .screenOnly))
    #expect(!SystemMediaPipeline.shouldPublishCompositedVideoSample(sceneKind: .face))
    #expect(!SystemMediaPipeline.shouldPublishCompositedVideoSample(sceneKind: .brb))
}

@Test
func microphonePermissionGrantStartsOnlyWhenSamplingIsStillRequested() {
    #expect(MicrophonePermissionStartPolicy.shouldStartEngine(isStartRequested: true, isPermissionGranted: true))
    #expect(!MicrophonePermissionStartPolicy.shouldStartEngine(isStartRequested: false, isPermissionGranted: true))
    #expect(!MicrophonePermissionStartPolicy.shouldStartEngine(isStartRequested: true, isPermissionGranted: false))
    #expect(!MicrophonePermissionStartPolicy.shouldStartEngine(isStartRequested: false, isPermissionGranted: false))
}

@Test
func screenMotionFrameSamplingGateDropsBurstFrames() {
    #expect(ScreenMotionFrameSamplingGate.shouldSample(now: 10, lastSampleTime: nil, interval: 0.25))
    #expect(!ScreenMotionFrameSamplingGate.shouldSample(now: 10.10, lastSampleTime: 10, interval: 0.25))
    #expect(ScreenMotionFrameSamplingGate.shouldSample(now: 10.25, lastSampleTime: 10, interval: 0.25))
    #expect(ScreenMotionFrameSamplingGate.shouldSample(now: 10.50, lastSampleTime: 10, interval: 0.25))
}

@Test
func screenMotionLumaSamplingUsesSmallFixedGrid() {
    #expect(ScreenMotionLumaSamplingGrid.columns == 16)
    #expect(ScreenMotionLumaSamplingGrid.rows == 9)
    #expect(ScreenMotionLumaSamplingGrid.capacity == 144)
}

@Test
func systemMediaPipelineCancelsRecordingWriterThatNeverStarted() {
    #expect(SystemMediaPipeline.shouldCancelWriterOnStop(status: .unknown))
    #expect(!SystemMediaPipeline.shouldCancelWriterOnStop(status: .writing))
    #expect(!SystemMediaPipeline.shouldCancelWriterOnStop(status: .completed))
    #expect(!SystemMediaPipeline.shouldCancelWriterOnStop(status: .failed))
    #expect(!SystemMediaPipeline.shouldCancelWriterOnStop(status: .cancelled))
}

@Test
func systemMediaPipelineReportsRecordingWriterFailureDetail() {
    let explicit = SystemMediaPipeline.writerFailureDetail(status: .failed, errorDescription: "disk full")
    #expect(explicit?.contains("disk full") == true)

    let generic = SystemMediaPipeline.writerFailureDetail(status: .failed, errorDescription: nil)
    #expect(generic == "Recording failed because the local media writer failed.")

    #expect(SystemMediaPipeline.writerFailureDetail(status: .writing, errorDescription: "disk full") == nil)
    #expect(SystemMediaPipeline.writerFailureDetail(status: .completed, errorDescription: "disk full") == nil)
    #expect(SystemMediaPipeline.writerFailureDetail(status: .cancelled, errorDescription: "disk full") == nil)
    #expect(SystemMediaPipeline.writerFailureDetail(status: .unknown, errorDescription: "disk full") == nil)
}

@Test
func systemMediaPipelineBuildsUpdatedStreamConfigurationFromCaptureGeometry() {
    let geometry = MediaCaptureGeometry(sourceWidth: 3_024, sourceHeight: 1_964, maxVideoWidth: 1_920)
    let balanced = SystemMediaPipeline.streamConfiguration(
        geometry: geometry,
        mediaConfiguration: MediaPipelineConfiguration(maxVideoWidth: 1_920, framesPerSecond: 30, queueDepth: 5)
    )

    #expect(balanced.width == 1_920)
    #expect(balanced.height == 1_246)
    #expect(balanced.minimumFrameInterval == CMTime(value: 1, timescale: 30))
    #expect(balanced.queueDepth == 5)
    #expect(balanced.capturesAudio)

    let efficiency = SystemMediaPipeline.streamConfiguration(
        geometry: geometry,
        mediaConfiguration: MediaPipelineConfiguration(maxVideoWidth: 1_280, framesPerSecond: 24, queueDepth: 3, capturesSystemAudio: false)
    )

    #expect(efficiency.width == 1_280)
    #expect(efficiency.height == 830)
    #expect(efficiency.minimumFrameInterval == CMTime(value: 1, timescale: 24))
    #expect(efficiency.queueDepth == 3)
    #expect(!efficiency.capturesAudio)
}

@Test
func systemMediaPipelineSkipsStreamReconfigurationForLevelOnlyChanges() {
    let baseline = MediaPipelineConfiguration(
        maxVideoWidth: 1_920,
        framesPerSecond: 30,
        videoBitrate: 8_000_000,
        queueDepth: 5,
        capturesSystemAudio: true,
        capturesMicrophone: true,
        systemAudioLevel: 1,
        microphoneLevel: 1
    )
    let levelOnly = MediaPipelineConfiguration(
        maxVideoWidth: 1_920,
        framesPerSecond: 30,
        videoBitrate: 8_000_000,
        queueDepth: 5,
        capturesSystemAudio: true,
        capturesMicrophone: true,
        systemAudioLevel: 0.4,
        microphoneLevel: 0.3
    )
    let microphoneCaptureOnly = MediaPipelineConfiguration(
        maxVideoWidth: 1_920,
        framesPerSecond: 30,
        videoBitrate: 8_000_000,
        queueDepth: 5,
        capturesSystemAudio: true,
        capturesMicrophone: false,
        systemAudioLevel: 1,
        microphoneLevel: 0
    )

    #expect(!SystemMediaPipeline.shouldUpdateActiveStreamConfiguration(from: baseline, to: levelOnly))
    #expect(!SystemMediaPipeline.shouldUpdateActiveStreamConfiguration(from: baseline, to: microphoneCaptureOnly))
}

@Test
func systemMediaPipelineUpdatesStreamConfigurationForCaptureCostChanges() {
    let baseline = MediaPipelineConfiguration(
        maxVideoWidth: 1_920,
        framesPerSecond: 30,
        queueDepth: 5,
        capturesSystemAudio: true
    )
    let lowerVideoCost = MediaPipelineConfiguration(
        maxVideoWidth: 1_280,
        framesPerSecond: 24,
        queueDepth: 3,
        capturesSystemAudio: true
    )
    let withoutSystemAudio = MediaPipelineConfiguration(
        maxVideoWidth: 1_920,
        framesPerSecond: 30,
        queueDepth: 5,
        capturesSystemAudio: false
    )
    let targetChanged = MediaPipelineConfiguration(
        maxVideoWidth: 1_920,
        framesPerSecond: 30,
        queueDepth: 5,
        capturesSystemAudio: true,
        screenCaptureTarget: ScreenCaptureTarget(id: "window-42", kind: .window, name: "Slides", detail: "Keynote")
    )
    let sceneChanged = MediaPipelineConfiguration(
        maxVideoWidth: 1_920,
        framesPerSecond: 30,
        queueDepth: 5,
        sceneKind: .screenAndFace,
        capturesSystemAudio: true
    )

    #expect(SystemMediaPipeline.shouldUpdateActiveStreamConfiguration(from: baseline, to: lowerVideoCost))
    #expect(SystemMediaPipeline.shouldUpdateActiveStreamConfiguration(from: baseline, to: withoutSystemAudio))
    #expect(SystemMediaPipeline.shouldUpdateActiveStreamConfiguration(from: baseline, to: targetChanged))
    #expect(SystemMediaPipeline.shouldUpdateActiveStreamConfiguration(from: baseline, to: sceneChanged))
}

@Test
func systemMediaPipelineAvoidsDoubleCountingCaptureFPSWhenPublishingAndRecordingOverlap() {
    #expect(SystemMediaPipeline.shouldRecordVideoSampleForHealth(
        isScreenOutput: true,
        isPublishingStream: true,
        hasDedicatedPublishingStream: true
    ))
    #expect(!SystemMediaPipeline.shouldRecordVideoSampleForHealth(
        isScreenOutput: true,
        isPublishingStream: false,
        hasDedicatedPublishingStream: true
    ))
    #expect(SystemMediaPipeline.shouldRecordVideoSampleForHealth(
        isScreenOutput: true,
        isPublishingStream: false,
        hasDedicatedPublishingStream: false
    ))
    #expect(!SystemMediaPipeline.shouldRecordVideoSampleForHealth(
        isScreenOutput: false,
        isPublishingStream: true,
        hasDedicatedPublishingStream: true
    ))
}

@Test
func systemMediaPipelineIgnoresStaleRecordingStreamSamples() {
    #expect(SystemMediaPipeline.shouldProcessRecordingStreamSample(isRecordingStream: true, hasWriter: true))
    #expect(!SystemMediaPipeline.shouldProcessRecordingStreamSample(isRecordingStream: false, hasWriter: true))
    #expect(!SystemMediaPipeline.shouldProcessRecordingStreamSample(isRecordingStream: true, hasWriter: false))
    #expect(!SystemMediaPipeline.shouldProcessRecordingStreamSample(isRecordingStream: false, hasWriter: false))
}

@Test
func rtmpAppendBackpressureGateRejectsWorkWhenPublishQueueIsFull() {
    let gate = RTMPAppendBackpressureGate(maxPendingAppends: 2)

    #expect(gate.tryBeginAppend())
    #expect(gate.tryBeginAppend())
    #expect(!gate.tryBeginAppend())

    gate.finishAppend()

    #expect(gate.tryBeginAppend())
}

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

@Test
func orderedMediaAppendQueueRejectsWhenPendingCapacityIsFull() async {
    let blocker = OrderedAppendBlocker()
    let queue = OrderedMediaAppendQueue<Int>(maxPendingAppends: 3) { value in
        await blocker.append(value)
    }

    #expect(queue.enqueue(0))
    #expect(queue.enqueue(1))
    #expect(queue.enqueue(2))
    await blocker.waitForStartedCount(1)

    #expect(!queue.enqueue(3))

    await blocker.releaseAll()
    await queue.closeAndWait()
    #expect(await blocker.startedCount == 3)
}

@Test
func orderedMediaAppendQueueStopsAcceptingAndProcessingAfterClose() async {
    let recorder = OrderedAppendRecorder()
    let blocker = OrderedAppendBlocker()
    let queue = OrderedMediaAppendQueue<Int>(maxPendingAppends: 3) { value in
        await blocker.append(value, recorder: recorder)
    }

    #expect(queue.enqueue(1))
    await blocker.waitForStartedCount(1)

    let closeTask = Task {
        await queue.closeAndWait()
    }
    for _ in 0..<100 where !queue.isClosed {
        await Task.yield()
    }
    #expect(queue.isClosed)

    #expect(!queue.enqueue(2))
    #expect(await recorder.values == [1])

    await blocker.releaseAll()
    await closeTask.value
    #expect(await recorder.values == [1])
}

@Test
func rtmpConnectionCancellationBoxResumesPendingConnectionAttempt() async {
    let cancellation = RTMPConnectionCancellationBox()
    let connection = NWConnection(host: "127.0.0.1", port: 9, using: .tcp)
    var didThrowCancellation = false

    do {
        try await withCheckedThrowingContinuation { continuation in
            let continuationBox = ConnectionContinuationBox(continuation)
            #expect(cancellation.install(connection: connection, continuation: continuationBox))
            cancellation.cancel()
        }
    } catch is CancellationError {
        didThrowCancellation = true
    } catch {
        didThrowCancellation = false
    }

    #expect(didThrowCancellation)
}

@Test
func systemMediaPipelineClosesConnectedPublisherWhenStartIsCancelledBeforeRegistration() async {
    let publisher = DelayedSuccessfulRTMPPublisher()
    let pipeline = SystemMediaPipeline { _ in publisher }
    let destination = StreamDestination(
        name: "Test RTMP",
        rtmpURL: "rtmp://127.0.0.1/live/stream"
    )

    let task = Task {
        try await pipeline.startStream(destination: destination)
    }

    await publisher.waitUntilConnectStarted()
    task.cancel()
    await publisher.finishConnect()

    do {
        try await task.value
    } catch is CancellationError {
    } catch {
        Issue.record("Expected CancellationError, got \(error)")
    }

    #expect(await publisher.closeCount == 1)
}

@Test
func systemMediaPipelineOnlyCapturesPublishMediaForFullRTMPTransport() {
    let pipeline = SystemMediaPipeline()

    #if MAC_STREAM_HAS_HAISHINKIT
    #expect(SystemMediaPipeline.capturesMediaForStreamTransport)
    #expect(pipeline.requiresScreenCaptureVideoForStream)
    #expect(pipeline.supportedSceneKindsForStream == [.screenOnly, .screenAndFace])
    #else
    #expect(!SystemMediaPipeline.capturesMediaForStreamTransport)
    #expect(!pipeline.requiresScreenCaptureVideoForStream)
    #expect(pipeline.supportedSceneKindsForStream == Set(SceneKind.allCases))
    #endif
    #expect(pipeline.requiresScreenCaptureVideoForRecording)
    #expect(pipeline.supportedSceneKindsForRecording == [.screenOnly, .screenAndFace])
}

@Test
func systemMediaPipelineSharesMicrophoneCaptureWhenStreamingAndRecordingOverlap() {
    #expect(SystemMediaPipeline.sharesMicrophoneCaptureBetweenStreamAndRecording)
}

@Test
func systemMediaPipelineStartsPreviewSessionWithoutEndpoint() async throws {
    let pipeline = SystemMediaPipeline()

    try await pipeline.startStream(destination: StreamDestination())
    await pipeline.stopStream()
}


private actor OrderedAppendRecorder {
    private(set) var values: [Int] = []
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func append(_ value: Int) {
        values.append(value)
        resumeReadyWaiters()
    }

    func waitForCount(_ count: Int) async {
        guard values.count < count else { return }
        await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }

    private func resumeReadyWaiters() {
        var pendingWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in waiters {
            if values.count >= waiter.count {
                waiter.continuation.resume()
            } else {
                pendingWaiters.append(waiter)
            }
        }
        waiters = pendingWaiters
    }
}

private actor OrderedAppendBlocker {
    private(set) var startedCount = 0
    private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false

    func append(_ value: Int, recorder: OrderedAppendRecorder? = nil) async {
        startedCount += 1
        resumeReadyStartWaiters()
        if let recorder {
            await recorder.append(value)
        }
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitForStartedCount(_ count: Int) async {
        guard startedCount < count else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((count, continuation))
        }
    }

    func releaseAll() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func resumeReadyStartWaiters() {
        var pendingWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in startWaiters {
            if startedCount >= waiter.count {
                waiter.continuation.resume()
            } else {
                pendingWaiters.append(waiter)
            }
        }
        startWaiters = pendingWaiters
    }
}
