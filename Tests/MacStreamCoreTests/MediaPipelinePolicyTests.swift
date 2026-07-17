import CoreGraphics
import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import Network
import Testing
@testable import MacStreamCore

@Test
func cameraCaptureHandoffWaitsForIdlePreviewTeardown() async throws {
    let handoff = CameraCaptureHandoff()
    let ownerID = UUID()
    handoff.claimIdlePreview(ownerID: ownerID)
    let clock = ContinuousClock()
    let startedAt = clock.now

    let waitTask = Task {
        try await handoff.waitForIdlePreviewRelease(
            timeout: .seconds(1),
            pollInterval: .milliseconds(5),
            settleDelay: .milliseconds(40)
        )
    }

    try await Task.sleep(for: .milliseconds(30))
    handoff.releaseIdlePreview(ownerID: ownerID)

    #expect(try await waitTask.value)
    #expect(startedAt.duration(to: clock.now) >= .milliseconds(60))
}

@Test
func cameraCaptureHandoffTimesOutWhenIdlePreviewDoesNotRelease() async throws {
    let handoff = CameraCaptureHandoff()
    let ownerID = UUID()
    handoff.claimIdlePreview(ownerID: ownerID)
    defer {
        handoff.releaseIdlePreview(ownerID: ownerID)
    }

    let released = try await handoff.waitForIdlePreviewRelease(
        timeout: .milliseconds(30),
        pollInterval: .milliseconds(5),
        settleDelay: .zero
    )

    #expect(!released)
}

@Test
func cameraCapturePrefersNativeBiPlanarPixelFormats() {
    #expect(SystemMediaPipeline.preferredCameraPixelFormat(available: [
        kCVPixelFormatType_32BGRA,
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    ]) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
    #expect(SystemMediaPipeline.preferredCameraPixelFormat(available: [
        kCVPixelFormatType_32BGRA,
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    ]) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
    #expect(SystemMediaPipeline.preferredCameraPixelFormat(available: [
        kCVPixelFormatType_32BGRA
    ]) == kCVPixelFormatType_32BGRA)
}

@Test
func microphoneWriterSettingsSanitizeDeviceRecommendationAndUseStereoFallback() {
    let recommended: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 192_000,
        "unsupported-device-setting": true
    ]
    let resolved = SystemMediaPipeline.microphoneWriterSettings(recommended: recommended)

    #expect(resolved[AVFormatIDKey] as? AudioFormatID == kAudioFormatMPEG4AAC)
    #expect(resolved[AVSampleRateKey] as? Int == 44_100)
    #expect(resolved[AVNumberOfChannelsKey] as? Int == 2)
    #expect(resolved[AVEncoderBitRateKey] as? Int == 192_000)
    #expect(resolved["unsupported-device-setting"] == nil)

    let fallback = SystemMediaPipeline.microphoneWriterSettings(
        recommended: nil,
        fallbackSampleRate: 50_000,
        fallbackChannels: 1
    )
    #expect(fallback[AVSampleRateKey] as? Int == 48_000)
    #expect(fallback[AVNumberOfChannelsKey] as? Int == 1)
    #expect(fallback[AVEncoderBitRateKey] as? Int == 128_000)
}

@Test
func cameraDrivenCompositionHonorsOutputCadence() {
    let start = CMTime(seconds: 10, preferredTimescale: 600)
    let oneFrameLater = CMTimeAdd(start, CMTime(value: 1, timescale: 60))
    let halfFrameLater = CMTimeAdd(start, CMTime(value: 1, timescale: 120))

    #expect(SystemMediaPipeline.shouldEmitCameraDrivenComposedFrame(
        start,
        after: nil,
        framesPerSecond: 60
    ))
    #expect(SystemMediaPipeline.shouldEmitCameraDrivenComposedFrame(
        oneFrameLater,
        after: start,
        framesPerSecond: 60
    ))
    #expect(!SystemMediaPipeline.shouldEmitCameraDrivenComposedFrame(
        halfFrameLater,
        after: start,
        framesPerSecond: 60
    ))
    #expect(!SystemMediaPipeline.shouldEmitCameraDrivenComposedFrame(
        start,
        after: oneFrameLater,
        framesPerSecond: 60
    ))
    #expect(SystemMediaPipeline.isNewerComposedPresentationTime(
        oneFrameLater,
        after: start
    ))
    #expect(!SystemMediaPipeline.isNewerComposedPresentationTime(
        start,
        after: oneFrameLater
    ))
}

@Test
func recordingAudioDropsPrerollAndNonMonotonicSamples() {
    let sessionStart = CMTime(seconds: 10, preferredTimescale: 48_000)
    let preroll = CMTime(seconds: 9.99, preferredTimescale: 48_000)
    let firstAccepted = CMTime(seconds: 10.01, preferredTimescale: 48_000)
    let nextAccepted = CMTime(seconds: 10.02, preferredTimescale: 48_000)

    #expect(!SystemMediaPipeline.shouldAppendRecordingAudioSample(
        preroll,
        sessionStartTime: sessionStart,
        previousPresentationTime: nil
    ))
    #expect(SystemMediaPipeline.shouldAppendRecordingAudioSample(
        firstAccepted,
        sessionStartTime: sessionStart,
        previousPresentationTime: nil
    ))
    #expect(!SystemMediaPipeline.shouldAppendRecordingAudioSample(
        firstAccepted,
        sessionStartTime: sessionStart,
        previousPresentationTime: firstAccepted
    ))
    #expect(SystemMediaPipeline.shouldAppendRecordingAudioSample(
        nextAccepted,
        sessionStartTime: sessionStart,
        previousPresentationTime: firstAccepted
    ))
}

@Test
func microphoneCaptureNormalizesDeviceAudioToInterleavedPCM() {
    let settings = SystemMediaPipeline.microphoneCaptureSettings(
        sampleRate: 48_000,
        channels: 4
    )

    #expect(settings[AVFormatIDKey] as? AudioFormatID == kAudioFormatLinearPCM)
    #expect(settings[AVSampleRateKey] as? Double == 48_000)
    #expect(settings[AVNumberOfChannelsKey] as? Int == 2)
    #expect(settings[AVLinearPCMBitDepthKey] as? Int == 16)
    #expect(settings[AVLinearPCMIsFloatKey] as? Bool == false)
    #expect(settings[AVLinearPCMIsBigEndianKey] as? Bool == false)
    #expect(settings[AVLinearPCMIsNonInterleaved] as? Bool == false)

    let fallback = SystemMediaPipeline.microphoneCaptureSettings(
        sampleRate: .nan,
        channels: 0
    )
    #expect(fallback[AVSampleRateKey] as? Double == 48_000)
    #expect(fallback[AVNumberOfChannelsKey] as? Int == 1)
}

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
func mediaPipelineOnlyReportsHandshakingWhenPublisherExists() {
    #expect(SystemMediaPipeline.initialPublishState(
        hasPublisher: true,
        supportsPublishStatus: true
    ) == .handshaking)
    #expect(SystemMediaPipeline.initialPublishState(
        hasPublisher: true,
        supportsPublishStatus: false
    ) == .disconnected)
    #expect(SystemMediaPipeline.initialPublishState(
        hasPublisher: false,
        supportsPublishStatus: true
    ) == .disconnected)
}

@Test
func cameraFirstFrameRecoveryOnlyContinuesForCurrentRequiredCapture() {
    #expect(SystemMediaPipeline.shouldContinueCameraFirstFrameRecovery(
        requiresCameraCapture: true,
        hasCurrentSession: true,
        hasDeliveredFrame: false,
        generationMatches: true
    ))
    #expect(!SystemMediaPipeline.shouldContinueCameraFirstFrameRecovery(
        requiresCameraCapture: false,
        hasCurrentSession: true,
        hasDeliveredFrame: false,
        generationMatches: true
    ))
    #expect(!SystemMediaPipeline.shouldContinueCameraFirstFrameRecovery(
        requiresCameraCapture: true,
        hasCurrentSession: false,
        hasDeliveredFrame: false,
        generationMatches: true
    ))
    #expect(!SystemMediaPipeline.shouldContinueCameraFirstFrameRecovery(
        requiresCameraCapture: true,
        hasCurrentSession: true,
        hasDeliveredFrame: true,
        generationMatches: true
    ))
    #expect(!SystemMediaPipeline.shouldContinueCameraFirstFrameRecovery(
        requiresCameraCapture: true,
        hasCurrentSession: true,
        hasDeliveredFrame: false,
        generationMatches: false
    ))
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
func audioLevelMeterSmoothsNormalizedMicrophoneSamples() {
    var state = AudioLevelMeterState()

    let loud = state.record(normalizedLevel: 1)
    let quiet = state.record(normalizedLevel: 0)

    #expect(abs(loud.level - 0.3) < 0.000_001)
    #expect(loud.isSpeaking)
    #expect(abs(quiet.level - 0.21) < 0.000_001)
    #expect(!quiet.isSpeaking)
}

@Test
func audioLevelMeterResetClearsStaleLevelAndSpeakingState() {
    var state = AudioLevelMeterState()
    _ = state.record(normalizedLevel: 1)

    state.reset()

    #expect(state.measurement.level == 0)
    #expect(!state.measurement.isSpeaking)
}

@Test
func systemMediaPipelineRecordsRecordingSystemAudioCallbacksBeforeWriterSessionStarts() {
    #expect(SystemMediaPipeline.shouldRecordSystemAudioCallback(
        isRecordingStream: true,
        hasWriter: true,
        processesSystemAudio: true
    ))
    #expect(!SystemMediaPipeline.shouldRecordSystemAudioCallback(
        isRecordingStream: false,
        hasWriter: true,
        processesSystemAudio: true
    ))
    #expect(!SystemMediaPipeline.shouldRecordSystemAudioCallback(
        isRecordingStream: true,
        hasWriter: false,
        processesSystemAudio: true
    ))
    #expect(!SystemMediaPipeline.shouldRecordSystemAudioCallback(
        isRecordingStream: true,
        hasWriter: true,
        processesSystemAudio: false
    ))
}

@Test
func streamHealthRoundTripsAudioDeliveryFields() throws {
    let health = StreamHealth(
        audioDeliveryState: .stalled,
        microphoneDeliveryState: .active,
        rtmpAudioAppendRejections: 7,
        rtmpPendingAppends: 2,
        rtmpAppendCapacity: 3,
        avDriftMilliseconds: -42,
        maxAbsoluteAVDriftMilliseconds: 87
    )

    let decoded = try JSONDecoder().decode(
        StreamHealth.self,
        from: JSONEncoder().encode(health)
    )

    #expect(decoded == health)
}

@Test
func avTimingHealthTracksSignedAndMaximumAcceptedSampleDrift() {
    var tracker = AVTimingHealthTracker()

    tracker.recordVideoPresentationTime(CMTime(seconds: 10, preferredTimescale: 600))
    tracker.recordAudioPresentationTime(CMTime(seconds: 10.05, preferredTimescale: 600))

    #expect(tracker.driftMilliseconds == 50)
    #expect(tracker.maxAbsoluteDriftMilliseconds == 50)

    tracker.recordAudioPresentationTime(CMTime(seconds: 9.92, preferredTimescale: 600))

    #expect(tracker.driftMilliseconds == -80)
    #expect(tracker.maxAbsoluteDriftMilliseconds == 80)
}

@Test
func avTimingHealthResetClearsPreviousSessionTiming() {
    var tracker = AVTimingHealthTracker()
    tracker.recordVideoPresentationTime(CMTime(seconds: 5, preferredTimescale: 600))
    tracker.recordAudioPresentationTime(CMTime(seconds: 5.2, preferredTimescale: 600))

    tracker.reset()
    tracker.recordAudioPresentationTime(CMTime(seconds: 20, preferredTimescale: 600))

    #expect(tracker.driftMilliseconds == 0)
    #expect(tracker.maxAbsoluteDriftMilliseconds == 0)
}

@Test
func audioDeliveryHealthTransitionsFromAwaitingToStalledAtBoundary() {
    var tracker = AudioDeliveryHealthTracker()
    tracker.reset(
        expectsSystemAudio: true,
        expectsMicrophone: false,
        at: 1_000_000_000
    )

    #expect(tracker.state(at: 1_000_000_000) == .awaiting)
    #expect(tracker.state(at: 2_999_999_999) == .awaiting)
    #expect(tracker.state(at: 3_000_000_000) == .stalled)
}

@Test
func audioDeliveryHealthRequiresEveryExpectedSourceToRemainFresh() {
    var tracker = AudioDeliveryHealthTracker()
    tracker.reset(
        expectsSystemAudio: true,
        expectsMicrophone: true,
        at: 10_000_000_000
    )

    tracker.recordSystemAudioCallback(at: 10_500_000_000)
    #expect(tracker.state(at: 10_500_000_000) == .awaiting)

    tracker.recordMicrophoneCallback(at: 10_750_000_000)
    #expect(tracker.state(at: 10_750_000_000) == .active)
    #expect(tracker.state(at: 12_499_999_999) == .active)
    #expect(tracker.state(at: 12_500_000_000) == .stalled)
}

@Test
func audioDeliveryHealthReportsMicrophoneIndependentlyFromSystemAudio() {
    var tracker = AudioDeliveryHealthTracker()
    tracker.reset(
        expectsSystemAudio: true,
        expectsMicrophone: true,
        at: 1_000_000_000
    )
    tracker.recordMicrophoneCallback(at: 3_000_000_000)

    #expect(tracker.state(at: 3_000_000_000) == .stalled)
    #expect(tracker.microphoneState(at: 3_000_000_000) == .active)
}

@Test
func audioDeliveryHealthResetStartsANewCaptureLifecycle() {
    var tracker = AudioDeliveryHealthTracker()
    tracker.reset(
        expectsSystemAudio: true,
        expectsMicrophone: false,
        at: 1_000
    )
    tracker.recordSystemAudioCallback(at: 2_000)
    tracker.recordRTMPAudioAppendResult(wasAccepted: false)

    tracker.reset(
        expectsSystemAudio: false,
        expectsMicrophone: true,
        at: 3_000
    )
    tracker.recordSystemAudioCallback(at: 3_500)

    #expect(tracker.state(at: 3_500) == .awaiting)
    #expect(tracker.rtmpAudioAppendRejections == 0)

    tracker.recordMicrophoneCallback(at: 4_000)
    #expect(tracker.state(at: 4_000) == .active)
}

@Test
func audioDeliveryHealthCountsRepeatedRTMPAppendRejections() {
    var tracker = AudioDeliveryHealthTracker()
    tracker.reset(
        expectsSystemAudio: true,
        expectsMicrophone: false,
        at: 0
    )

    for _ in 0..<50_000 {
        tracker.recordRTMPAudioAppendResult(wasAccepted: false)
    }
    tracker.recordRTMPAudioAppendResult(wasAccepted: true)

    #expect(tracker.rtmpAudioAppendRejections == 50_000)
}

@Test
func systemMediaPipelinePlansPublishingAudioTracks() {
    var plan = SystemMediaPipeline.publishingAudioTrackPlan(capturesSystemAudio: true, capturesMicrophone: true)
    #expect(plan.systemAudio == 0)
    #expect(plan.microphone == 1)
    #expect(plan.mainTrack == 0)

    plan = SystemMediaPipeline.publishingAudioTrackPlan(capturesSystemAudio: false, capturesMicrophone: true)
    #expect(plan.systemAudio == nil)
    #expect(plan.microphone == 0)
    #expect(plan.mainTrack == 0)

    plan = SystemMediaPipeline.publishingAudioTrackPlan(capturesSystemAudio: true, capturesMicrophone: false)
    #expect(plan.systemAudio == 0)
    #expect(plan.microphone == nil)
    #expect(plan.mainTrack == 0)

    plan = SystemMediaPipeline.publishingAudioTrackPlan(capturesSystemAudio: false, capturesMicrophone: false)
    #expect(plan.systemAudio == nil)
    #expect(plan.microphone == nil)
    #expect(plan.mainTrack == 0)
}

@Test
func systemMediaPipelineClampsPublishingBitrateToPlatformSafeCeiling() {
    let fullHD = MediaPipelineConfiguration(maxVideoWidth: 1_920, framesPerSecond: 30, videoBitrate: 8_000_000)
    #expect(SystemMediaPipeline.publishingVideoBitrateCeiling(configuration: fullHD) == 4_000_000)
    #expect(SystemMediaPipeline.publishingVideoBitrate(configuration: fullHD) == 4_000_000)

    let hd = MediaPipelineConfiguration(maxVideoWidth: 1_280, framesPerSecond: 30, videoBitrate: 8_000_000)
    #expect(SystemMediaPipeline.publishingVideoBitrateCeiling(configuration: hd) == 2_500_000)
    #expect(SystemMediaPipeline.publishingVideoBitrate(configuration: hd) == 2_500_000)

    let hdAtLowerFrameRate = MediaPipelineConfiguration(maxVideoWidth: 1_280, framesPerSecond: 24, videoBitrate: 8_000_000)
    #expect(SystemMediaPipeline.publishingVideoBitrateCeiling(configuration: hdAtLowerFrameRate) == 2_000_000)
    #expect(SystemMediaPipeline.publishingVideoBitrate(configuration: hdAtLowerFrameRate) == 2_000_000)

    let tiny = MediaPipelineConfiguration(maxVideoWidth: 320, framesPerSecond: 30, videoBitrate: 8_000_000)
    #expect(SystemMediaPipeline.publishingVideoBitrateCeiling(configuration: tiny) == 625_000)
    #expect(SystemMediaPipeline.publishingVideoBitrate(configuration: tiny) == 625_000)
}

@Test
func systemMediaPipelinePublishingBitrateLeavesAlreadyLowConfigurationsUntouched() {
    let lowBitrate = MediaPipelineConfiguration(maxVideoWidth: 1_920, framesPerSecond: 30, videoBitrate: 2_000_000)

    #expect(SystemMediaPipeline.publishingVideoBitrateCeiling(configuration: lowBitrate) == 4_000_000)
    #expect(SystemMediaPipeline.publishingVideoBitrate(configuration: lowBitrate) == 2_000_000)
}

@Test
func systemMediaPipelinePublishingAudioTrackPlanHonorsZeroLevels() {
    var configuration = MediaPipelineConfiguration(capturesSystemAudio: false, capturesMicrophone: true)
    var plan = SystemMediaPipeline.publishingAudioTrackPlan(configuration: configuration)
    #expect(plan.systemAudio == nil)
    #expect(plan.microphone == 0)
    #expect(plan.mainTrack == 0)

    configuration = MediaPipelineConfiguration(capturesSystemAudio: true, capturesMicrophone: true)
    configuration.systemAudioLevel = 0
    plan = SystemMediaPipeline.publishingAudioTrackPlan(configuration: configuration)
    #expect(plan.systemAudio == nil)
    #expect(plan.microphone == 0)
    #expect(plan.mainTrack == 0)

    configuration.systemAudioLevel = 1
    configuration.microphoneLevel = 0
    plan = SystemMediaPipeline.publishingAudioTrackPlan(configuration: configuration)
    #expect(plan.systemAudio == 0)
    #expect(plan.microphone == nil)
    #expect(plan.mainTrack == 0)

    configuration.systemAudioLevel = 0
    plan = SystemMediaPipeline.publishingAudioTrackPlan(configuration: configuration)
    #expect(plan.systemAudio == nil)
    #expect(plan.microphone == nil)
    #expect(plan.mainTrack == 0)
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
    #expect(SystemMediaPipeline.shouldPublishCompositedVideoSample(sceneKind: .screenOnly))
    #expect(!SystemMediaPipeline.shouldPublishCompositedVideoSample(sceneKind: .face))
    #expect(!SystemMediaPipeline.shouldPublishCompositedVideoSample(sceneKind: .brb))
    #expect(SystemMediaPipeline.requiresCameraCapture(sceneKind: .screenAndFace))
    #expect(!SystemMediaPipeline.requiresCameraCapture(sceneKind: .screenOnly))
}

@Test
func rtmpPublisherStatusEventsMapToPublishStateAndFailures() {
    let connected = RTMPPublisherEvent.connectionStatus(code: "NetConnection.Connect.Success", level: "status")
    let publishing = RTMPPublisherEvent.streamStatus(code: "NetStream.Publish.Start", level: "status")
    let badName = RTMPPublisherEvent.streamStatus(code: "NetStream.Publish.BadName", level: "error")
    let closed = RTMPPublisherEvent.connectionStatus(code: "NetConnection.Connect.Closed", level: "status")
    let failed = RTMPPublisherEvent.connectionStatus(code: "NetConnection.Connect.Failed", level: "error")
    let unpublished = RTMPPublisherEvent.streamStatus(code: "NetStream.Unpublish.Success", level: "status")

    #expect(connected.publishState == .handshaking)
    #expect(publishing.publishState == .publishing)
    #expect(badName.publishState == .disconnected)
    #expect(closed.publishState == .disconnected)
    #expect(failed.publishState == .disconnected)
    #expect(unpublished.publishState == .disconnected)
    #expect(publishing.failureReason == nil)
    #expect(badName.failureReason != nil)
    #expect(closed.failureReason != nil)
    #expect(failed.failureReason != nil)
    #expect(unpublished.failureReason != nil)
}

@Test
func rtmpPublisherEventsAreAcceptedOnlyForActiveOrConnectingPublisher() {
    #expect(SystemMediaPipeline.shouldAcceptRTMPPublisherEvent(
        isCurrentPublisher: true,
        isObservedConnectingPublisher: false
    ))
    #expect(SystemMediaPipeline.shouldAcceptRTMPPublisherEvent(
        isCurrentPublisher: false,
        isObservedConnectingPublisher: true
    ))
    #expect(!SystemMediaPipeline.shouldAcceptRTMPPublisherEvent(
        isCurrentPublisher: false,
        isObservedConnectingPublisher: false
    ))
}

@Test
func rtmpByteDeltaComputesOutboundThroughput() {
    #expect(SystemMediaPipeline.outboundBytesPerSecond(byteDelta: 3_000, elapsed: 1.5) == 2_000)
    #expect(SystemMediaPipeline.outboundBitrateKbps(bytesPerSecond: 125_000) == 1_000)
    #expect(SystemMediaPipeline.outboundBytesPerSecond(byteDelta: 0, elapsed: 1) == 0)
    #expect(SystemMediaPipeline.outboundBytesPerSecond(byteDelta: 100, elapsed: 0) == 0)
    #expect(SystemMediaPipeline.outboundBitrateKbps(bytesPerSecond: 0) == 0)
}

@Test
func microphonePermissionGrantStartsOnlyWhenSamplingIsStillRequested() {
    #expect(MicrophonePermissionStartPolicy.shouldStartCapture(isStartRequested: true, isPermissionGranted: true))
    #expect(!MicrophonePermissionStartPolicy.shouldStartCapture(isStartRequested: false, isPermissionGranted: true))
    #expect(!MicrophonePermissionStartPolicy.shouldStartCapture(isStartRequested: true, isPermissionGranted: false))
    #expect(!MicrophonePermissionStartPolicy.shouldStartCapture(isStartRequested: false, isPermissionGranted: false))
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
func systemMediaPipelineReportsUnexpectedRecordingCaptureStopAsRecordingFailure() {
    let plan = SystemMediaPipeline.screenCaptureInterruptionPlan(
        isRecordingStream: true,
        isPublishingStream: false,
        publishingMode: .none
    )

    #expect(
        plan.recordingFailureDetail(errorDescription: "display removed")
            == "Screen capture stopped unexpectedly while recording: display removed"
    )
    #expect(plan.streamFailureDetail(errorDescription: "display removed") == nil)
}

@Test
func systemMediaPipelineReportsUnexpectedPublishingCaptureStopAsStreamFailure() {
    let plan = SystemMediaPipeline.screenCaptureInterruptionPlan(
        isRecordingStream: false,
        isPublishingStream: true,
        publishingMode: .dedicated
    )

    #expect(plan.recordingFailureDetail(errorDescription: "display removed") == nil)
    #expect(
        plan.streamFailureDetail(errorDescription: "display removed")
            == "Screen capture stopped unexpectedly while publishing: display removed"
    )
}

@Test
func systemMediaPipelineReportsSharedCaptureStopToRecordingAndPublishing() {
    let plan = SystemMediaPipeline.screenCaptureInterruptionPlan(
        isRecordingStream: true,
        isPublishingStream: false,
        publishingMode: .recordingOwned
    )

    #expect(plan.recordingFailureDetail(errorDescription: "capture interrupted") != nil)
    #expect(plan.streamFailureDetail(errorDescription: "capture interrupted") != nil)
}

@Test
func systemMediaPipelineIgnoresCaptureStopAfterNormalTeardown() {
    let plan = SystemMediaPipeline.screenCaptureInterruptionPlan(
        isRecordingStream: false,
        isPublishingStream: false,
        publishingMode: .none
    )

    #expect(plan.recordingFailureDetail(errorDescription: "capture stopped") == nil)
    #expect(plan.streamFailureDetail(errorDescription: "capture stopped") == nil)
}

@Test
func systemMediaPipelineReportsZeroCaptureFPSAtStaleBoundary() {
    #expect(StreamHealth().captureFPS == 0)
    #expect(SystemMediaPipeline.captureFPSStaleInterval == 2)
    #expect(SystemMediaPipeline.reportedCaptureFPS(sampledFPS: 30, frameAge: nil) == 0)
    #expect(SystemMediaPipeline.reportedCaptureFPS(sampledFPS: 30, frameAge: 1.999) == 30)
    #expect(SystemMediaPipeline.reportedCaptureFPS(sampledFPS: 30, frameAge: 2) == 0)
}

@Test
func systemMediaPipelineUsesMonotonicElapsedTimeForCaptureHealth() {
    #expect(SystemMediaPipeline.elapsedSeconds(from: 1_000_000_000, to: 2_500_000_000) == 1.5)
    #expect(SystemMediaPipeline.elapsedSeconds(from: 2, to: 1) == nil)
}

@Test
func systemMediaPipelineCapsPublishingCaptureFPSAtRTMPTarget() {
    let responsive = MediaPipelineConfiguration(maxVideoWidth: 1_920, framesPerSecond: 60, queueDepth: 5)
    let capped = SystemMediaPipeline.publishingCaptureMediaConfiguration(for: responsive)

    #expect(capped.framesPerSecond == 30)

    let geometry = MediaCaptureGeometry(sourceWidth: 3_024, sourceHeight: 1_964, maxVideoWidth: 1_920)
    let streamConfiguration = SystemMediaPipeline.publishingStreamConfiguration(
        geometry: geometry,
        mediaConfiguration: responsive
    )
    #expect(streamConfiguration.minimumFrameInterval == CMTime(value: 1, timescale: 30))

    let efficiency = MediaPipelineConfiguration(maxVideoWidth: 1_280, framesPerSecond: 24, queueDepth: 3)
    #expect(SystemMediaPipeline.publishingCaptureMediaConfiguration(for: efficiency).framesPerSecond == 24)
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
func systemMediaPipelineSkipsStreamReconfigurationForOutputOnlyChanges() {
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
    let cameraEnhancementOnly = MediaPipelineConfiguration(
        maxVideoWidth: 1_920,
        framesPerSecond: 30,
        videoBitrate: 8_000_000,
        queueDepth: 5,
        capturesSystemAudio: true,
        capturesMicrophone: true,
        systemAudioLevel: 1,
        microphoneLevel: 1,
        cameraEnhancements: CameraEnhancementSettings(usesAutoLight: true, autoLightAmount: 0.8)
    )
    let sceneOnly = MediaPipelineConfiguration(
        maxVideoWidth: 1_920,
        framesPerSecond: 30,
        videoBitrate: 8_000_000,
        queueDepth: 5,
        sceneKind: .screenAndFace,
        capturesSystemAudio: true,
        capturesMicrophone: true,
        systemAudioLevel: 1,
        microphoneLevel: 1
    )
    let layoutOnly = MediaPipelineConfiguration(
        maxVideoWidth: 1_920,
        framesPerSecond: 30,
        videoBitrate: 8_000_000,
        queueDepth: 5,
        capturesSystemAudio: true,
        capturesMicrophone: true,
        systemAudioLevel: 1,
        microphoneLevel: 1,
        layoutSettings: StudioLayoutSettings(preset: .screen70Webcam30, canvasPadding: 0.08)
    )

    #expect(!SystemMediaPipeline.shouldUpdateActiveStreamConfiguration(from: baseline, to: levelOnly))
    #expect(!SystemMediaPipeline.shouldUpdateActiveStreamConfiguration(from: baseline, to: microphoneCaptureOnly))
    #expect(!SystemMediaPipeline.shouldUpdateActiveStreamConfiguration(from: baseline, to: cameraEnhancementOnly))
    #expect(!SystemMediaPipeline.shouldUpdateActiveStreamConfiguration(from: baseline, to: sceneOnly))
    #expect(!SystemMediaPipeline.shouldUpdateActiveStreamConfiguration(from: baseline, to: layoutOnly))
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
    #expect(SystemMediaPipeline.shouldUpdateActiveStreamConfiguration(from: baseline, to: lowerVideoCost))
    #expect(SystemMediaPipeline.shouldUpdateActiveStreamConfiguration(from: baseline, to: withoutSystemAudio))
    #expect(SystemMediaPipeline.shouldUpdateActiveStreamConfiguration(from: baseline, to: targetChanged))
}

@Test
func videoCanvasRenderPlanUsesPictureInPictureGeometry() {
    let outputSize = CGSize(width: 1_920, height: 1_080)
    let settings = StudioLayoutSettings(
        preset: .pictureInPicture,
        canvasPadding: 0.04,
        screenZoom: 1.2,
        webcamZoom: 0.9,
        sourceCornerRadius: 0.025
    )
    let plan = VideoCanvasRenderPlan.make(
        outputSize: outputSize,
        layoutSettings: settings
    )
    let layout = StudioCanvasLayout(size: outputSize, settings: settings)

    #expect(plan.mode == .pictureInPicture)
    #expect(plan.screenRect == layout.contentRect.integral)
    #expect(plan.cameraRect == layout.pictureInPictureRect.integral)
    #expect(plan.screenZoom == 1.2)
    #expect(plan.cameraZoom == 0.9)
    #expect(plan.screenViewport == settings.screenViewport)
    #expect(plan.cameraViewport == settings.webcamViewport)
    #expect(plan.sourceCornerRadius == layout.sourceCornerRadius)
    #expect(plan.backgroundDescriptor == .color(red: 0, green: 0, blue: 0, alpha: 1))
}

@Test
func videoCanvasRenderPlanUsesSplitGeometry() {
    let outputSize = CGSize(width: 1_280, height: 720)
    let settings = StudioLayoutSettings(
        preset: .screen70Webcam30,
        background: .color(StudioRGBAColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.6)),
        canvasPadding: 0.08,
        screenViewport: StudioSourceViewportSettings(zoom: 0.85, panX: 0.25, panY: -0.5),
        webcamViewport: StudioSourceViewportSettings(zoom: 1.4, panX: -0.75, panY: 0.5),
        sourceCornerRadius: 0.05
    )
    let plan = VideoCanvasRenderPlan.make(
        outputSize: outputSize,
        layoutSettings: settings
    )
    let layout = StudioCanvasLayout(size: outputSize, settings: settings)

    #expect(plan.mode == .split)
    #expect(plan.screenRect == layout.splitScreenRect.integral)
    #expect(plan.cameraRect == layout.splitWebcamRect.integral)
    #expect(plan.screenZoom == 0.85)
    #expect(plan.cameraZoom == 1.4)
    #expect(plan.screenViewport == StudioSourceViewportSettings(zoom: 0.85, panX: 0.25, panY: -0.5))
    #expect(plan.cameraViewport == StudioSourceViewportSettings(zoom: 1.4, panX: -0.75, panY: 0.5))
    #expect(plan.sourceCornerRadius == layout.sourceCornerRadius)
    #expect(plan.backgroundDescriptor == .color(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.6))
}

@Test
func videoCanvasRenderPlanUsesCanvasGeometryWithoutCameraForScreenOnly() {
    let outputSize = CGSize(width: 1_920, height: 1_080)
    let settings = StudioLayoutSettings(
        preset: .screen70Webcam30,
        backgroundStyle: .warm,
        canvasPadding: 0.08,
        screenZoom: 1.25,
        sourceCornerRadius: 0.03
    )
    let plan = VideoCanvasRenderPlan.make(
        outputSize: outputSize,
        layoutSettings: settings,
        sceneKind: .screenOnly
    )
    let layout = StudioCanvasLayout(size: outputSize, settings: settings)

    #expect(plan.mode == .screenOnly)
    #expect(plan.screenRect == layout.contentRect.integral)
    #expect(plan.cameraRect == .zero)
    #expect(plan.screenZoom == 1.25)
    #expect(plan.sourceCornerRadius == layout.sourceCornerRadius)
    #expect(plan.backgroundDescriptor == .color(red: 0.14, green: 0.10, blue: 0.06, alpha: 1))
}

@Test
func systemMediaPipelineUsesFixedWidescreenOutputDimensions() {
    #expect(SystemMediaPipeline.outputVideoSize(
        for: MediaPipelineConfiguration(maxVideoWidth: 1_280)
    ) == (width: 1_280, height: 720))
    #expect(SystemMediaPipeline.outputVideoSize(
        for: MediaPipelineConfiguration(maxVideoWidth: 3_840)
    ) == (width: 3_840, height: 2_160))
}

@Test
func videoCanvasSourceTransformBoundsPanWithoutExposingGaps() {
    let sourceExtent = CGRect(x: 0, y: 0, width: 100, height: 100)
    let targetRect = CGRect(x: 0, y: 0, width: 100, height: 100)
    let transform = VideoCanvasRenderPlan.sourceTransform(
        sourceExtent: sourceExtent,
        targetRect: targetRect,
        viewport: StudioSourceViewportSettings(zoom: 2, panX: 1, panY: 1)
    )
    let transformedExtent = sourceExtent.applying(transform)

    #expect(transformedExtent.minX <= targetRect.minX)
    #expect(transformedExtent.maxX >= targetRect.maxX)
    #expect(transformedExtent.minY <= targetRect.minY)
    #expect(transformedExtent.maxY >= targetRect.maxY)
    #expect(transform.tx == -100)
    #expect(transform.ty == 0)
}

@Test
func videoCanvasSourceTransformPreservesZoomOutForMoreSourceContext() {
    let sourceExtent = CGRect(x: 0, y: 0, width: 100, height: 100)
    let targetRect = CGRect(x: 0, y: 0, width: 100, height: 100)
    let transform = VideoCanvasRenderPlan.sourceTransform(
        sourceExtent: sourceExtent,
        targetRect: targetRect,
        viewport: StudioSourceViewportSettings(zoom: 0.75, panX: 5, panY: -.infinity)
    )
    let transformedExtent = sourceExtent.applying(transform)

    #expect(transformedExtent == CGRect(x: 12.5, y: 12.5, width: 75, height: 75))
    #expect(transform.a == 0.75)
    #expect(transform.d == 0.75)
    #expect(transform.tx == 12.5)
    #expect(transform.ty == 12.5)
}

@Test
func videoCanvasBackgroundDescriptorMapsCanonicalBackgrounds() {
    #expect(
        VideoCanvasRenderPlan.backgroundDescriptor(for: .preset(.stage))
            == .color(red: 0.08, green: 0.02, blue: 0.04, alpha: 1)
    )
    #expect(
        VideoCanvasRenderPlan.backgroundDescriptor(
            for: .color(StudioRGBAColor(red: 0.12, green: 0.34, blue: 0.56, alpha: 0.78))
        ) == .color(red: 0.12, green: 0.34, blue: 0.56, alpha: 0.78)
    )
    #expect(
        VideoCanvasRenderPlan.backgroundDescriptor(for: .localImage(path: "/tmp/canvas.png")) { _ in true }
            == .localImage(path: "/tmp/canvas.png")
    )
    #expect(
        VideoCanvasRenderPlan.backgroundDescriptor(for: .localImage(path: "/tmp/missing.png")) { _ in false }
            == .fallbackBlack
    )
    #expect(
        VideoCanvasRenderPlan.backgroundDescriptor(for: .localImage(path: "")) { _ in true }
            == .fallbackBlack
    )
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
func systemMediaPipelineSharesRecordingCaptureOnlyWhenExplicitlyEligible() {
    #expect(SystemMediaPipeline.shouldShareRecordingCaptureForPublishing(
        publishingMode: .none,
        hasRecordingStream: true,
        hasRecordingWriter: true,
        hasRecordingCaptureGeometry: true,
        sceneKind: .screenOnly,
        hasRecordingVideoCompositor: true,
        hasRecordingVideoPixelBufferAdaptor: true
    ))
    #expect(SystemMediaPipeline.shouldShareRecordingCaptureForPublishing(
        publishingMode: .none,
        hasRecordingStream: true,
        hasRecordingWriter: true,
        hasRecordingCaptureGeometry: true,
        sceneKind: .screenAndFace,
        hasRecordingVideoCompositor: true,
        hasRecordingVideoPixelBufferAdaptor: true
    ))
    #expect(!SystemMediaPipeline.shouldShareRecordingCaptureForPublishing(
        publishingMode: .dedicated,
        hasRecordingStream: true,
        hasRecordingWriter: true,
        hasRecordingCaptureGeometry: true,
        sceneKind: .screenOnly,
        hasRecordingVideoCompositor: true,
        hasRecordingVideoPixelBufferAdaptor: true
    ))
    #expect(!SystemMediaPipeline.shouldShareRecordingCaptureForPublishing(
        publishingMode: .none,
        hasRecordingStream: true,
        hasRecordingWriter: true,
        hasRecordingCaptureGeometry: true,
        sceneKind: .screenAndFace,
        hasRecordingVideoCompositor: true,
        hasRecordingVideoPixelBufferAdaptor: false
    ))
}

@Test
func systemMediaPipelineRoutesRecordingOwnedSamplesToPublisherOnlyInSharedMode() {
    #expect(SystemMediaPipeline.shouldPublishRecordingOwnedStreamSample(
        publishingMode: .recordingOwned,
        isRecordingStream: true,
        hasPublisher: true
    ))
    #expect(!SystemMediaPipeline.shouldPublishRecordingOwnedStreamSample(
        publishingMode: .dedicated,
        isRecordingStream: true,
        hasPublisher: true
    ))
    #expect(!SystemMediaPipeline.shouldPublishRecordingOwnedStreamSample(
        publishingMode: .recordingOwned,
        isRecordingStream: false,
        hasPublisher: true
    ))
    #expect(!SystemMediaPipeline.shouldPublishRecordingOwnedStreamSample(
        publishingMode: .recordingOwned,
        isRecordingStream: true,
        hasPublisher: false
    ))
}

@Test
func systemMediaPipelinePromotesSharedPublishingBeforeStoppingRecording() {
    #expect(SystemMediaPipeline.shouldPromotePublishingBeforeStoppingRecording(
        publishingMode: .recordingOwned,
        hasPublisher: true
    ))
    #expect(!SystemMediaPipeline.shouldPromotePublishingBeforeStoppingRecording(
        publishingMode: .recordingOwned,
        hasPublisher: false
    ))
    #expect(!SystemMediaPipeline.shouldPromotePublishingBeforeStoppingRecording(
        publishingMode: .dedicated,
        hasPublisher: true
    ))
    #expect(!SystemMediaPipeline.shouldPromotePublishingBeforeStoppingRecording(
        publishingMode: .none,
        hasPublisher: true
    ))
}

@Test
func systemMediaPipelineStopStreamDoesNotStopRecordingOwnedCapture() {
    #expect(SystemMediaPipeline.publishingStopPlan(
        mode: .recordingOwned,
        publishingOwnsMicrophoneSession: false,
        recordingUsesPublishingMicrophoneSession: false,
        hasPublishingMicrophoneSession: false
    ) == PublishingStopPlan(
        shouldStopStream: false,
        shouldStopMicrophoneSession: false,
        shouldStopCameraSession: false,
        shouldReturnMicrophoneToRecording: false
    ))

    #expect(SystemMediaPipeline.publishingStopPlan(
        mode: .dedicated,
        publishingOwnsMicrophoneSession: true,
        recordingUsesPublishingMicrophoneSession: false,
        hasPublishingMicrophoneSession: true
    ) == PublishingStopPlan(
        shouldStopStream: true,
        shouldStopMicrophoneSession: true,
        shouldStopCameraSession: true,
        shouldReturnMicrophoneToRecording: false
    ))

    #expect(SystemMediaPipeline.publishingStopPlan(
        mode: .dedicated,
        publishingOwnsMicrophoneSession: false,
        recordingUsesPublishingMicrophoneSession: true,
        hasPublishingMicrophoneSession: true
    ) == PublishingStopPlan(
        shouldStopStream: true,
        shouldStopMicrophoneSession: false,
        shouldStopCameraSession: true,
        shouldReturnMicrophoneToRecording: true
    ))
}

@Test
func systemMediaPipelineAdoptsDedicatedPublishingCaptureWhenRecordingStartsAfterRTMP() {
    #expect(SystemMediaPipeline.dedicatedPublishingRecordingAdoptionPlan(
        publishingMode: .dedicated,
        hasPublisher: true,
        hasPublishingStream: true,
        hasPublishingCaptureGeometry: true,
        sceneKind: .screenOnly,
        hasPublishingCamera: false,
        hasPublishingMicrophone: true
    ) == DedicatedPublishingRecordingAdoptionPlan(
        shouldAdopt: true,
        shouldTransferStreamToRecording: true,
        shouldTransferCameraToRecording: false,
        shouldTransferMicrophoneToRecording: true
    ))

    #expect(SystemMediaPipeline.dedicatedPublishingRecordingAdoptionPlan(
        publishingMode: .dedicated,
        hasPublisher: true,
        hasPublishingStream: true,
        hasPublishingCaptureGeometry: true,
        sceneKind: .screenAndFace,
        hasPublishingCamera: true,
        hasPublishingMicrophone: true
    ) == DedicatedPublishingRecordingAdoptionPlan(
        shouldAdopt: true,
        shouldTransferStreamToRecording: true,
        shouldTransferCameraToRecording: true,
        shouldTransferMicrophoneToRecording: true
    ))
}

@Test
func systemMediaPipelineRejectsDedicatedPublishingAdoptionWithoutStableOwnership() {
    #expect(!SystemMediaPipeline.dedicatedPublishingRecordingAdoptionPlan(
        publishingMode: .recordingOwned,
        hasPublisher: true,
        hasPublishingStream: true,
        hasPublishingCaptureGeometry: true,
        sceneKind: .screenOnly,
        hasPublishingCamera: false,
        hasPublishingMicrophone: false
    ).shouldAdopt)
    #expect(!SystemMediaPipeline.dedicatedPublishingRecordingAdoptionPlan(
        publishingMode: .dedicated,
        hasPublisher: false,
        hasPublishingStream: true,
        hasPublishingCaptureGeometry: true,
        sceneKind: .screenOnly,
        hasPublishingCamera: false,
        hasPublishingMicrophone: false
    ).shouldAdopt)
    #expect(!SystemMediaPipeline.dedicatedPublishingRecordingAdoptionPlan(
        publishingMode: .dedicated,
        hasPublisher: true,
        hasPublishingStream: true,
        hasPublishingCaptureGeometry: true,
        sceneKind: .screenAndFace,
        hasPublishingCamera: false,
        hasPublishingMicrophone: true
    ).shouldAdopt)
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

    #expect(gate.snapshot() == RTMPAppendQueueSnapshot(pendingCount: 0, capacity: 2))
    #expect(gate.tryBeginAppend())
    #expect(gate.tryBeginAppend())
    #expect(!gate.tryBeginAppend())
    #expect(gate.snapshot() == RTMPAppendQueueSnapshot(pendingCount: 2, capacity: 2))

    gate.finishAppend()

    #expect(gate.tryBeginAppend())
    #expect(gate.snapshot() == RTMPAppendQueueSnapshot(pendingCount: 2, capacity: 2))
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
    #expect(await queue.closeAndWait())
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
    #expect(queue.snapshot == RTMPAppendQueueSnapshot(pendingCount: 3, capacity: 3))

    await blocker.releaseAll()
    #expect(await queue.closeAndWait())
    #expect(await blocker.startedCount == 3)
    #expect(queue.snapshot == RTMPAppendQueueSnapshot(pendingCount: 0, capacity: 3))
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
    #expect(await closeTask.value)
    #expect(await recorder.values == [1])
}

@Test
func orderedMediaAppendQueueCloseAndWaitTimesOutPromptlyAndRejectsAdmission() async {
    let blocker = OrderedAppendBlocker()
    let queue = OrderedMediaAppendQueue<Int>(maxPendingAppends: 3) { value in
        await blocker.append(value)
    }

    #expect(queue.enqueue(1))
    await blocker.waitForStartedCount(1)
    #expect(queue.enqueue(2))

    let clock = ContinuousClock()
    let closeStartedAt = clock.now
    let closeTask = Task {
        await queue.closeAndWait(timeout: .milliseconds(50))
    }
    for _ in 0..<100 where !queue.isClosed {
        await Task.yield()
    }

    #expect(queue.isClosed)
    #expect(!queue.enqueue(3))

    let didDrain = await closeTask.value
    let elapsed = closeStartedAt.duration(to: clock.now)
    #expect(!didDrain)
    #expect(elapsed < .seconds(1))
    #expect(await blocker.startedCount == 1)

    let completionTask = Task {
        await queue.waitUntilFinished()
    }
    await blocker.releaseAll()
    #expect(await completionTask.value == false)
}

@Test
func rtmpPublisherShutdownClosesTransportBeforeDeferredMediaTeardown() async {
    let blocker = OrderedAppendBlocker()
    let shutdownRecorder = PublisherShutdownRecorder()
    let queue = OrderedMediaAppendQueue<Int>(maxPendingAppends: 1) { value in
        await blocker.append(value)
    }

    #expect(queue.enqueue(1))
    await blocker.waitForStartedCount(1)

    await RTMPPublisherShutdown.perform(
        appendQueue: queue,
        timeout: .milliseconds(50),
        closeTransport: {
            await shutdownRecorder.recordTransportClose()
        },
        finishMediaTeardown: {
            await shutdownRecorder.recordMediaTeardown()
        }
    )

    #expect(await shutdownRecorder.didCloseTransport)
    #expect(!(await shutdownRecorder.didFinishMediaTeardown))

    await blocker.releaseAll()
    await shutdownRecorder.waitForMediaTeardown()
    #expect(await shutdownRecorder.didFinishMediaTeardown)
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

private actor PublisherShutdownRecorder {
    private(set) var didCloseTransport = false
    private(set) var didFinishMediaTeardown = false
    private var teardownWaiters: [CheckedContinuation<Void, Never>] = []

    func recordTransportClose() {
        didCloseTransport = true
    }

    func recordMediaTeardown() {
        didFinishMediaTeardown = true
        let waiters = teardownWaiters
        teardownWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func waitForMediaTeardown() async {
        guard !didFinishMediaTeardown else { return }
        await withCheckedContinuation { continuation in
            teardownWaiters.append(continuation)
        }
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
