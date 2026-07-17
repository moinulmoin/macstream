import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import Network
import Testing
@testable import MacStreamCore

private func expectedSignalConfigurationDuringMediaCapture(
    _ mode: StudioPerformanceMode
) -> SignalSamplingConfiguration {
    var configuration = mode.signalSamplingConfiguration
    configuration.isMicrophoneEnabled = false
    return configuration
}

@Test
@MainActor
func screenCaptureTargetCannotChangeWhileRecording() async {
    let pipeline = SpyMediaPipeline()
    let displayTarget = ScreenCaptureTarget(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964")
    let windowTarget = ScreenCaptureTarget(id: "window-42", kind: .window, name: "Slides", detail: "Keynote")
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: displayTarget.id, kind: .display, name: displayTarget.name, detail: displayTarget.detail, permission: .granted),
            CaptureDeviceInfo(id: windowTarget.id, kind: .window, name: windowTarget.name, detail: windowTarget.detail, permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report)
    )

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))
    store.startRecording()
    try? await Task.sleep(for: .milliseconds(50))
    store.selectScreenCaptureTarget(windowTarget)

    #expect(!store.canEditScreenCaptureTarget)
    #expect(store.selectedScreenCaptureTarget == displayTarget)
}

@Test
@MainActor
func screenCaptureTargetCannotChangeWhileStreamIsConnectingOrLive() async {
    let pipeline = DelayedStartMediaPipeline()
    let displayTarget = ScreenCaptureTarget(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964")
    let windowTarget = ScreenCaptureTarget(id: "window-42", kind: .window, name: "Slides", detail: "Keynote")
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: displayTarget.id, kind: .display, name: displayTarget.name, detail: displayTarget.detail, permission: .granted),
            CaptureDeviceInfo(id: windowTarget.id, kind: .window, name: windowTarget.name, detail: windowTarget.detail, permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report)
    )

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))
    store.startStream()
    try? await Task.sleep(for: .milliseconds(10))

    #expect(store.isStreamConnecting)
    #expect(!store.canEditScreenCaptureTarget)

    store.selectScreenCaptureTarget(windowTarget)

    #expect(store.selectedScreenCaptureTarget == displayTarget)

    try? await Task.sleep(for: .milliseconds(100))

    #expect(store.streamState == .live)
    #expect(!store.canEditScreenCaptureTarget)

    store.selectScreenCaptureTarget(windowTarget)

    #expect(store.selectedScreenCaptureTarget == displayTarget)
}

@Test
@MainActor
func captureRescanDoesNotChangeScreenTargetWhileRecording() async {
    let pipeline = ConfigurableMediaPipeline()
    let signalProvider = ConfigurableSignalProvider()
    let displayTarget = ScreenCaptureTarget(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964")
    let windowTarget = ScreenCaptureTarget(id: "window-42", kind: .window, name: "Slides", detail: "Keynote")
    let provider = SequencedCaptureDeviceProvider(reports: [
        CapturePreflightReport(
            devices: [
                CaptureDeviceInfo(id: displayTarget.id, kind: .display, name: displayTarget.name, detail: displayTarget.detail, permission: .granted)
            ],
            summary: "Display ready."
        ),
        CapturePreflightReport(
            devices: [
                CaptureDeviceInfo(id: windowTarget.id, kind: .window, name: windowTarget.name, detail: windowTarget.detail, permission: .granted)
            ],
            summary: "Window ready."
        )
    ])
    let store = StudioStore(
        mediaPipeline: pipeline,
        captureDeviceProvider: provider,
        signalProvider: signalProvider
    )

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))
    store.startRecording()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.selectedScreenCaptureTarget == displayTarget)
    #expect(pipeline.lastConfiguration?.screenCaptureTarget == displayTarget)
    #expect(signalProvider.lastConfiguration?.screenCaptureTarget == displayTarget)
    #expect(!store.canScanCaptureDevices)

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(!store.canEditScreenCaptureTarget)
    #expect(store.captureScanBlockedReason == "Stop preview, stream, or recording before checking capture devices.")
    #expect(store.captureReport.summary == "Display ready.")
    #expect(store.selectedScreenCaptureTarget == displayTarget)
    #expect(pipeline.lastConfiguration?.screenCaptureTarget == displayTarget)
    #expect(signalProvider.lastConfiguration?.screenCaptureTarget == displayTarget)
    #expect(await provider.scanCount() == 1)
}

@Test
@MainActor
func adaptivePerformanceModeUsesBalancedWhenPressureIsNominal() {
    let pipeline = ConfigurableMediaPipeline()
    let signalProvider = ConfigurableSignalProvider()
    let pressure = SystemPressureSnapshot(thermalPressure: .nominal, memoryUsedMB: 512, physicalMemoryMB: 16_384)
    let store = StudioStore(
        mediaPipeline: pipeline,
        signalProvider: signalProvider,
        performanceMonitor: FixedSystemPerformanceMonitor(snapshot: pressure),
        preferences: StudioPreferences(performanceMode: .adaptive)
    )

    store.advanceDirector()

    #expect(store.effectivePerformanceMode == .balanced)
    #expect(pipeline.lastConfiguration == expectedMediaConfiguration(.balanced))
    #expect(signalProvider.lastConfiguration == StudioPerformanceMode.balanced.signalSamplingConfiguration)
}

@Test
@MainActor
func adaptivePerformanceModeUsesEfficiencyUnderPressure() {
    let pipeline = ConfigurableMediaPipeline()
    let signalProvider = ConfigurableSignalProvider()
    let pressure = SystemPressureSnapshot(thermalPressure: .serious, memoryUsedMB: 900, physicalMemoryMB: 16_384)
    let store = StudioStore(
        mediaPipeline: pipeline,
        signalProvider: signalProvider,
        performanceMonitor: FixedSystemPerformanceMonitor(snapshot: pressure),
        preferences: StudioPreferences(performanceMode: .adaptive)
    )

    store.advanceDirector()

    #expect(store.effectivePerformanceMode == .efficiency)
    #expect(pipeline.lastConfiguration == expectedMediaConfiguration(.efficiency))
    #expect(signalProvider.lastConfiguration == StudioPerformanceMode.efficiency.signalSamplingConfiguration)
}

@Test
@MainActor
func studioStoreUsesBoundedSmoothPreviewCaptureWhileRTMPPublishing() {
    for mode in StudioPerformanceMode.allCases {
        #expect(StudioStore.previewCaptureConfiguration(
            for: mode,
            isRTMPPublishing: false
        ) == mode.previewCaptureConfiguration)
        let livePreview = StudioStore.previewCaptureConfiguration(
            for: mode,
            isRTMPPublishing: true
        )
        #expect(livePreview.maxDisplayWidth <= StudioPerformanceMode.liveStreamingPreviewConfiguration.maxDisplayWidth)
        #expect(livePreview.framesPerSecond <= StudioPerformanceMode.liveStreamingPreviewConfiguration.framesPerSecond)
        #expect(livePreview.framesPerSecond == min(
            mode.previewCaptureConfiguration.framesPerSecond,
            StudioPerformanceMode.liveStreamingPreviewConfiguration.framesPerSecond
        ))
        #expect(livePreview.queueDepth == 1)
    }

    #expect(StudioPerformanceMode.liveStreamingPreviewConfiguration.framesPerSecond == 12)
    #expect(StudioPerformanceMode.liveStreamingPreviewConfiguration.maxDisplayWidth == 960)
    #expect(StudioPerformanceMode.liveStreamingPreviewConfiguration.queueDepth == 1)
}

@Test
@MainActor
func studioStoreReducesSamplingCostWhileRTMPPublishing() {
    for mode in StudioPerformanceMode.allCases {
        #expect(StudioStore.signalSamplingConfiguration(
            for: mode,
            isRTMPPublishing: false
        ) == mode.signalSamplingConfiguration)
        #expect(StudioStore.signalSamplingConfiguration(
            for: mode,
            isRTMPPublishing: true
        ) == StudioPerformanceMode.liveStreamingSignalSamplingConfiguration)
        #expect(StudioStore.directorSampleIntervalMilliseconds(
            for: mode,
            isRTMPPublishing: false
        ) == mode.directorSampleIntervalMilliseconds)
        #expect(StudioStore.directorSampleIntervalMilliseconds(
            for: mode,
            isRTMPPublishing: true
        ) >= StudioPerformanceMode.liveStreamingDirectorSampleIntervalMilliseconds)
    }
}

@Test
@MainActor
func studioStoreCapsRTMPPublishingMediaFPS() {
    let responsive = StudioPerformanceMode.responsive.mediaConfiguration
    let capped = StudioStore.mediaConfiguration(responsive, constrainedForRTMPPublishing: true)

    #expect(capped.framesPerSecond == 30)
    #expect(capped.maxVideoWidth == responsive.maxVideoWidth)
    #expect(capped.videoBitrate == responsive.videoBitrate)
    #expect(StudioStore.mediaConfiguration(
        StudioPerformanceMode.efficiency.mediaConfiguration,
        constrainedForRTMPPublishing: true
    ).framesPerSecond == 24)
}

@Test
@MainActor
func resourceUsageSnapshotBreaksDownCapturePreviewDirectorAndSignals() {
    let pipeline = ConfigurableMediaPipeline()
    let pressure = SystemPressureSnapshot(
        thermalPressure: .fair,
        memoryUsedMB: 768,
        physicalMemoryMB: 16_384,
        isLowPowerModeEnabled: true
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        performanceMonitor: FixedSystemPerformanceMonitor(snapshot: pressure),
        preferences: StudioPreferences(performanceMode: .responsive)
    )

    pipeline.currentHealth = StreamHealth(
        bitrateKbps: 9_500,
        droppedFrames: 2,
        captureFPS: 48,
        roundTripMs: 28
    )
    store.startStream()
    store.advanceDirector()

    let snapshot = store.resourceUsageSnapshot
    #expect(snapshot.processMemoryMB == 768)
    #expect(snapshot.memoryUsagePercent == 4)
    #expect(snapshot.thermalPressure == .fair)
    #expect(snapshot.isLowPowerModeEnabled)
    #expect(snapshot.streamTargetFPS == 60)
    #expect(snapshot.streamActualFPS == 48)
    #expect(snapshot.streamDroppedFrames == 2)
    #expect(snapshot.streamBitrateKbps == 9_500)
    #expect(snapshot.streamQueueDepth == 5)
    #expect(snapshot.previewTargetFPS == 15)
    #expect(snapshot.previewMaxDisplayWidth == 1_920)
    #expect(snapshot.previewQueueDepth == 3)
    #expect(snapshot.directorSampleIntervalMilliseconds == 500)
    #expect(snapshot.screenSignalFPS == 8)
}

@Test
@MainActor
func resourceUsageSnapshotReflectsRTMPPublishingResourcePolicies() async {
    let signalProvider = ConfigurableSignalProvider()
    let pipeline = ConfigurableMediaPipeline(streamTransport: .rtmpPublish)
    let store = StudioStore(
        mediaPipeline: pipeline,
        signalProvider: signalProvider,
        preferences: StudioPreferences(performanceMode: .responsive)
    )
    store.destination = StreamDestination(name: "RTMP", rtmpURL: "rtmps://live.example.com/app/sk_live_secret")
    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    let snapshot = store.resourceUsageSnapshot

    #expect(snapshot.previewTargetFPS == StudioPerformanceMode.liveStreamingPreviewConfiguration.framesPerSecond)
    #expect(snapshot.previewMaxDisplayWidth == StudioPerformanceMode.liveStreamingPreviewConfiguration.maxDisplayWidth)
    #expect(snapshot.previewQueueDepth == StudioPerformanceMode.liveStreamingPreviewConfiguration.queueDepth)
    #expect(snapshot.directorSampleIntervalMilliseconds == StudioPerformanceMode.liveStreamingDirectorSampleIntervalMilliseconds)
    #expect(snapshot.screenSignalFPS == StudioPerformanceMode.liveStreamingSignalSamplingConfiguration.screenMotionFramesPerSecond)
    #expect(snapshot.streamTargetFPS == 30)
    #expect(signalProvider.lastConfiguration?.screenMotionFramesPerSecond == 2)
}

@Test
@MainActor
func adaptivePerformanceModeUsesEfficiencyWhenCaptureHealthDrops() async {
    let pipeline = ConfigurableMediaPipeline()
    let signalProvider = ConfigurableSignalProvider()
    pipeline.currentHealth = StreamHealth(
        bitrateKbps: 6_200,
        droppedFrames: 4,
        captureFPS: 30,
        audioLevel: 0.2,
        roundTripMs: 18
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        signalProvider: signalProvider,
        preferences: StudioPreferences(performanceMode: .adaptive)
    )
    store.directorMode = .paused

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.advanceDirector()

    #expect(store.effectivePerformanceMode == .efficiency)
    #expect(pipeline.lastConfiguration == expectedMediaConfiguration(.efficiency))
    #expect(signalProvider.lastConfiguration == expectedSignalConfigurationDuringMediaCapture(.efficiency))
    #expect(store.streamState == .degraded("Dropped frames detected; reducing capture cost."))
}

@Test
@MainActor
func adaptivePerformanceModeUsesEfficiencyWhenRTMPAppendQueueSaturates() async {
    let pipeline = ConfigurableMediaPipeline(streamTransport: .rtmpPublish)
    pipeline.currentHealth = StreamHealth(
        bitrateKbps: 4_000,
        publishState: .publishing,
        captureFPS: 30,
        rtmpPendingAppends: 3,
        rtmpAppendCapacity: 3
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        preferences: StudioPreferences(performanceMode: .adaptive)
    )
    store.directorMode = .paused
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.advanceDirector()

    #expect(store.effectivePerformanceMode == .efficiency)
    #expect(store.streamState == .degraded("RTMP append queue saturated; reducing capture cost."))
    #expect(store.operatorRecoveryGuidance == OperatorRecoveryGuidance(
        kind: .backpressure,
        title: "Output queues full",
        detail: "All RTMP lanes are falling behind. Switch to Efficiency mode, or stop before lowering FPS or resolution.",
        action: .reduceOutputCost
    ))
}

@Test
@MainActor
func recoveredRTMPLaneDoesNotKeepBackpressureGuidanceFromCumulativeRejections() async {
    let destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/test-key"
    )
    let pipeline = ConfigurableMediaPipeline(streamTransport: .rtmpPublish)
    pipeline.currentHealth = StreamHealth(
        bitrateKbps: 4_000,
        publishState: .publishing,
        captureFPS: 30,
        rtmpPendingAppends: 0,
        rtmpAppendCapacity: 3
    )
    pipeline.currentDestinationStatuses = [
        StreamDestinationStatus(
            id: destination.id,
            name: destination.name,
            state: .publishing,
            pendingAppends: 0,
            appendCapacity: 3,
            appendRejections: 4
        )
    ]
    let store = StudioStore(mediaPipeline: pipeline)
    store.destination = destination

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.streamState == .live)
    #expect(store.operatorRecoveryGuidance == nil)
}

@Test
@MainActor
func adaptivePerformanceModeUsesEfficiencyWhenRTMPAudioAppendIsRejected() async {
    let pipeline = ConfigurableMediaPipeline(streamTransport: .rtmpPublish)
    pipeline.currentHealth = StreamHealth(
        bitrateKbps: 4_000,
        publishState: .publishing,
        captureFPS: 30,
        rtmpAudioAppendRejections: 1,
        rtmpPendingAppends: 1,
        rtmpAppendCapacity: 3
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        preferences: StudioPreferences(performanceMode: .adaptive)
    )
    store.directorMode = .paused
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.advanceDirector()

    #expect(store.effectivePerformanceMode == .efficiency)
    #expect(store.streamState == .degraded("RTMP audio backpressure detected; reducing capture cost."))
}

@Test
@MainActor
func zeroCaptureFPSRequiresStaleIntervalBeforePressure() {
    #expect(!StudioStore.captureFPSIndicatesPressure(0, lowFPSLimit: 20, zeroFPSAge: nil))
    #expect(!StudioStore.captureFPSIndicatesPressure(0, lowFPSLimit: 20, zeroFPSAge: .milliseconds(1_999)))
    #expect(StudioStore.captureFPSIndicatesPressure(0, lowFPSLimit: 20, zeroFPSAge: .seconds(2)))
    #expect(StudioStore.captureFPSIndicatesPressure(10, lowFPSLimit: 20, zeroFPSAge: nil))
    #expect(!StudioStore.captureFPSIndicatesPressure(24, lowFPSLimit: 20, zeroFPSAge: nil))
}

@Test
@MainActor
func pausedLiveStreamSamplesCaptureHealthWithoutDirectorLoop() async {
    let pipeline = ConfigurableMediaPipeline()
    let signalProvider = ConfigurableSignalProvider()
    pipeline.currentHealth = StreamHealth(
        bitrateKbps: 6_200,
        droppedFrames: 4,
        captureFPS: 30,
        audioLevel: 0.2,
        roundTripMs: 18
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        signalProvider: signalProvider,
        preferences: StudioPreferences(performanceMode: .adaptive)
    )
    store.directorMode = .paused

    store.startStream()
    try? await Task.sleep(for: .milliseconds(80))

    #expect(signalProvider.startCount == 0)
    #expect(store.effectivePerformanceMode == .efficiency)
    #expect(pipeline.lastConfiguration == expectedMediaConfiguration(.efficiency))
    #expect(store.streamState == .degraded("Dropped frames detected; reducing capture cost."))
}

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

@Test
@MainActor
func adaptivePerformanceModeRecoversWhenCaptureHealthStabilizes() async {
    let pipeline = ConfigurableMediaPipeline()
    let signalProvider = ConfigurableSignalProvider()
    pipeline.currentHealth = StreamHealth(
        bitrateKbps: 6_200,
        droppedFrames: 4,
        captureFPS: 30,
        audioLevel: 0.2,
        roundTripMs: 18
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        signalProvider: signalProvider,
        preferences: StudioPreferences(performanceMode: .adaptive)
    )
    store.directorMode = .paused

    store.startStream()
    try? await Task.sleep(for: .milliseconds(80))

    #expect(store.effectivePerformanceMode == .efficiency)
    #expect(pipeline.lastConfiguration == expectedMediaConfiguration(.efficiency))
    #expect(signalProvider.lastConfiguration == expectedSignalConfigurationDuringMediaCapture(.efficiency))
    #expect(store.streamState == .degraded("Dropped frames detected; reducing capture cost."))

    pipeline.currentHealth = StreamHealth(
        bitrateKbps: 6_200,
        droppedFrames: 4,
        captureFPS: 30,
        audioLevel: 0.2,
        roundTripMs: 18
    )
    store.advanceDirector()

    #expect(store.effectivePerformanceMode == .efficiency)
    #expect(pipeline.lastConfiguration == expectedMediaConfiguration(.efficiency))
    #expect(signalProvider.lastConfiguration == expectedSignalConfigurationDuringMediaCapture(.efficiency))
    #expect(store.streamState == .degraded("Dropped frames detected; reducing capture cost."))

    store.advanceDirector()

    #expect(store.effectivePerformanceMode == .balanced)
    #expect(pipeline.lastConfiguration == expectedMediaConfiguration(.balanced))
    #expect(signalProvider.lastConfiguration == expectedSignalConfigurationDuringMediaCapture(.balanced))
    #expect(store.streamState == .live)
}
