import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import Network
import Testing
@testable import MacStreamCore

@MainActor
private func waitUntilStreamIsLive(_ store: StudioStore) async {
    for _ in 0..<200 {
        guard !store.streamState.isLive else { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
private func waitUntilStreamIsOffline(_ store: StudioStore) async {
    for _ in 0..<200 {
        guard store.streamState != .offline || store.isStreamStopping else { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
private func waitUntilRecordingIsActive(_ store: StudioStore) async {
    for _ in 0..<100 {
        guard store.recordingState != .recording else { return }
        await Task.yield()
    }
}

@MainActor
private func waitUntilRecordingIsStopped(_ store: StudioStore) async {
    for _ in 0..<200 {
        guard store.recordingState != .stopped else { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
private func waitUntilCaptureScanCompletes(_ store: StudioStore) async {
    for _ in 0..<100 {
        guard !store.hasRunInitialCaptureScan else { return }
        await Task.yield()
    }
}

@Test
@MainActor
func studioStoreUsesPreviewTransportForDefaultDestination() {
    let pipeline = ConfigurableMediaPipeline(streamTransport: .rtmpPublish)
    let store = StudioStore(mediaPipeline: pipeline)

    #expect(store.streamTransport == .preview)
    #expect(store.streamStatusDetail == "Ready")
}

@Test
@MainActor
func studioStoreUpdatesDestinationModeWithoutStartingStream() {
    let pipeline = ConfigurableMediaPipeline(streamTransport: .rtmpPublish)
    let store = StudioStore(mediaPipeline: pipeline)

    store.setDestinationMode(.rtmp)

    #expect(store.destination.mode == .rtmp)
    #expect(store.destination.name == "RTMP Destination")
    #expect(store.destination.rtmpURL.isEmpty)
    #expect(store.streamTransport == .rtmpPublish)
    #expect(!store.canStartStream)
    #expect(store.canEditDestination)
    #expect(store.streamStatusDetail == "Enter a valid RTMP or RTMPS URL.")

    store.destination.rtmpURL = "rtmps://live.example.com/app/sk_live_secret"
    store.setDestinationMode(.preview)

    #expect(store.destination.mode == .preview)
    #expect(store.destination.name == "Preview Session")
    #expect(store.destination.rtmpURL == "preview")
    #expect(store.selectedDestination?.rtmpURL == "rtmps://live.example.com/app/sk_live_secret")
    #expect(store.streamTransport == .preview)
}

@Test
@MainActor
func savedDestinationRestoresConfiguredRTMP() {
    let pipeline = ConfigurableMediaPipeline(streamTransport: .rtmpPublish)
    let store = StudioStore(mediaPipeline: pipeline)

    store.applySavedDestination(
        StreamDestination(
            mode: .rtmp,
            name: "Twitch",
            rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
        )
    )

    #expect(store.destination.mode == .rtmp)
    #expect(store.destination.name == "Twitch")
    #expect(store.destination.safeDisplayDetail == "rtmps://live.example.com/app/****")
    #expect(store.streamTransport == .rtmpPublish)
    #expect(store.canStartStream)
}

@Test
@MainActor
func redundantDestinationWritesDoNotResolveTransport() {
    let pipeline = TransportCountingMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)
    let transportReadCount = pipeline.transportReadCount

    store.destination = store.destination

    #expect(store.destination.mode == .preview)
    #expect(store.streamTransport == .preview)
    #expect(pipeline.transportReadCount == transportReadCount)
}

@Test
@MainActor
func destinationModeChangesResolveTransportOnlyWhenNeeded() {
    let pipeline = TransportCountingMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)

    #expect(store.streamTransport == .preview)
    #expect(pipeline.transportReadCount == 0)

    store.setDestinationMode(.rtmp)

    #expect(store.destination.mode == .rtmp)
    #expect(store.destination.name == "RTMP Destination")
    #expect(store.destination.rtmpURL.isEmpty)
    #expect(store.streamTransport == .rtmpPublish)
    #expect(pipeline.transportReadCount == 1)

    store.setDestinationMode(.preview)

    #expect(store.destination.mode == .preview)
    #expect(store.destination.name == "Preview Session")
    #expect(store.streamTransport == .preview)
    #expect(pipeline.transportReadCount == 1)
}

@Test
@MainActor
func invalidRTMPDestinationDoesNotStartStream() async {
    let pipeline = ConfigurableMediaPipeline(streamTransport: .rtmpPublish)
    let store = StudioStore(mediaPipeline: pipeline)
    store.setDestinationMode(.rtmp)

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.streamState == .offline)
    #expect(!store.canStartStream)
    #expect(store.canEditDestination)
    #expect(pipeline.configurationAtStartStream == nil)
    #expect(store.streamStatusDetail == "Enter a valid RTMP or RTMPS URL.")

    store.destination.rtmpURL = "rtmps://live.example.com/app/sk_live_secret"

    #expect(store.canStartStream)
}

@Test
@MainActor
func invalidRTMPDestinationCanBeEditedBackToPreview() {
    let pipeline = ConfigurableMediaPipeline(streamTransport: .rtmpPublish)
    let store = StudioStore(mediaPipeline: pipeline)

    store.setDestinationMode(.rtmp)
    #expect(store.destination.mode == .rtmp)
    #expect(!store.canStartStream)
    #expect(store.canEditDestination)

    store.setDestinationMode(.preview)

    #expect(store.destination.mode == .preview)
    #expect(store.destination.name == "Preview Session")
    #expect(store.canStartStream)
    #expect(store.canEditDestination)
    #expect(store.streamTransport == .preview)
}

@Test
@MainActor
func studioStoreReportsTransportAwareStreamStatusDetails() async {
    let pipeline = ConfigurableMediaPipeline(streamTransport: .rtmpPublish)
    pipeline.currentHealth = StreamHealth(publishState: .publishing)
    let store = StudioStore(mediaPipeline: pipeline)

    store.startStream()
    #expect(store.streamStatusDetail == "Starting local preview session")
    await waitUntilStreamIsLive(store)
    #expect(store.streamStatusDetail == "Local preview running")

    store.stopStream()
    await waitUntilStreamIsOffline(store)
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )
    store.startStream()
    #expect(store.streamStatusDetail == "Connecting RTMP publisher (attempt 1/3)")
    for _ in 0..<200 {
        guard store.streamStatusDetail != "Publishing media" else { break }
        try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(store.streamStatusDetail == "Publishing media")
}

@Test
@MainActor
func previewStreamStartsWithoutArtificialDelay() async {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted),
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(
        mediaPipeline: SystemMediaPipeline(),
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report)
    )

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))
    store.selectRecommendedStartingScene()

    store.startStream()

    #expect(store.streamStatusDetail == "Starting local preview session")
    for _ in 0..<10 {
        if store.streamState == .live { break }
        await Task.yield()
    }
    #expect(store.streamState == .live)
    #expect(store.streamStatusDetail == "Local preview running")

    store.stopStream()
}

@Test
@MainActor
func failedStreamStartStaysRetryableAndEditable() async {
    let pipeline = RecoveringMediaPipeline()
    pipeline.errorToThrow = TestStreamError(message: "Bad endpoint")
    let store = StudioStore(mediaPipeline: pipeline, streamStartRetryPolicy: .none)
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.streamState == .failed("Bad endpoint"))
    #expect(store.streamStatusDetail == "Bad endpoint")
    #expect(!store.isLive)
    #expect(store.canStartStream)
    #expect(store.canEditDestination)
    #expect(pipeline.startCount == 1)

    store.destination.rtmpURL = "rtmps://live.example.com/app/sk_live_recovered"
    pipeline.errorToThrow = nil
    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.streamState == .live)
    #expect(store.isLive)
    #expect(pipeline.startCount == 2)
}

@Test
@MainActor
func editingEndpointAfterFailedStreamClearsStaleFailure() async {
    let pipeline = RecoveringMediaPipeline()
    pipeline.errorToThrow = TestStreamError(message: "Bad endpoint")
    let store = StudioStore(mediaPipeline: pipeline, streamStartRetryPolicy: .none)
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.streamState == .failed("Bad endpoint"))
    #expect(store.streamStatusDetail == "Bad endpoint")

    store.destination.rtmpURL = "rtmps://live.example.com/app/sk_live_recovered"

    #expect(store.streamState == .offline)
    #expect(store.streamStatusDetail == "Ready")
    #expect(store.canStartStream)
    #expect(store.canEditDestination)
}

@Test
@MainActor
func editingEndpointAfterFailedStreamSurfacesNewValidationError() async {
    let pipeline = RecoveringMediaPipeline()
    pipeline.errorToThrow = TestStreamError(message: "Bad endpoint")
    let store = StudioStore(mediaPipeline: pipeline, streamStartRetryPolicy: .none)
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    store.destination.rtmpURL = "not an rtmp endpoint"

    #expect(store.streamState == .offline)
    #expect(!store.canStartStream)
    #expect(store.canEditDestination)
    #expect(store.streamStatusDetail == "Enter a valid RTMP or RTMPS URL.")
}

@Test
func streamStartRetryPolicyUsesBoundedBackoff() {
    let policy = StreamStartRetryPolicy(maxAttempts: 3, backoffMilliseconds: [10])

    #expect(policy.maxAttempts == 3)
    #expect(policy.delayBeforeRetry(afterFailedAttempt: 1) == .milliseconds(10))
    #expect(policy.delayBeforeRetry(afterFailedAttempt: 2) == .milliseconds(10))
    #expect(policy.delayBeforeRetry(afterFailedAttempt: 3) == nil)
}

@Test
@MainActor
func rtmpStreamStartRetriesTransientFailures() async {
    let pipeline = FlakyStartMediaPipeline(failuresBeforeSuccess: 2)
    let store = StudioStore(
        mediaPipeline: pipeline,
        streamStartRetryPolicy: StreamStartRetryPolicy(maxAttempts: 3, backoffMilliseconds: [1, 1])
    )
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )

    store.startStream()
    await waitUntilStreamIsLive(store)

    #expect(store.streamState == .live)
    #expect(store.streamStartAttempt == 3)
    #expect(store.streamStartMaxAttempts == 3)
    #expect(pipeline.startCount == 3)
    #expect(store.events.contains { $0.title == "Retrying RTMP Publish" })
}

@Test
@MainActor
func liveRTMPDisconnectStopsOldPublisherAndRecoversWithBoundedRetry() async {
    let pipeline = SessionRecoveryMediaPipeline()
    let store = StudioStore(
        mediaPipeline: pipeline,
        streamStartRetryPolicy: StreamStartRetryPolicy(maxAttempts: 3, backoffMilliseconds: [1, 1])
    )
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )

    store.startStream()
    await waitUntilStreamIsLive(store)
    #expect(pipeline.startStreamCount == 1)

    pipeline.failSession("RTMP connection closed by the server.", recoveryStartFailures: 2)
    store.advanceDirector()
    #expect(store.isStreamConnecting)

    for _ in 0..<400 {
        guard store.streamState != .live || pipeline.startStreamCount < 4 else { break }
        try? await Task.sleep(for: .milliseconds(5))
    }

    #expect(store.streamState == .live)
    #expect(pipeline.stopStreamCount == 1)
    #expect(pipeline.startStreamCount == 4)
    #expect(store.streamStartAttempt == 3)
    #expect(store.events.contains { $0.title == "Stream interrupted" })
    #expect(store.events.contains { $0.title == "Stream recovered" })
    #expect(!store.events.contains { $0.title == "Stream recovery failed" })

    store.stopStream()
    await waitUntilStreamIsOffline(store)
}

@Test
@MainActor
func liveRTMPRecoveryPreservesStreamOwnedRecordingUntilStreamStops() async {
    let pipeline = SessionRecoveryMediaPipeline()
    let store = StudioStore(
        mediaPipeline: pipeline,
        preferences: StudioPreferences(recordWhileStreaming: true),
        streamStartRetryPolicy: StreamStartRetryPolicy(maxAttempts: 3, backoffMilliseconds: [1, 1])
    )
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )

    store.startStream()
    await waitUntilStreamIsLive(store)
    await waitUntilRecordingIsActive(store)

    pipeline.failSession("RTMP connection closed by the server.", recoveryStartFailures: 1)
    store.advanceDirector()

    for _ in 0..<1_000 {
        if store.streamState.isLive && pipeline.startStreamCount == 3 { break }
        await Task.yield()
    }

    #expect(store.streamState == .live)
    #expect(store.recordingState == .recording)
    #expect(pipeline.startRecordingCount == 1)
    #expect(pipeline.stopRecordingCount == 0)
    #expect(store.streamRecoveryMetrics.interruptionCount == 1)
    #expect(store.streamRecoveryMetrics.successfulRecoveryCount == 1)
    #expect(store.streamRecoveryMetrics.failedRecoveryCount == 0)
    #expect(store.streamRecoveryMetrics.cancelledRecoveryCount == 0)

    store.stopStream()
    await waitUntilStreamIsOffline(store)
    await waitUntilRecordingIsStopped(store)

    #expect(pipeline.stopRecordingCount == 1)
}

@Test
@MainActor
func liveRTMPRecoveryFailureStopsStreamOwnedRecording() async {
    let pipeline = SessionRecoveryMediaPipeline()
    let store = StudioStore(
        mediaPipeline: pipeline,
        preferences: StudioPreferences(recordWhileStreaming: true),
        streamStartRetryPolicy: StreamStartRetryPolicy(maxAttempts: 2, backoffMilliseconds: [1])
    )
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )

    store.startStream()
    await waitUntilStreamIsLive(store)
    await waitUntilRecordingIsActive(store)

    pipeline.failSession("RTMP connection failed.", recoveryStartFailures: 3)
    store.advanceDirector()

    for _ in 0..<1_000 {
        if case .failed = store.streamState, store.recordingState == .stopped { break }
        await Task.yield()
    }

    #expect(store.streamState == .failed("Transient recovery failure 3"))
    #expect(store.recordingState == .stopped)
    #expect(pipeline.startRecordingCount == 1)
    #expect(pipeline.stopRecordingCount == 1)
    #expect(store.streamRecoveryMetrics.interruptionCount == 1)
    #expect(store.streamRecoveryMetrics.successfulRecoveryCount == 0)
    #expect(store.streamRecoveryMetrics.failedRecoveryCount == 1)
    #expect(store.streamRecoveryMetrics.cancelledRecoveryCount == 0)
}

@Test
@MainActor
func liveRTMPRecoveryCancellationRecordsCancellationAndNextSessionResetsMetrics() async {
    let pipeline = SessionRecoveryMediaPipeline()
    let store = StudioStore(
        mediaPipeline: pipeline,
        streamStartRetryPolicy: StreamStartRetryPolicy(maxAttempts: 3, backoffMilliseconds: [100, 100])
    )
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )

    store.startStream()
    await waitUntilStreamIsLive(store)

    pipeline.failSession("RTMP connection closed by the server.", recoveryStartFailures: 3)
    store.advanceDirector()
    #expect(store.isStreamConnecting)

    store.stopStream()
    await waitUntilStreamIsOffline(store)

    #expect(store.streamRecoveryMetrics.interruptionCount == 1)
    #expect(store.streamRecoveryMetrics.successfulRecoveryCount == 0)
    #expect(store.streamRecoveryMetrics.failedRecoveryCount == 0)
    #expect(store.streamRecoveryMetrics.cancelledRecoveryCount == 1)

    pipeline.failSession("", recoveryStartFailures: 0)
    store.startStream()
    await waitUntilStreamIsLive(store)

    #expect(store.streamRecoveryMetrics == StreamRecoveryMetrics())

    store.stopStream()
    await waitUntilStreamIsOffline(store)
}

@Test
@MainActor
func liveRTMPRecoveryEndsInTruthfulFailureAfterRetryBudget() async {
    let pipeline = SessionRecoveryMediaPipeline()
    let store = StudioStore(
        mediaPipeline: pipeline,
        streamStartRetryPolicy: StreamStartRetryPolicy(maxAttempts: 2, backoffMilliseconds: [1])
    )
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )

    store.startStream()
    await waitUntilStreamIsLive(store)
    pipeline.failSession("RTMP connection failed.", recoveryStartFailures: 3)
    store.advanceDirector()

    for _ in 0..<1_000 {
        if case .failed = store.streamState { break }
        await Task.yield()
    }

    #expect(store.streamState == .failed("Transient recovery failure 3"))
    #expect(pipeline.stopStreamCount == 1)
    #expect(pipeline.startStreamCount == 3)
    #expect(store.streamStartAttempt == 2)
    #expect(store.events.contains { $0.title == "Stream recovery failed" })
    #expect(!store.canStopStream)
}

@Test
@MainActor
func streamStartCancellationDoesNotRetry() async {
    let pipeline = RecoveringMediaPipeline()
    pipeline.errorToThrow = CancellationError()
    let store = StudioStore(
        mediaPipeline: pipeline,
        streamStartRetryPolicy: StreamStartRetryPolicy(maxAttempts: 3, backoffMilliseconds: [1, 1])
    )
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(pipeline.startCount == 1)
    #expect(store.streamStartAttempt == 1)
    #expect(!store.events.contains { $0.title == "Retrying RTMP Publish" })
}

@Test
@MainActor
func previewStreamStartDoesNotRetryFailures() async {
    let pipeline = FlakyStartMediaPipeline(failuresBeforeSuccess: 1, streamTransport: .preview)
    let store = StudioStore(
        mediaPipeline: pipeline,
        streamStartRetryPolicy: StreamStartRetryPolicy(maxAttempts: 3, backoffMilliseconds: [1, 1])
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.streamState == .failed("Transient start failure 1"))
    #expect(store.streamStartAttempt == 1)
    #expect(store.streamStartMaxAttempts == 1)
    #expect(pipeline.startCount == 1)
}

@Test
@MainActor
func cancelDuringRTMPRetryLeavesStreamOffline() async {
    let pipeline = FlakyStartMediaPipeline(failuresBeforeSuccess: 5)
    let store = StudioStore(
        mediaPipeline: pipeline,
        streamStartRetryPolicy: StreamStartRetryPolicy(maxAttempts: 3, backoffMilliseconds: [100, 100])
    )
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(20))
    store.stopStream()
    try? await Task.sleep(for: .milliseconds(80))

    #expect(store.streamState == .offline)
    #expect(!store.isLive)
    #expect(store.streamStartAttempt == 0)
    #expect(store.streamStartMaxAttempts == 1)
    #expect(pipeline.startCount == 1)
}

@Test
@MainActor
func stopStreamIsIdempotentWhilePipelineStops() async {
    let pipeline = DelayedStopMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)

    store.startStream()
    try? await Task.sleep(for: .milliseconds(20))

    #expect(store.streamState == .live)

    store.stopStream()

    #expect(store.isStreamStopping)
    #expect(!store.canStopStream)
    #expect(!store.canStartStream)
    #expect(store.streamStatusDetail == "Stopping stream")

    store.stopStream()
    try? await Task.sleep(for: .milliseconds(20))

    #expect(pipeline.stopCount == 1)

    await waitUntilStreamIsOffline(store)

    #expect(!store.isStreamStopping)
    #expect(store.streamState == .offline)
    #expect(store.canStartStream)
    #expect(pipeline.stopCount == 1)
    #expect(store.events.filter { $0.title == "Offline" }.count == 1)
}

@Test
@MainActor
func connectingStreamStartSuppressesDuplicateStartsAndDestinationEdits() async {
    let pipeline = DelayedStartMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)

    store.startStream()
    try? await Task.sleep(for: .milliseconds(10))

    #expect(store.isStreamConnecting)
    #expect(!store.canStartStream)
    #expect(store.canStopStream)
    #expect(!store.canEditDestination)

    store.startStream()
    store.setDestinationMode(.rtmp)
    store.destination = StreamDestination(
        name: "Edited while connecting",
        rtmpURL: "rtmps://live.example.com/app/sk_live_changed"
    )

    #expect(store.destination.mode == .preview)
    #expect(store.destination.name == "Preview Session")
    #expect(pipeline.startCount == 1)

    await waitUntilStreamIsLive(store)

    #expect(store.streamState == .live)
    #expect(!store.canStartStream)
    #expect(store.canStopStream)
    #expect(!store.canEditDestination)
    #expect(pipeline.startCount == 1)
}

@Test
@MainActor
func liveStreamRejectsDestinationMutation() async {
    let pipeline = DelayedStartMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)

    store.startStream()
    await waitUntilStreamIsLive(store)

    #expect(store.streamState == .live)
    #expect(!store.canEditDestination)

    store.destination = StreamDestination(
        name: "Edited while live",
        rtmpURL: "rtmps://live.example.com/app/sk_live_changed"
    )
    store.destination.name = "Renamed while live"
    store.setDestinationMode(.rtmp)

    #expect(store.destination.mode == .preview)
    #expect(store.destination.name == "Preview Session")
    #expect(store.destination.rtmpURL == "preview")
}

@Test
@MainActor
func connectingStreamStartSuppressesRecordingStart() async {
    let pipeline = DelayedStartMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)

    store.startStream()
    try? await Task.sleep(for: .milliseconds(10))

    #expect(store.isStreamConnecting)
    #expect(!store.canStartRecording)

    store.startRecording()

    #expect(pipeline.startRecordingCount == 0)

    await waitUntilStreamIsLive(store)

    #expect(store.streamState == .live)
    #expect(store.canStartRecording)
}

@Test
@MainActor
func cancelWhileConnectingIgnoresLateStreamStartCompletion() async {
    let pipeline = NonCancellableDelayedStartMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)

    store.startStream()
    try? await Task.sleep(for: .milliseconds(10))
    store.stopStream()
    try? await Task.sleep(for: .milliseconds(10))

    #expect(pipeline.stopCount == 1)

    try? await Task.sleep(for: .milliseconds(120))

    #expect(store.streamState == .offline)
    #expect(!store.isLive)
    #expect(store.canStartStream)
    #expect(store.canEditDestination)
    #expect(pipeline.startCount == 1)
    #expect(pipeline.stopCount >= 1)
}

@Test
@MainActor
func studioStoreSurfacesMediaPipelineTransportForRTMPDestination() async {
    let pipeline = ConfigurableMediaPipeline(streamTransport: .rtmpPublish)
    let store = StudioStore(mediaPipeline: pipeline)
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.streamTransport == .rtmpPublish)
}

@Test
@MainActor
func studioStoreRedactsDestinationSecretInStreamEvents() async {
    let pipeline = ConfigurableMediaPipeline(streamTransport: .endpointValidation)
    let store = StudioStore(mediaPipeline: pipeline)
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    let eventDetails = store.events.map(\.detail).joined(separator: "\n")
    #expect(eventDetails.contains("1 destination ready"))
    #expect(!eventDetails.contains("sk_live_secret"))
}

@Test
@MainActor
func startRecordingWithSetupWarningsEmitsWarningEvents() async {
    let pipeline = ConfigurableMediaPipeline()
    pipeline.captureSetupWarnings = [
        "System audio could not be attached; this recording will not include system audio.",
        "Microphone capture could not be attached; this recording will not include microphone audio."
    ]
    let store = StudioStore(mediaPipeline: pipeline)

    store.startRecording()
    try? await Task.sleep(for: .milliseconds(80))

    #expect(store.recordingState == .recording)
    #expect(store.events.contains {
        $0.kind == .warning
            && $0.title == "Recording degraded"
            && $0.detail == "System audio could not be attached; this recording will not include system audio."
    })
    #expect(store.events.contains {
        $0.kind == .warning
            && $0.title == "Recording degraded"
            && $0.detail == "Microphone capture could not be attached; this recording will not include microphone audio."
    })
}

@Test
@MainActor
func recordingFailureDetailOnHealthTickTransitionsToFailed() async {
    let pipeline = ConfigurableMediaPipeline()
    pipeline.currentHealth = StreamHealth(
        bitrateKbps: 0,
        droppedFrames: 0,
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
    pipeline.recordingFailureDetail = "Recording failed: disk full"
    try? await Task.sleep(for: .milliseconds(1_200))

    #expect(store.recordingState == .failed("Recording failed: disk full"))
    #expect(store.events.contains {
        $0.kind == .warning
            && $0.title == "Recording failed"
            && $0.detail == "Recording failed: disk full"
    })
    #expect(!store.events.contains {
        $0.title == "Recording stopped" && $0.detail == "Local archive closed."
    })
}

@Test
@MainActor
func recordingFailureDuringLiveStreamFailsRecordingOnly() async {
    let pipeline = ConfigurableMediaPipeline()
    pipeline.currentHealth = StreamHealth(
        bitrateKbps: 6_000,
        droppedFrames: 0,
        captureFPS: 30,
        audioLevel: 0.2,
        roundTripMs: 18
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        preferences: StudioPreferences(performanceMode: .adaptive)
    )
    store.directorMode = .auto

    store.startStream()
    try? await Task.sleep(for: .milliseconds(80))
    store.startRecording()
    try? await Task.sleep(for: .milliseconds(80))
    pipeline.recordingFailureDetail = "Recording failed: disk full while streaming"

    store.advanceDirector()
    try? await Task.sleep(for: .milliseconds(80))

    #expect(store.recordingState == .failed("Recording failed: disk full while streaming"))
    #expect(store.streamState.isLive)
    #expect(store.events.contains {
        $0.kind == .warning
            && $0.title == "Recording failed"
            && $0.detail == "Recording failed: disk full while streaming"
    })
    #expect(!store.events.contains {
        $0.title == "Recording stopped" && $0.detail == "Local archive closed."
    })
    #expect(!store.events.contains { $0.title == "Offline" })
}

@Test
@MainActor
func sharedCaptureFailureStopsRecordingBeforeStreamRecovery() async {
    let pipeline = SharedCaptureFailureMediaPipeline()
    let store = StudioStore(
        mediaPipeline: pipeline,
        preferences: StudioPreferences(recordWhileStreaming: true),
        streamStartRetryPolicy: StreamStartRetryPolicy(maxAttempts: 2, backoffMilliseconds: [1])
    )
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )

    store.startStream()
    await waitUntilStreamIsLive(store)
    await waitUntilRecordingIsActive(store)
    #expect(pipeline.transitions == ["startStream", "startRecording"])

    pipeline.recordingFailureDetail = "Shared camera capture failed while recording"
    pipeline.streamFailureDetail = "Shared camera capture failed while publishing"
    store.advanceDirector()

    for _ in 0..<100 {
        guard store.recordingState != .failed("Shared camera capture failed while recording") else { break }
        await Task.yield()
    }

    #expect(store.recordingState == .failed("Shared camera capture failed while recording"))
    #expect(store.streamState.isLive)
    #expect(pipeline.startStreamCount == 1)
    #expect(pipeline.transitions == ["startStream", "startRecording", "stopRecording"])
    #expect(store.events.contains {
        $0.kind == .warning
            && $0.title == "Recording failed"
            && $0.detail == "Shared camera capture failed while recording"
    })

    store.advanceDirector()
    for _ in 0..<100 {
        if case .failed = store.streamState, !store.isStreamStopping { break }
        await Task.yield()
    }

    #expect(store.recordingState == .failed("Shared camera capture failed while recording"))
    #expect(store.streamState == .failed("Shared camera capture failed while publishing"))
    #expect(pipeline.startStreamCount == 1)
    #expect(pipeline.transitions == ["startStream", "startRecording", "stopRecording", "stopStream"])
    #expect(store.events.contains {
        $0.kind == .warning
            && $0.title == "Recording failed"
            && $0.detail == "Shared camera capture failed while recording"
    })
    #expect(store.events.contains {
        $0.kind == .warning
            && $0.title == "Stream failed"
            && $0.detail == "Shared camera capture failed while publishing"
    })
    #expect(!store.events.contains { $0.title == "Stream recovered" })
}

@Test
@MainActor
func stopRecordingWithFailureDetailReportsFailedInsteadOfStopped() async {
    let pipeline = ConfigurableMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)

    store.startRecording()
    try? await Task.sleep(for: .milliseconds(80))
    pipeline.recordingFailureDetail = "Recording failed: writer closed"

    store.stopRecording()
    try? await Task.sleep(for: .milliseconds(80))

    #expect(store.recordingState == .failed("Recording failed: writer closed"))
    #expect(store.events.contains {
        $0.kind == .warning
            && $0.title == "Recording failed"
            && $0.detail == "Recording failed: writer closed"
    })
    #expect(!store.events.contains {
        $0.title == "Recording stopped" && $0.detail == "Local archive closed."
    })
}

@Test
@MainActor
func lifecycleShutdownWhenIdleStopsMonitoringWithoutTouchingMediaPipeline() async {
    let pipeline = LifecycleTrackingMediaPipeline()
    let signalProvider = MutableSignalProvider()
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(
                id: "microphone-1",
                kind: .microphone,
                name: "Studio Mic",
                permission: .granted
            )
        ],
        summary: "Microphone is ready."
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report),
        signalProvider: signalProvider
    )
    store.scanCaptureDevices()
    await waitUntilCaptureScanCompletes(store)
    store.startSourceMonitoring()
    #expect(signalProvider.startCount == 1)

    await store.shutdownForLifecycle()

    #expect(pipeline.stopStreamCount == 0)
    #expect(pipeline.stopRecordingCount == 0)
    #expect(signalProvider.stopCount == 1)
    #expect(store.streamState == .offline)
    #expect(store.recordingState == .stopped)
}

@Test
@MainActor
func lifecycleShutdownStopsActiveStreamAndDirector() async {
    let pipeline = LifecycleTrackingMediaPipeline()
    let signalProvider = ConfigurableSignalProvider()
    let store = StudioStore(
        mediaPipeline: pipeline,
        signalProvider: signalProvider,
        isDirectorRuntimeEnabled: true
    )
    store.startStream()
    await waitUntilStreamIsLive(store)
    #expect(store.streamState.isLive)
    #expect(signalProvider.startCount == 1)

    await store.shutdownForLifecycle()

    #expect(pipeline.stopStreamCount == 1)
    #expect(pipeline.stopRecordingCount == 0)
    #expect(signalProvider.stopCount == 1)
    #expect(store.streamState == .offline)
    #expect(store.recordingState == .stopped)
    #expect(!store.isStreamStopping)
}

@Test
@MainActor
func lifecycleShutdownStopsActiveRecording() async {
    let pipeline = LifecycleTrackingMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)
    store.startRecording()
    await waitUntilRecordingIsActive(store)
    #expect(store.recordingState == .recording)

    await store.shutdownForLifecycle()

    #expect(pipeline.stopStreamCount == 0)
    #expect(pipeline.stopRecordingCount == 1)
    #expect(store.streamState == .offline)
    #expect(store.recordingState == .stopped)
    #expect(!store.isRecordingStopping)
}

@Test
@MainActor
func lifecycleShutdownStopsStreamBeforeSharedRecording() async {
    let pipeline = LifecycleTrackingMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)
    store.startStream()
    await waitUntilStreamIsLive(store)
    store.startRecording()
    await waitUntilRecordingIsActive(store)
    #expect(store.streamState.isLive)
    #expect(store.recordingState == .recording)

    await store.shutdownForLifecycle()

    #expect(pipeline.transitions == [
        "startStream",
        "startRecording",
        "stopStream",
        "stopRecording"
    ])
    #expect(store.streamState == .offline)
    #expect(store.recordingState == .stopped)
}

@Test
@MainActor
func lifecycleShutdownCancelsInFlightStreamStartBeforeStoppingPipeline() async {
    let pipeline = LifecycleTrackingMediaPipeline()
    pipeline.suspendsStreamStart = true
    let store = StudioStore(mediaPipeline: pipeline)
    store.startStream()
    await pipeline.waitUntilStreamStartCalled()
    #expect(store.isStreamConnecting)

    await store.shutdownForLifecycle()

    #expect(pipeline.streamStartCancellationCount == 1)
    #expect(pipeline.stopStreamCount == 1)
    #expect(pipeline.transitions == ["startStream", "stopStream"])
    #expect(store.streamState == .offline)
    #expect(!store.isStreamStopping)
}

@Test
@MainActor
func lifecycleShutdownCancelsInFlightRecordingStartBeforeStoppingPipeline() async {
    let pipeline = LifecycleTrackingMediaPipeline()
    pipeline.suspendsRecordingStart = true
    let store = StudioStore(mediaPipeline: pipeline)
    store.startRecording()
    await pipeline.waitUntilRecordingStartCalled()
    #expect(store.recordingState == .starting)

    await store.shutdownForLifecycle()

    #expect(pipeline.recordingStartCancellationCount == 1)
    #expect(pipeline.stopRecordingCount == 1)
    #expect(pipeline.transitions == ["startRecording", "stopRecording"])
    #expect(store.recordingState == .stopped)
    #expect(!store.isRecordingStopping)
}

@Test
@MainActor
func concurrentLifecycleShutdownsAwaitOneReusableTeardown() async {
    let pipeline = LifecycleTrackingMediaPipeline()
    pipeline.holdsStreamStop = true
    let store = StudioStore(mediaPipeline: pipeline)
    store.startStream()
    await waitUntilStreamIsLive(store)

    var completedShutdownCount = 0
    let firstShutdown = Task { @MainActor in
        await store.shutdownForLifecycle()
        completedShutdownCount += 1
    }
    await pipeline.waitUntilStreamStopCalled()
    let secondShutdown = Task { @MainActor in
        await store.shutdownForLifecycle()
        completedShutdownCount += 1
    }
    await Task.yield()

    #expect(pipeline.stopStreamCount == 1)
    #expect(completedShutdownCount == 0)

    pipeline.finishStreamStop()
    await firstShutdown.value
    await secondShutdown.value
    await store.shutdownForLifecycle()

    #expect(completedShutdownCount == 2)
    #expect(pipeline.stopStreamCount == 1)
    #expect(pipeline.stopRecordingCount == 0)
    #expect(store.streamState == .offline)
    #expect(store.recordingState == .stopped)

    store.startStream()
    await waitUntilStreamIsLive(store)

    #expect(store.streamState.isLive)
    #expect(pipeline.startStreamCount == 2)

    pipeline.holdsStreamStop = false
    await store.shutdownForLifecycle()
}

@Test
@MainActor
func repeatedStreamLifecycleLeavesNoPendingOwnershipOrStopState() async {
    let pipeline = LifecycleTrackingMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)
    let cycleCount = 100

    for _ in 0..<cycleCount {
        store.startStream()
        await waitUntilStreamIsLive(store)
        #expect(store.streamState.isLive)

        store.stopStream()
        await waitUntilStreamIsOffline(store)
        #expect(store.streamState == .offline)
        #expect(!store.isStreamStopping)
    }

    #expect(pipeline.startStreamCount == cycleCount)
    #expect(pipeline.stopStreamCount == cycleCount)
    #expect(pipeline.transitions.count == cycleCount * 2)
    #expect(store.recordingState == .stopped)

    await store.shutdownForLifecycle()

    #expect(pipeline.stopStreamCount == cycleCount)
}

private final class SharedCaptureFailureMediaPipeline: MediaPipeline, @unchecked Sendable {
    let streamTransport: StreamTransportKind = .rtmpPublish
    var currentHealth: StreamHealth? = StreamHealth(
        bitrateKbps: 4_000,
        publishState: .publishing,
        captureFPS: 30,
        microphoneDeliveryState: .active
    )
    var recordingFailureDetail: String?
    var streamFailureDetail: String?
    private(set) var startStreamCount = 0
    private(set) var transitions: [String] = []

    func update(configuration: MediaPipelineConfiguration) {}

    func startStream(destinations: [StreamDestination]) async throws {
        startStreamCount += 1
        transitions.append("startStream")
    }

    func stopStream() async {
        transitions.append("stopStream")
        streamFailureDetail = nil
    }

    func startRecording() async throws -> URL {
        transitions.append("startRecording")
        return URL(fileURLWithPath: "/tmp/macstream-shared-capture-failure.mov")
    }

    func stopRecording() async {
        transitions.append("stopRecording")
    }
}
