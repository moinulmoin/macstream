import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import Network
import Testing
@testable import MacStreamCore

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
func studioStoreUsesMinimalPreviewCaptureWhileRTMPPublishing() {
    for mode in StudioPerformanceMode.allCases {
        #expect(StudioStore.previewCaptureConfiguration(
            for: mode,
            isRTMPPublishing: false
        ) == mode.previewCaptureConfiguration)
        #expect(StudioStore.previewCaptureConfiguration(
            for: mode,
            isRTMPPublishing: true
        ) == StudioPerformanceMode.liveStreamingPreviewConfiguration)
    }

    #expect(StudioPerformanceMode.liveStreamingPreviewConfiguration.framesPerSecond <= 6)
    #expect(StudioPerformanceMode.liveStreamingPreviewConfiguration.maxDisplayWidth <= 640)
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
    #expect(signalProvider.lastConfiguration == StudioPerformanceMode.efficiency.signalSamplingConfiguration)
    #expect(store.streamState == .degraded("Dropped frames detected; reducing capture cost."))
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
    #expect(signalProvider.lastConfiguration == StudioPerformanceMode.efficiency.signalSamplingConfiguration)
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
    #expect(signalProvider.lastConfiguration == StudioPerformanceMode.efficiency.signalSamplingConfiguration)
    #expect(store.streamState == .degraded("Dropped frames detected; reducing capture cost."))

    store.advanceDirector()

    #expect(store.effectivePerformanceMode == .balanced)
    #expect(pipeline.lastConfiguration == expectedMediaConfiguration(.balanced))
    #expect(signalProvider.lastConfiguration == StudioPerformanceMode.balanced.signalSamplingConfiguration)
    #expect(store.streamState == .live)
}
