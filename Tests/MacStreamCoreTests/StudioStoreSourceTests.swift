import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import Network
import Testing
@testable import MacStreamCore

@Test
@MainActor
func studioStoreReportsSourceEnabledState() {
    let store = StudioStore()
    let camera = store.sources.first { $0.kind == .camera }!

    #expect(store.isSourceEnabled(.camera))

    store.toggleSource(camera)

    #expect(!store.isSourceEnabled(.camera))
}

@Test
@MainActor
func savedSourceConfigurationRestoresSourceState() {
    let store = StudioStore()

    store.applySavedSourceConfiguration([
        StudioSourceConfiguration(kind: .camera, isEnabled: false, level: 0.2),
        StudioSourceConfiguration(kind: .screen, isEnabled: true, level: 0.43),
        StudioSourceConfiguration(kind: .microphone, isEnabled: false, level: -1),
        StudioSourceConfiguration(kind: .systemAudio, isEnabled: true, level: 2)
    ])

    #expect(!store.isSourceEnabled(.camera))
    #expect(store.sourceLevel(.camera) == 1)
    #expect(store.isSourceEnabled(.screen))
    #expect(store.sourceLevel(.screen) == 0.43)
    #expect(!store.isSourceEnabled(.microphone))
    #expect(store.sourceLevel(.microphone) == 0)
    #expect(store.isSourceEnabled(.systemAudio))
    #expect(store.sourceLevel(.systemAudio) == 1)
    #expect(store.sourceConfiguration.contains(StudioSourceConfiguration(kind: .systemAudio, isEnabled: true, level: 1)))
}

@Test
@MainActor
func activeCaptureKeepsSelectedSceneRequiredSourcesEnabled() async throws {
    let pipeline = ConfigurableMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)
    let screenScene = try #require(store.scenes.first { $0.kind == .screenOnly })
    let screen = try #require(store.sources.first { $0.kind == .screen })
    let microphone = try #require(store.sources.first { $0.kind == .microphone })

    store.selectScene(screenScene)
    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.isLive)
    #expect(!store.canToggleSource(screen))
    #expect(!store.canAdjustSourceLevel(screen))

    let eventCount = store.events.count
    let pipelineUpdateCount = pipeline.updateCount
    store.toggleSource(screen)
    store.updateLevel(for: screen, level: 0)

    #expect(store.isSourceEnabled(.screen))
    #expect(store.sourceLevel(.screen) == 1)
    #expect(store.events.count == eventCount)
    #expect(pipeline.updateCount == pipelineUpdateCount)

    #expect(store.canToggleSource(microphone))
    #expect(store.canAdjustSourceLevel(microphone))
    store.toggleSource(microphone)

    #expect(!store.isSourceEnabled(.microphone))
    #expect(pipeline.updateCount == pipelineUpdateCount + 1)
}

@Test
@MainActor
func activeRealCaptureRejectsUnsupportedSceneSwitches() async throws {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted),
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(
        mediaPipeline: ScreenVideoGatedMediaPipeline(streamTransport: .rtmpPublish),
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report)
    )
    let screenScene = try #require(store.scenes.first { $0.kind == .screenOnly })
    let screenAndFaceScene = try #require(store.scenes.first { $0.kind == .screenAndFace })
    let faceScene = try #require(store.scenes.first { $0.kind == .face })
    let brbScene = try #require(store.scenes.first { $0.kind == .brb })

    store.destination = StreamDestination(name: "RTMP", rtmpURL: "rtmp://127.0.0.1/live/stream")
    store.selectScene(screenScene)
    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.canStartStream)

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.isLive)
    #expect(!store.canSelectScene(faceScene))
    #expect(!store.canSelectScene(screenAndFaceScene))
    #expect(!store.canSelectScene(brbScene))
    #expect(store.sceneSelectionBlockedReason(for: faceScene) == "Stop real capture before choosing Webcam.")
    #expect(store.sceneSelectionBlockedReason(for: screenAndFaceScene) == "Stop real capture before choosing Screen + Webcam.")
    #expect(store.sceneSelectionBlockedReason(for: brbScene) == "Stop real capture before choosing BRB.")

    let eventCount = store.events.count
    store.selectScene(faceScene)

    #expect(store.selectedSceneKind == .screenOnly)
    #expect(store.events.count == eventCount)

    store.selectScene(screenAndFaceScene)

    #expect(store.selectedSceneKind == .screenOnly)
}

@Test
@MainActor
func activeRealCaptureAllowsSupportedComposedSceneSwitches() async throws {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted),
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let pipeline = ComposedScreenVideoMediaPipeline(streamTransport: .rtmpPublish)
    let store = StudioStore(
        mediaPipeline: pipeline,
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report)
    )
    let screenScene = try #require(store.scenes.first { $0.kind == .screenOnly })
    let screenAndFaceScene = try #require(store.scenes.first { $0.kind == .screenAndFace })
    let faceScene = try #require(store.scenes.first { $0.kind == .face })

    store.destination = StreamDestination(name: "RTMP", rtmpURL: "rtmp://127.0.0.1/live/stream")
    store.selectScene(screenScene)
    store.scanCaptureDevices()
    await waitForStudioState { store.canStartStream }

    #expect(store.canStartStream)

    store.startStream()
    await waitForStudioState { store.isLive }

    #expect(store.isLive)
    #expect(store.canSelectScene(screenAndFaceScene))
    #expect(!store.canSelectScene(faceScene))
    #expect(store.sceneSelectionBlockedReason(for: screenAndFaceScene) == nil)

    store.selectScene(screenAndFaceScene)

    #expect(store.selectedSceneKind == .screenAndFace)
    #expect(pipeline.lastConfiguration?.sceneKind == .screenAndFace)
}

@Test
@MainActor
func activeRecordingRejectsUnsupportedSceneSwitches() async throws {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted),
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(
        mediaPipeline: ScreenVideoGatedMediaPipeline(streamTransport: .rtmpPublish),
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report)
    )
    let screenScene = try #require(store.scenes.first { $0.kind == .screenOnly })
    let faceScene = try #require(store.scenes.first { $0.kind == .face })

    store.selectScene(screenScene)
    store.scanCaptureDevices()
    await waitForStudioState { store.canStartRecording }

    #expect(store.canStartRecording)

    store.startRecording()
    await waitForStudioState { store.recordingState == .recording }

    #expect(store.recordingState == .recording)
    #expect(!store.canSelectScene(faceScene))
    #expect(store.sceneSelectionBlockedReason(for: faceScene) == "Stop recording before choosing Webcam.")

    let eventCount = store.events.count
    store.selectScene(faceScene)

    #expect(store.selectedSceneKind == .screenOnly)
    #expect(store.events.count == eventCount)
}

@Test
@MainActor
func activeRealCaptureSuppressesUnavailableDirectorSceneCue() async throws {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted),
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: true,
            speechLevel: 0.72,
            screenMotion: 0.08,
            hasFace: true,
            activeApplication: "Notes"
        )
    )
    let store = StudioStore(
        mediaPipeline: ScreenVideoGatedMediaPipeline(streamTransport: .rtmpPublish),
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report),
        signalProvider: provider
    )
    let screenScene = try #require(store.scenes.first { $0.kind == .screenOnly })

    store.destination = StreamDestination(name: "RTMP", rtmpURL: "rtmp://127.0.0.1/live/stream")
    store.selectScene(screenScene)
    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))
    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    store.advanceDirector()

    #expect(store.isLive)
    #expect(store.selectedSceneKind == .screenOnly)
    #expect(store.recommendation == nil)
    #expect(store.autoCueRemainingSeconds == nil)
    #expect(!store.events.contains { $0.title == "Cue Webcam" })
}

@Test
@MainActor
func activeRealCaptureRetargetsUnavailableImmediateCueToStreamWarning() async throws {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted),
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: false,
            speechLevel: 0.04,
            screenMotion: 0.1,
            hasFace: true,
            activeApplication: "Keynote",
            isScreenFrozen: true
        )
    )
    let store = StudioStore(
        mediaPipeline: ScreenVideoGatedMediaPipeline(streamTransport: .rtmpPublish),
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report),
        signalProvider: provider
    )
    let screenScene = try #require(store.scenes.first { $0.kind == .screenOnly })

    store.destination = StreamDestination(name: "RTMP", rtmpURL: "rtmp://127.0.0.1/live/stream")
    store.selectScene(screenScene)
    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))
    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    store.advanceDirector()

    #expect(store.isLive)
    #expect(store.selectedSceneKind == .screenOnly)
    #expect(store.recommendation?.target == .screenOnly)
    #expect(store.recommendation?.urgency == .immediate)
    #expect(store.recommendation?.reason.contains("Stop real capture before choosing Webcam.") == true)
    #expect(!store.canApplyRecommendation)
    #expect(store.autoCueRemainingSeconds == nil)
    #expect(store.events.contains { $0.title == "Check stream" })
}

@Test
@MainActor
func defaultSourcesKeepSystemAudioOptIn() {
    let store = StudioStore()

    #expect(store.isSourceEnabled(.camera))
    #expect(store.isSourceEnabled(.screen))
    #expect(store.isSourceEnabled(.microphone))
    #expect(!store.isSourceEnabled(.systemAudio))
    #expect(store.sourceSetupTitle == "3/4 on")
    #expect(store.sourceLevel(.systemAudio) == 0.72)
}

@Test
func sourceLevelSupportMatchesCurrentCaptureControls() {
    #expect(!SourceKind.camera.supportsLevelControl)
    #expect(SourceKind.screen.supportsLevelControl)
    #expect(SourceKind.microphone.supportsLevelControl)
    #expect(SourceKind.systemAudio.supportsLevelControl)
}

@Test
@MainActor
func studioStoreAppliesSourceTogglesToSignalSamplingConfiguration() {
    let provider = ConfigurableSignalProvider()
    let store = StudioStore(signalProvider: provider)
    let microphone = store.sources.first { $0.kind == .microphone }!
    let screen = store.sources.first { $0.kind == .screen }!

    #expect(provider.lastConfiguration == SignalSamplingConfiguration(screenMotionFramesPerSecond: 4))

    store.toggleSource(screen)

    #expect(provider.lastConfiguration == SignalSamplingConfiguration(
        screenMotionFramesPerSecond: 4,
        isMicrophoneEnabled: true,
        isScreenMotionEnabled: false
    ))

    store.toggleSource(microphone)

    #expect(provider.lastConfiguration == SignalSamplingConfiguration(
        screenMotionFramesPerSecond: 4,
        isMicrophoneEnabled: false,
        isScreenMotionEnabled: false
    ))
}

@Test
@MainActor
func sourceTogglesPreservePerformanceSamplingRate() {
    let provider = ConfigurableSignalProvider()
    let store = StudioStore(
        signalProvider: provider,
        preferences: StudioPreferences(performanceMode: .responsive)
    )
    let screen = store.sources.first { $0.kind == .screen }!

    store.toggleSource(screen)

    #expect(provider.lastConfiguration == SignalSamplingConfiguration(
        screenMotionFramesPerSecond: 8,
        isMicrophoneEnabled: true,
        isScreenMotionEnabled: false
    ))
}

@Test
@MainActor
func zeroScreenLevelDisablesScreenMotionSampling() {
    let provider = ConfigurableSignalProvider()
    let store = StudioStore(signalProvider: provider)
    let screen = store.sources.first { $0.kind == .screen }!

    store.updateLevel(for: screen, level: 0)

    #expect(provider.lastConfiguration == SignalSamplingConfiguration(
        screenMotionFramesPerSecond: 4,
        isMicrophoneEnabled: true,
        isScreenMotionEnabled: false
    ))

    store.updateLevel(for: screen, level: 0.5)

    #expect(provider.lastConfiguration == SignalSamplingConfiguration(
        screenMotionFramesPerSecond: 4,
        isMicrophoneEnabled: true,
        isScreenMotionEnabled: true
    ))
}

@Test
@MainActor
func sourceMonitoringDoesNotStartWithoutSelectedMicrophone() {
    let provider = MutableSignalProvider(
        snapshot: SignalSnapshot(isSpeaking: true, speechLevel: 0.82)
    )
    let store = StudioStore(signalProvider: provider)

    store.startSourceMonitoring()

    #expect(provider.startCount == 0)
    #expect(store.latestSignals.speechLevel == 0)
    #expect(store.latestSignals.isMicMuted)

    store.stopSourceMonitoring()
}

@Test
@MainActor
func sourceMonitoringDoesNotRepublishUnchangedMutedState() {
    let store = StudioStore(signalProvider: MutableSignalProvider())

    store.startSourceMonitoring()
    let publishedTimestamp = store.latestSignals.timestamp
    store.advanceSourceMonitoring()

    #expect(store.latestSignals.timestamp == publishedTimestamp)
    #expect(store.latestSignals.isMicMuted)
    #expect(store.health.audioLevel == 0)

    store.stopSourceMonitoring()
}

@Test
@MainActor
func sourceMonitoringSamplesSelectedMicrophoneWithoutScreenMotion() async {
    let provider = MutableSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: true,
            speechLevel: 0.82,
            screenMotion: 0.67,
            hasFace: true,
            activeApplication: "Xcode"
        )
    )
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report),
        signalProvider: provider
    )

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))
    store.startSourceMonitoring()

    #expect(provider.startCount == 1)
    #expect(provider.lastConfiguration == StudioStore.sourceMonitoringSignalConfiguration(
        isMicrophoneEnabled: true,
        microphoneDeviceID: "microphone-1"
    ))
    #expect(provider.lastConfiguration?.isActivityContextEnabled == false)
    #expect(store.latestSignals.speechLevel == 0.82)
    #expect(store.latestSignals.isSpeaking)
    #expect(store.health.audioLevel == 0.82)

    store.stopSourceMonitoring()

    #expect(provider.stopCount == 1)
}

@Test
@MainActor
func recordingGatesIdleMicrophoneMonitoringAndRestoresItAfterCapture() async {
    let provider = ConfigurableSignalProvider()
    let store = StudioStore(
        mediaPipeline: ConfigurableMediaPipeline(),
        signalProvider: provider
    )

    #expect(provider.lastConfiguration?.isMicrophoneEnabled == true)

    store.startRecording()

    #expect(store.recordingState == .starting)
    #expect(provider.lastConfiguration?.isMicrophoneEnabled == false)

    for _ in 0..<100 {
        guard store.recordingState != .recording else { break }
        await Task.yield()
    }

    #expect(store.recordingState == .recording)
    #expect(provider.lastConfiguration?.isMicrophoneEnabled == false)
    #expect(provider.lastConfiguration?.isActivityContextEnabled == true)
    #expect(provider.lastConfiguration?.isScreenMotionEnabled == true)

    store.stopRecording()
    for _ in 0..<100 {
        guard store.recordingState != .stopped else { break }
        await Task.yield()
    }

    #expect(store.recordingState == .stopped)
    #expect(provider.lastConfiguration?.isMicrophoneEnabled == true)
}

@Test
func systemSignalProviderReportsUnavailableWhenMicrophoneIsEnabledWithoutSelectedDevice() async {
    let provider = SystemSignalProvider()

    provider.update(configuration: SignalSamplingConfiguration(
        isMicrophoneEnabled: true,
        microphoneDeviceID: nil,
        isScreenMotionEnabled: false,
        isActivityContextEnabled: false
    ))
    provider.start()
    try? await Task.sleep(for: .milliseconds(30))

    let snapshot = provider.snapshot()

    #expect(snapshot.isMicMuted)
    #expect(snapshot.speechLevel == 0)

    provider.stop()
}

@Test
@MainActor
func studioStoreAppliesPerformanceModeToMediaPipeline() async {
    let pipeline = ConfigurableMediaPipeline()
    let store = StudioStore(
        mediaPipeline: pipeline,
        preferences: StudioPreferences(performanceMode: .efficiency)
    )

    #expect(pipeline.lastConfiguration == expectedMediaConfiguration(.efficiency))

    store.updatePreferences(StudioPreferences(performanceMode: .responsive))
    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(pipeline.lastConfiguration == expectedMediaConfiguration(.responsive))
    #expect(pipeline.configurationAtStartStream == expectedMediaConfiguration(.responsive))
    #expect(store.health.captureFPS == StudioPerformanceMode.responsive.mediaConfiguration.framesPerSecond)
}

@Test
@MainActor
func studioStoreScalesPipelineMicrophoneSignalAndUsesDeliveryStateForMuteTruth() async {
    let pipeline = ConfigurableMediaPipeline()
    pipeline.currentHealth = StreamHealth(
        bitrateKbps: 3_200,
        droppedFrames: 7,
        captureFPS: 48,
        audioLevel: 0.12,
        roundTripMs: 16,
        microphoneDeliveryState: .stalled
    )
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: true,
            speechLevel: 0.74,
            screenMotion: 0.92,
            hasFace: true,
            activeApplication: "Xcode",
            isScreenFrozen: true
        )
    )
    let store = StudioStore(mediaPipeline: pipeline, signalProvider: provider)
    let microphone = store.sources.first { $0.kind == .microphone }!
    store.updateLevel(for: microphone, level: 0.5)

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.advanceDirector()

    #expect(store.health.bitrateKbps == 3_200)
    #expect(store.health.droppedFrames == 7)
    #expect(store.health.captureFPS == 48)
    #expect(store.health.audioLevel == 0.12)
    #expect(abs(store.latestSignals.speechLevel - 0.06) < 0.000_001)
    #expect(!store.latestSignals.isSpeaking)
    #expect(store.latestSignals.isMicMuted)
    #expect(store.health.roundTripMs == 16)
}

@Test
@MainActor
func studioStorePreservesZeroCaptureFPSFromPipelineHealth() async {
    let pipeline = ConfigurableMediaPipeline()
    pipeline.currentHealth = StreamHealth(captureFPS: 0)
    let store = StudioStore(mediaPipeline: pipeline)

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.advanceDirector()

    #expect(store.health.captureFPS == 0)
}

@Test
@MainActor
func studioStoreKeepsOfflineCaptureFPSAtZeroWhenHealthIsSampled() {
    let store = StudioStore(mediaPipeline: ConfigurableMediaPipeline())

    store.advanceDirector()

    #expect(store.streamState == .offline)
    #expect(store.recordingState == .stopped)
    #expect(store.health.captureFPS == 0)
}

@Test
@MainActor
func studioStoreAppliesAudioSourceTogglesToMediaPipelineConfiguration() {
    let pipeline = ConfigurableMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)
    let microphone = store.sources.first { $0.kind == .microphone }!
    let systemAudio = store.sources.first { $0.kind == .systemAudio }!

    #expect(pipeline.lastConfiguration?.capturesMicrophone == true)
    #expect(pipeline.lastConfiguration?.capturesSystemAudio == false)

    store.toggleSource(systemAudio)

    #expect(pipeline.lastConfiguration?.capturesMicrophone == true)
    #expect(pipeline.lastConfiguration?.capturesSystemAudio == true)

    store.toggleSource(microphone)

    #expect(pipeline.lastConfiguration?.capturesMicrophone == false)
    #expect(pipeline.lastConfiguration?.capturesSystemAudio == true)

    store.toggleSource(systemAudio)

    #expect(pipeline.lastConfiguration?.capturesMicrophone == false)
    #expect(pipeline.lastConfiguration?.capturesSystemAudio == false)
}

@Test
@MainActor
func sourceLevelsUpdateMediaPipelineAudioConfiguration() {
    let pipeline = ConfigurableMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)
    let microphone = store.sources.first { $0.kind == .microphone }!
    let systemAudio = store.sources.first { $0.kind == .systemAudio }!

    #expect(pipeline.lastConfiguration?.microphoneLevel == 1)
    #expect(pipeline.lastConfiguration?.systemAudioLevel == 0.72)
    #expect(pipeline.lastConfiguration?.capturesSystemAudio == false)

    store.toggleSource(systemAudio)

    store.updateLevel(for: microphone, level: 0.35)
    store.updateLevel(for: systemAudio, level: 0.4)

    #expect(pipeline.lastConfiguration?.capturesMicrophone == true)
    #expect(pipeline.lastConfiguration?.capturesSystemAudio == true)
    #expect(pipeline.lastConfiguration?.microphoneLevel == 0.35)
    #expect(pipeline.lastConfiguration?.systemAudioLevel == 0.4)

    store.updateLevel(for: microphone, level: 0)
    store.updateLevel(for: systemAudio, level: 0)

    #expect(pipeline.lastConfiguration?.capturesMicrophone == false)
    #expect(pipeline.lastConfiguration?.capturesSystemAudio == false)
    #expect(pipeline.lastConfiguration?.microphoneLevel == 0)
    #expect(pipeline.lastConfiguration?.systemAudioLevel == 0)
}

@Test
@MainActor
func sourceLevelUpdatesSkipRedundantClampedValues() {
    let pipeline = ConfigurableMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)
    let microphone = store.sources.first { $0.kind == .microphone }!

    #expect(store.sourceLevel(.microphone) == 1)
    #expect(pipeline.updateCount == 1)

    store.updateLevel(for: microphone, level: 2)

    #expect(store.sourceLevel(.microphone) == 1)
    #expect(pipeline.updateCount == 1)

    store.updateLevel(for: microphone, level: 0.35)

    #expect(store.sourceLevel(.microphone) == 0.35)
    #expect(pipeline.updateCount == 2)

    store.updateLevel(for: microphone, level: 0.35)

    #expect(pipeline.updateCount == 2)
}

@Test
@MainActor
func sourceLevelUpdatesQuantizeSliderNoise() throws {
    let pipeline = ConfigurableMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)
    let microphone = store.sources.first { $0.kind == .microphone }!
    let sourceRackURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStream/Views/SourceRackView.swift")
    let sourceRack = try String(contentsOf: sourceRackURL, encoding: .utf8)

    store.updateLevel(for: microphone, level: 0.354)

    #expect(store.sourceLevel(.microphone) == 0.35)
    #expect(pipeline.updateCount == 2)

    store.updateLevel(for: microphone, level: 0.351)

    #expect(store.sourceLevel(.microphone) == 0.35)
    #expect(pipeline.updateCount == 2)

    store.updateLevel(for: microphone, level: 0.356)

    #expect(store.sourceLevel(.microphone) == 0.36)
    #expect(pipeline.updateCount == 3)
    #expect(sourceRack.contains("step: 0.01"))
}

@Test
@MainActor
func cameraLevelUpdatesAreIgnored() {
    let pipeline = ConfigurableMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)
    let camera = store.sources.first { $0.kind == .camera }!

    #expect(store.sourceLevel(.camera) == 1)
    #expect(pipeline.updateCount == 1)

    store.updateLevel(for: camera, level: 0)

    #expect(store.sourceLevel(.camera) == 1)
    #expect(pipeline.updateCount == 1)
}

@Test
@MainActor
func sourceLevelUpdatesUseStoredSourceCapabilities() {
    let pipeline = ConfigurableMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)
    let camera = store.sources.first { $0.kind == .camera }!
    let forgedMicrophone = StudioSource(
        id: camera.id,
        kind: .microphone,
        title: "Forged Mic",
        level: 0.2
    )

    store.updateLevel(for: forgedMicrophone, level: 0)

    #expect(store.sourceLevel(.camera) == 1)
    #expect(pipeline.updateCount == 1)
}

@Test
@MainActor
func sourceTogglesPreserveMediaPerformanceProfile() {
    let pipeline = ConfigurableMediaPipeline()
    let store = StudioStore(
        mediaPipeline: pipeline,
        preferences: StudioPreferences(performanceMode: .efficiency)
    )
    let systemAudio = store.sources.first { $0.kind == .systemAudio }!

    store.toggleSource(systemAudio)

    var expected = StudioPerformanceMode.efficiency.mediaConfiguration
    expected.sceneKind = .brb
    expected.systemAudioLevel = 0.72
    expected.capturesSystemAudio = true
    #expect(pipeline.lastConfiguration == expected)
}

@Test
@MainActor
func selectedSceneUpdatesMediaPipelineConfiguration() throws {
    let pipeline = ConfigurableMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)
    let screenAndFaceScene = try #require(store.scenes.first { $0.kind == .screenAndFace })

    store.selectScene(screenAndFaceScene)

    #expect(pipeline.lastConfiguration?.sceneKind == .screenAndFace)
}

@Test
@MainActor
func applyingDirectorRecommendationUpdatesMediaPipelineScene() throws {
    let pipeline = ConfigurableMediaPipeline()
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: false,
            speechLevel: 0.04,
            screenMotion: 0.1,
            hasFace: true,
            activeApplication: "Keynote",
            isScreenFrozen: true
        )
    )
    let store = StudioStore(mediaPipeline: pipeline, signalProvider: provider)

    #expect(store.selectedSceneKind == .brb)
    #expect(pipeline.lastConfiguration?.sceneKind == .brb)

    store.advanceDirector()
    #expect(store.recommendation?.target == .face)

    store.applyRecommendation()

    #expect(store.selectedSceneKind == .face)
    #expect(pipeline.lastConfiguration?.sceneKind == .face)
}

@Test
@MainActor
func cameraEnhancementsUpdateMediaPipelineConfiguration() {
    let pipeline = ConfigurableMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)
    let enhancements = CameraEnhancementSettings(
        mirrorsPreview: false,
        rotation: .degrees90,
        usesAutoLight: true,
        autoLightAmount: 0.68
    )

    store.updateCameraEnhancements(enhancements)

    #expect(pipeline.lastConfiguration?.cameraEnhancements == enhancements)
}

@Test
@MainActor
func outputAndLayoutPreferencesUpdateMediaPipelineConfiguration() {
    let pipeline = ConfigurableMediaPipeline()
    let layoutSettings = StudioLayoutSettings(
        preset: .screen70Webcam30,
        backgroundStyle: .studio,
        screenZoom: 1.2,
        webcamZoom: 0.85
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        preferences: StudioPreferences(
            performanceMode: .efficiency,
            outputResolution: .ultraHD4K,
            outputFrameRate: .fps60,
            previewRenderQuality: .full,
            layoutSettings: layoutSettings
        )
    )

    #expect(pipeline.lastConfiguration?.maxVideoWidth == 3_840)
    #expect(pipeline.lastConfiguration?.framesPerSecond == 60)
    #expect(pipeline.lastConfiguration?.videoBitrate == StudioStore.outputVideoBitrate(maxVideoWidth: 3_840, framesPerSecond: 60))
    #expect(pipeline.lastConfiguration?.layoutSettings == layoutSettings)
    #expect(store.currentOutputResolutionWidth == 3_840)
    #expect(store.currentOutputFrameRate == 60)
    #expect(store.currentPreviewCaptureConfiguration == StudioPerformanceMode.efficiency.previewCaptureConfiguration)
}

@Test
@MainActor
func activeStreamStagesOutputChangesButAppliesLayoutImmediately() async throws {
    let pipeline = ConfigurableMediaPipeline()
    let store = StudioStore(
        mediaPipeline: pipeline,
        preferences: StudioPreferences(
            performanceMode: .balanced,
            outputResolution: .hd720,
            outputFrameRate: .fps30
        )
    )
    let selectedScreenScene = try #require(store.scenes.first { $0.kind == .screenOnly })
    let liveLayout = StudioLayoutSettings(
        preset: .screen70Webcam30,
        backgroundStyle: .stage,
        screenZoom: 1.3,
        webcamZoom: 0.9
    )

    store.selectScene(selectedScreenScene)
    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.isLive)
    #expect(!store.canEditOutputCaptureSettings)
    #expect(pipeline.configurationAtStartStream?.maxVideoWidth == 1_280)
    #expect(pipeline.configurationAtStartStream?.framesPerSecond == 30)

    var preferences = store.preferences
    preferences.outputResolution = .ultraHD4K
    preferences.outputFrameRate = .fps60
    preferences.layoutSettings = liveLayout
    store.updatePreferences(preferences)

    #expect(store.currentOutputResolutionWidth == 1_280)
    #expect(store.currentOutputFrameRate == 30)
    #expect(pipeline.lastConfiguration?.maxVideoWidth == 1_280)
    #expect(pipeline.lastConfiguration?.framesPerSecond == 30)
    #expect(pipeline.lastConfiguration?.layoutSettings == liveLayout)

    store.stopStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.canEditOutputCaptureSettings)
    #expect(store.currentOutputResolutionWidth == 3_840)
    #expect(store.currentOutputFrameRate == 60)
    #expect(pipeline.lastConfiguration?.maxVideoWidth == 3_840)
    #expect(pipeline.lastConfiguration?.framesPerSecond == 60)
}

@Test
@MainActor
func transientCanvasLayoutUpdatesPipelineWithoutPersistingPreferences() {
    let pipeline = ConfigurableMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)
    let persistedLayout = store.preferences.layoutSettings
    var transientLayout = StudioLayoutSettings(
        preset: .pictureInPicture,
        presenterComposition: StudioPresenterCompositionSettings(
            mode: .presenterOverlay,
            placement: .manual,
            manualPosition: StudioNormalizedPoint(x: 0.2, y: 0.8),
            scale: 0.35
        )
    )
    transientLayout.screenViewport = StudioSourceViewportSettings(zoom: 1.4, panX: 0.5, panY: -0.25)
    transientLayout.webcamViewport = StudioSourceViewportSettings(zoom: 1.2)

    store.previewLayoutSettings(transientLayout)

    #expect(store.preferences.layoutSettings == persistedLayout)
    #expect(pipeline.lastConfiguration?.layoutSettings == transientLayout)

    store.previewLayoutSettings(nil)

    #expect(store.preferences.layoutSettings == persistedLayout)
    #expect(pipeline.lastConfiguration?.layoutSettings == persistedLayout)

    store.previewLayoutSettings(transientLayout)
    store.commitLayoutSettings(transientLayout)

    #expect(store.preferences.layoutSettings == transientLayout)
    #expect(pipeline.lastConfiguration?.layoutSettings == transientLayout)
}

@MainActor
private func waitForStudioState(_ predicate: @MainActor () -> Bool) async {
    for _ in 0..<200 {
        if predicate() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}
