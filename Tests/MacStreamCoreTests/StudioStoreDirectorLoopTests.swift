import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import Network
import Testing
@testable import MacStreamCore

@Test
@MainActor
func studioStoreStartsOnNonCapturingScene() {
    let store = StudioStore()

    #expect(store.selectedSceneKind == .brb)
}

@Test
@MainActor
func sceneSelectionUsesStoreActionPath() {
    let store = StudioStore()
    let faceScene = store.scenes.first { $0.kind == .face }!

    store.selectScene(faceScene)

    #expect(store.selectedSceneID == faceScene.id)
    #expect(store.selectedSceneKind == .face)
    #expect(store.recommendation == nil)
    #expect(store.events[0].title == "Scene changed")
    #expect(store.events[0].detail == "Face")
}

@Test
@MainActor
func selectingCurrentSceneIsNoOp() {
    let store = StudioStore()
    let currentScene = store.selectedScene
    let eventCount = store.events.count

    store.selectScene(currentScene)

    #expect(store.selectedSceneID == currentScene.id)
    #expect(store.events.count == eventCount)
    #expect(store.events[0].title == "Director armed")
}

@Test
@MainActor
func selectingUnknownSceneIsNoOp() {
    let store = StudioStore()
    let selectedSceneID = store.selectedSceneID
    let selectedSceneKind = store.selectedSceneKind
    let eventCount = store.events.count

    store.selectScene(StudioScene(kind: .face, title: "External", subtitle: "Not owned by this store"))

    #expect(store.selectedSceneID == selectedSceneID)
    #expect(store.selectedSceneKind == selectedSceneKind)
    #expect(store.events.count == eventCount)
}

@Test
func performanceModeControlsDisplayPreviewCaptureCost() {
    #expect(StudioPerformanceMode.efficiency.previewCaptureConfiguration == PreviewCaptureConfiguration(maxDisplayWidth: 960, framesPerSecond: 8, queueDepth: 1))
    #expect(StudioPerformanceMode.balanced.previewCaptureConfiguration == PreviewCaptureConfiguration(maxDisplayWidth: 1_280, framesPerSecond: 12, queueDepth: 2))
    #expect(StudioPerformanceMode.responsive.previewCaptureConfiguration == PreviewCaptureConfiguration(maxDisplayWidth: 1_920, framesPerSecond: 15, queueDepth: 3))
}

@Test
func previewCaptureConfigurationClampsValues() {
    #expect(PreviewCaptureConfiguration(maxDisplayWidth: 100, framesPerSecond: 1, queueDepth: 0) == PreviewCaptureConfiguration(maxDisplayWidth: 640, framesPerSecond: 5, queueDepth: 1))
    #expect(PreviewCaptureConfiguration(maxDisplayWidth: 4_000, framesPerSecond: 90, queueDepth: 12) == PreviewCaptureConfiguration(maxDisplayWidth: 1_920, framesPerSecond: 30, queueDepth: 4))
}

@Test
@MainActor
func studioStoreUsesInjectedSignalProvider() {
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: true,
            speechLevel: 0.76,
            screenMotion: 0.08,
            hasFace: true,
            activeApplication: "Notes"
        )
    )
    let store = StudioStore(signalProvider: provider)

    store.advanceDirector()

    #expect(store.latestSignals.speechLevel == 0.76)
    #expect(store.recommendation?.target == .face)
}

@Test
@MainActor
func studioStoreSamplesSystemPressureDuringDirectorTick() {
    let pressure = SystemPressureSnapshot(
        thermalPressure: .fair,
        memoryUsedMB: 512,
        physicalMemoryMB: 16_384
    )
    let store = StudioStore(performanceMonitor: FixedSystemPerformanceMonitor(snapshot: pressure))

    store.advanceDirector()

    #expect(store.systemPressure == pressure)
}

@Test
func systemPressureUsesMemoryFootprintForEfficiency() {
    let nominal = SystemPressureSnapshot(memoryUsedMB: 512, physicalMemoryMB: 16_384)
    let largeFootprint = SystemPressureSnapshot(memoryUsedMB: 2_048, physicalMemoryMB: 16_384)
    let highShare = SystemPressureSnapshot(memoryUsedMB: 1_024, physicalMemoryMB: 4_096)

    #expect(nominal.memoryUsagePercent == 3)
    #expect(!nominal.isMemoryConstrained)
    #expect(!nominal.shouldPreferEfficiency)
    #expect(nominal.efficiencyPressureDetail == nil)
    #expect(largeFootprint.isMemoryConstrained)
    #expect(largeFootprint.shouldPreferEfficiency)
    #expect(largeFootprint.efficiencyPressureDetail == "MacStream is using 2048 MB; Efficiency mode is safer.")
    #expect(highShare.memoryUsagePercent == 25)
    #expect(highShare.isMemoryConstrained)
    #expect(highShare.efficiencyPressureDetail == "MacStream is using 1024 MB; Efficiency mode is safer.")
}

@Test
@MainActor
func studioStoreWarnsAboutPerformancePressureWhenLive() async {
    let pressure = SystemPressureSnapshot(
        thermalPressure: .serious,
        memoryUsedMB: 900,
        physicalMemoryMB: 16_384
    )
    let store = StudioStore(
        mediaPipeline: SpyMediaPipeline(),
        performanceMonitor: FixedSystemPerformanceMonitor(snapshot: pressure)
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.advanceDirector()

    #expect(store.events.contains { $0.title == "Performance pressure" })
}

@Test
@MainActor
func studioStoreWarnsAboutMemoryPressureWhenLive() async {
    let pressure = SystemPressureSnapshot(
        thermalPressure: .nominal,
        memoryUsedMB: 2_048,
        physicalMemoryMB: 16_384
    )
    let store = StudioStore(
        mediaPipeline: SpyMediaPipeline(),
        performanceMonitor: FixedSystemPerformanceMonitor(snapshot: pressure)
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.advanceDirector()

    #expect(store.events.contains {
        $0.title == "Performance pressure" && $0.detail == "MacStream is using 2048 MB; Efficiency mode is safer."
    })
}

@Test
@MainActor
func studioStoreAppliesCountdownPreferenceToCue() {
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: true,
            speechLevel: 0.7,
            screenMotion: 0.08,
            hasFace: true,
            activeApplication: "Notes"
        )
    )
    let store = StudioStore(
        signalProvider: provider,
        preferences: StudioPreferences(directorCountdownSeconds: 5)
    )

    store.advanceDirector()

    #expect(store.recommendation?.delaySeconds == 5)
}

@Test
func studioPreferencesClampCountdownSeconds() throws {
    #expect(StudioPreferences(directorCountdownSeconds: -4).directorCountdownSeconds == 1)
    #expect(StudioPreferences(directorCountdownSeconds: 40).directorCountdownSeconds == 5)

    var preferences = StudioPreferences()
    preferences.directorCountdownSeconds = 0

    #expect(preferences.directorCountdownSeconds == 1)

    let legacyPreferences = """
    {
      "recordWhileStreaming": true,
      "directorCountdownSeconds": 99,
      "performanceMode": "responsive"
    }
    """
    let decoded = try JSONDecoder().decode(StudioPreferences.self, from: Data(legacyPreferences.utf8))

    #expect(decoded.recordWhileStreaming)
    #expect(decoded.directorCountdownSeconds == 5)
    #expect(decoded.performanceMode == .responsive)
    #expect(decoded.cameraEnhancements == CameraEnhancementSettings())
}

@Test
func cameraEnhancementSettingsNormalizeAndPersist() throws {
    let settings = CameraEnhancementSettings(
        mirrorsPreview: false,
        rotation: .degrees90,
        usesAutoLight: true,
        autoLightAmount: 1.7
    )
    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(CameraEnhancementSettings.self, from: encoded)

    #expect(settings.autoLightAmount == 1)
    #expect(decoded == settings)
    #expect(CameraPreviewRotation.degrees90.isSideways)
    #expect(CameraPreviewRotation.degrees270.isSideways)
    #expect(!CameraPreviewRotation.degrees0.isSideways)
}

@Test
@MainActor
func autoDirectorWaitsForCueCountdownBeforeSwitching() async {
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: true,
            speechLevel: 0.7,
            screenMotion: 0.08,
            hasFace: true,
            activeApplication: "Notes"
        )
    )
    let store = StudioStore(
        signalProvider: provider,
        preferences: StudioPreferences(directorCountdownSeconds: 1)
    )
    store.directorMode = .auto
    let startingScene = store.selectedSceneKind

    store.advanceDirector()

    #expect(store.selectedSceneKind == startingScene)
    #expect(store.recommendation?.target == .face)
    #expect(store.autoCueRemainingSeconds == 1)

    try? await Task.sleep(for: .milliseconds(1_200))

    #expect(store.selectedSceneKind == .face)
    #expect(store.recommendation == nil)
    #expect(store.autoCueRemainingSeconds == nil)
}

@Test
@MainActor
func holdingCueCancelsPendingAutoSwitch() async {
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: true,
            speechLevel: 0.7,
            screenMotion: 0.08,
            hasFace: true,
            activeApplication: "Notes"
        )
    )
    let store = StudioStore(
        signalProvider: provider,
        preferences: StudioPreferences(directorCountdownSeconds: 1)
    )
    store.directorMode = .auto
    let startingScene = store.selectedSceneKind

    store.advanceDirector()
    store.dismissRecommendation()

    #expect(store.autoCueRemainingSeconds == nil)
    #expect(store.recommendation == nil)

    try? await Task.sleep(for: .milliseconds(1_200))

    #expect(store.selectedSceneKind == startingScene)
    #expect(store.autoCueRemainingSeconds == nil)
}

@Test
@MainActor
func dismissingMissingRecommendationIsNoOp() {
    let store = StudioStore()
    let eventCount = store.events.count

    store.dismissRecommendation()

    #expect(store.recommendation == nil)
    #expect(store.autoCueRemainingSeconds == nil)
    #expect(store.events.count == eventCount)
    #expect(store.events[0].title == "Director armed")
}

@Test
@MainActor
func autoDirectorAppliesImmediateSafetyCueWithoutCountdown() {
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
    let store = StudioStore(signalProvider: provider)
    store.directorMode = .auto

    store.advanceDirector()

    #expect(store.selectedSceneKind == .face)
    #expect(store.recommendation == nil)
    #expect(store.autoCueRemainingSeconds == nil)
}

@Test
@MainActor
func studioStoreAppliesPerformanceModeToSignalProvider() {
    let provider = ConfigurableSignalProvider()
    let store = StudioStore(
        signalProvider: provider,
        preferences: StudioPreferences(performanceMode: .efficiency)
    )

    #expect(provider.lastConfiguration == StudioPerformanceMode.efficiency.signalSamplingConfiguration)

    store.updatePreferences(StudioPreferences(performanceMode: .responsive))

    #expect(provider.lastConfiguration == StudioPerformanceMode.responsive.signalSamplingConfiguration)
}

@Test
@MainActor
func pausedDirectorModeDoesNotStartSignalLoopWhenStreamStarts() async {
    let provider = ConfigurableSignalProvider()
    let store = StudioStore(
        mediaPipeline: ConfigurableMediaPipeline(),
        signalProvider: provider
    )

    store.directorMode = .paused
    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.isLive)
    #expect(provider.startCount == 0)
    #expect(provider.stopCount == 0)
    #expect(store.recommendation == nil)
}

@Test
@MainActor
func offlineDirectorLoopStartDoesNotStartSignalSampling() {
    let provider = ConfigurableSignalProvider()
    let store = StudioStore(signalProvider: provider)
    let updateCount = provider.updateCount

    store.startDirectorLoop()

    #expect(!store.isLive)
    #expect(provider.updateCount == updateCount)
    #expect(provider.startCount == 0)
    #expect(provider.stopCount == 0)
    #expect(store.autoCueRemainingSeconds == nil)
}

@Test
@MainActor
func directorLoopRestartsWhenLeavingPausedModeWhileLive() async {
    let provider = ConfigurableSignalProvider()
    let store = StudioStore(
        mediaPipeline: ConfigurableMediaPipeline(),
        signalProvider: provider
    )

    store.directorMode = .paused
    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    store.directorMode = .suggest

    #expect(provider.startCount == 1)

    store.directorMode = .paused

    #expect(provider.stopCount == 1)
}

@Test
@MainActor
func redundantDirectorModeWritesDoNotRestartSignalLoop() async {
    let provider = ConfigurableSignalProvider()
    let store = StudioStore(
        mediaPipeline: ConfigurableMediaPipeline(),
        signalProvider: provider
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(provider.startCount == 1)

    store.directorMode = .suggest

    #expect(provider.startCount == 1)
    #expect(provider.stopCount == 0)

    store.directorMode = .paused

    #expect(provider.stopCount == 1)

    store.directorMode = .paused

    #expect(provider.stopCount == 1)
}

@Test
@MainActor
func directorSamplesImmediatelyWhenStreamStarts() async {
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: true,
            speechLevel: 0.76,
            screenMotion: 0.08,
            hasFace: true,
            activeApplication: "Notes"
        )
    )
    let store = StudioStore(
        mediaPipeline: ConfigurableMediaPipeline(),
        signalProvider: provider
    )

    store.startStream()
    for _ in 0..<10 {
        if store.recommendation != nil { break }
        await Task.yield()
    }

    #expect(store.streamState == .live)
    #expect(store.recommendation?.target == .face)
}

@Test
@MainActor
func studioStoreSkipsRedundantPerformanceConfigurationUpdates() {
    let pipeline = ConfigurableMediaPipeline()
    let provider = ConfigurableSignalProvider()
    let store = StudioStore(
        mediaPipeline: pipeline,
        signalProvider: provider,
        preferences: StudioPreferences(performanceMode: .balanced)
    )

    #expect(pipeline.updateCount == 1)
    #expect(provider.updateCount == 1)

    store.updatePreferences(StudioPreferences(performanceMode: .balanced))

    #expect(pipeline.updateCount == 1)
    #expect(provider.updateCount == 1)

    store.updatePreferences(StudioPreferences(performanceMode: .responsive))

    #expect(pipeline.updateCount == 2)
    #expect(provider.updateCount == 2)

    store.updatePreferences(StudioPreferences(performanceMode: .responsive))

    #expect(pipeline.updateCount == 2)
    #expect(provider.updateCount == 2)
}
