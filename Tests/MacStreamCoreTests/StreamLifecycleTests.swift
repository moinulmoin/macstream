import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import Network
import Testing
@testable import MacStreamCore

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
    #expect(store.destination.rtmpURL == "rtmps://live.example.com/app/sk_live_secret")
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
    let store = StudioStore(mediaPipeline: pipeline)

    store.startStream()
    #expect(store.streamStatusDetail == "Starting local preview session")
    try? await Task.sleep(for: .milliseconds(50))
    #expect(store.streamStatusDetail == "Local preview running")

    store.stopStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )
    store.startStream()
    #expect(store.streamStatusDetail == "Connecting RTMP publisher (attempt 1/3)")
    try? await Task.sleep(for: .milliseconds(50))
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
    try? await Task.sleep(for: .milliseconds(80))

    #expect(store.streamState == .live)
    #expect(store.streamStartAttempt == 3)
    #expect(store.streamStartMaxAttempts == 3)
    #expect(pipeline.startCount == 3)
    #expect(store.events.contains { $0.title == "Retrying RTMP Publish" })
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

    try? await Task.sleep(for: .milliseconds(100))

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

    try? await Task.sleep(for: .milliseconds(100))

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
    try? await Task.sleep(for: .milliseconds(100))

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

    try? await Task.sleep(for: .milliseconds(100))

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
    #expect(eventDetails.contains("rtmps://live.example.com/app/****"))
    #expect(!eventDetails.contains("sk_live_secret"))
}
