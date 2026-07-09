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
    #expect(store.events[0].detail == "Webcam")
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
    #expect(decoded.outputResolution == .automatic)
    #expect(decoded.outputFrameRate == .automatic)
    #expect(decoded.previewRenderQuality == .automatic)
    #expect(decoded.layoutSettings == StudioLayoutSettings())
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
func outputAndLayoutPreferencesNormalizeAndPersist() throws {
    let layoutSettings = StudioLayoutSettings(
        preset: .screen70Webcam30,
        backgroundStyle: .stage,
        canvasPadding: 0.5,
        screenZoom: 0.2,
        webcamZoom: 3.4,
        sourceGap: 2,
        sourceCornerRadius: 0.234
    )
    let preferences = StudioPreferences(
        outputResolution: .ultraHD4K,
        outputFrameRate: .fps60,
        previewRenderQuality: .half,
        layoutSettings: layoutSettings
    )
    let encoded = try JSONEncoder().encode(preferences)
    let decoded = try JSONDecoder().decode(StudioPreferences.self, from: encoded)

    #expect(layoutSettings.screenZoom == StudioLayoutSettings.minimumSourceZoom)
    #expect(layoutSettings.webcamZoom == StudioLayoutSettings.maximumSourceZoom)
    #expect(layoutSettings.canvasPadding == StudioLayoutSettings.maximumCanvasPadding)
    #expect(layoutSettings.sourceGap == StudioLayoutSettings.maximumSourceGap)
    #expect(layoutSettings.sourceCornerRadius == StudioLayoutSettings.maximumSourceCornerRadius)
    #expect(decoded.outputResolution == .ultraHD4K)
    #expect(decoded.outputFrameRate == .fps60)
    #expect(decoded.previewRenderQuality == .half)
    #expect(decoded.layoutSettings == layoutSettings)

    let persistedLayout = """
    {"preset":"evenSplit","backgroundStyle":"warm","screenZoom":0.1,"webcamZoom":4.2}
    """
    let decodedLayout = try JSONDecoder().decode(
        StudioLayoutSettings.self,
        from: Data(persistedLayout.utf8)
    )
    #expect(decodedLayout.preset == .evenSplit)
    #expect(decodedLayout.backgroundStyle == .warm)
    #expect(decodedLayout.canvasPadding == 0.04)
    #expect(decodedLayout.screenZoom == StudioLayoutSettings.minimumSourceZoom)
    #expect(decodedLayout.webcamZoom == StudioLayoutSettings.maximumSourceZoom)
    #expect(decodedLayout.screenViewport == StudioSourceViewportSettings(zoom: 0.1))
    #expect(decodedLayout.webcamViewport == StudioSourceViewportSettings(zoom: 4.2))
    #expect(decodedLayout.sourceGap == StudioLayoutSettings.defaultSourceGap(canvasPadding: 0.04))
    #expect(decodedLayout.sourceCornerRadius == StudioLayoutSettings.defaultSourceCornerRadius)
}

@Test
func sourceViewportSettingsNormalizeZoomAndPan() {
    var viewport = StudioSourceViewportSettings(
        zoom: .infinity,
        panX: .nan,
        panY: -1.337
    )

    #expect(viewport.zoom == 1)
    #expect(viewport.panX == 0)
    #expect(viewport.panY == -1)

    viewport.zoom = 1.234
    viewport.panX = 0.456
    viewport.panY = -.infinity

    #expect(viewport.zoom == 1.23)
    #expect(viewport.panX == 0.46)
    #expect(viewport.panY == 0)
}

@Test
func layoutSettingsDecodeNewViewportFieldsAheadOfLegacyZooms() throws {
    let persistedLayout = """
    {
      "preset": "screen70Webcam30",
      "backgroundStyle": "stage",
      "canvasPadding": 0.046,
      "screenZoom": 0.8,
      "webcamZoom": 1.8,
      "screenViewport": { "zoom": 1.257, "panX": 0.331, "panY": -0.777 },
      "webcamViewport": { "zoom": 1.112, "panX": -0.252, "panY": 0.244 },
      "sourceGap": 0.0316,
      "sourceCornerRadius": 0.0124
    }
    """

    let decodedLayout = try JSONDecoder().decode(
        StudioLayoutSettings.self,
        from: Data(persistedLayout.utf8)
    )

    #expect(decodedLayout.canvasPadding == 0.05)
    #expect(decodedLayout.screenViewport == StudioSourceViewportSettings(zoom: 1.257, panX: 0.331, panY: -0.777))
    #expect(decodedLayout.webcamViewport == StudioSourceViewportSettings(zoom: 1.112, panX: -0.252, panY: 0.244))
    #expect(decodedLayout.screenZoom == 1.26)
    #expect(decodedLayout.webcamZoom == 1.11)
    #expect(decodedLayout.sourceGap == 0.032)
    #expect(decodedLayout.sourceCornerRadius == 0.012)
}

@Test
func layoutSettingsRoundTripPersistsCanonicalCanvasValues() throws {
    let settings = StudioLayoutSettings(
        preset: .screen30Webcam70,
        background: .color(StudioRGBAColor(red: 0.1234, green: 2, blue: -.infinity, alpha: 0.7654)),
        canvasPadding: .nan,
        screenViewport: StudioSourceViewportSettings(zoom: 1.456, panX: 0.2, panY: -0.2),
        webcamViewport: StudioSourceViewportSettings(zoom: 0.912, panX: -0.4, panY: 0.4),
        sourceGap: .infinity,
        sourceCornerRadius: .nan
    )
    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(StudioLayoutSettings.self, from: encoded)

    #expect(settings.canvasPadding == 0.04)
    #expect(settings.sourceGap == StudioLayoutSettings.defaultSourceGap(canvasPadding: 0.04))
    #expect(settings.sourceCornerRadius == StudioLayoutSettings.defaultSourceCornerRadius)
    #expect(decoded == settings)
    #expect(decoded.backgroundStyle == .black)
    #expect(decoded.background == .color(StudioRGBAColor(red: 0.123, green: 1, blue: 1, alpha: 0.765)))
}

@Test
func canvasBackgroundSupportsLegacyPresetCustomColorAndLocalImage() throws {
    let legacyBackground = try JSONDecoder().decode(
        StudioCanvasBackground.self,
        from: Data(#""warm""#.utf8)
    )
    let customColor = StudioCanvasBackground.color(
        StudioRGBAColor(red: -1, green: 0.3336, blue: .infinity, alpha: .nan)
    )
    let localImage = StudioCanvasBackground.localImage(path: "/tmp/canvas-bg.png")

    #expect(legacyBackground == .preset(.warm))
    #expect(customColor == .color(StudioRGBAColor(red: 0, green: 0.334, blue: 1, alpha: 1)))
    #expect(try JSONDecoder().decode(StudioCanvasBackground.self, from: JSONEncoder().encode(customColor)) == customColor)
    #expect(try JSONDecoder().decode(StudioCanvasBackground.self, from: JSONEncoder().encode(localImage)) == localImage)
}

@Test
func studioCanvasLayoutAppliesPaddingAndSplitGap() {
    let settings = StudioLayoutSettings(
        preset: .screen70Webcam30,
        backgroundStyle: .stage,
        canvasPadding: 0.04
    )
    let layout = StudioCanvasLayout(
        size: CGSize(width: 1_920, height: 1_080),
        settings: settings
    )

    #expect(abs(layout.canvasInset - 43.2) < 0.001)
    #expect(layout.contentRect.minX == layout.canvasInset)
    #expect(layout.contentRect.minY == layout.canvasInset)
    #expect(abs(layout.sourceGap - (min(layout.contentRect.width, layout.contentRect.height) * settings.sourceGap)) < 0.001)
    #expect(abs(layout.splitScreenRect.width - ((layout.contentRect.width - layout.sourceGap) * 0.7)) < 0.001)
    #expect(abs(layout.splitWebcamRect.minX - (layout.splitScreenRect.maxX + layout.sourceGap)) < 0.001)
    #expect(layout.splitWebcamRect.maxX == layout.contentRect.maxX)
}

@Test
func studioCanvasLayoutUsesExplicitGapAndCornerRadius() {
    let settings = StudioLayoutSettings(
        preset: .evenSplit,
        canvasPadding: 0.1,
        sourceGap: 0.05,
        sourceCornerRadius: 0.025
    )
    let layout = StudioCanvasLayout(
        size: CGSize(width: 1_000, height: 500),
        settings: settings
    )

    #expect(layout.contentRect == CGRect(x: 50, y: 50, width: 900, height: 400))
    #expect(layout.sourceGap == 20)
    #expect(layout.sourceCornerRadius == 10)
    #expect(layout.splitScreenRect == CGRect(x: 50, y: 50, width: 440, height: 400))
    #expect(layout.splitWebcamRect == CGRect(x: 510, y: 50, width: 440, height: 400))
}

@Test
func studioCanvasLayoutAllowsEdgeToEdgeSources() {
    let settings = StudioLayoutSettings(
        preset: .evenSplit,
        canvasPadding: 0
    )
    let layout = StudioCanvasLayout(
        size: CGSize(width: 1_280, height: 720),
        settings: settings
    )

    #expect(layout.canvasInset == 0)
    #expect(layout.sourceGap == 0)
    #expect(layout.contentRect == layout.outputRect)
    #expect(layout.splitScreenRect.width == 640)
    #expect(layout.splitWebcamRect.width == 640)
}

@Test
@MainActor
func previewRenderQualityControlsPreviewCaptureCost() {
    #expect(StudioStore.previewCaptureConfiguration(
        for: .responsive,
        quality: .automatic,
        isRTMPPublishing: true
    ) == StudioPerformanceMode.liveStreamingPreviewConfiguration)
    #expect(StudioStore.previewCaptureConfiguration(
        for: .responsive,
        quality: .full,
        isRTMPPublishing: true
    ) == StudioPerformanceMode.responsive.previewCaptureConfiguration)
    #expect(StudioStore.previewCaptureConfiguration(
        for: .responsive,
        quality: .half,
        isRTMPPublishing: false
    ) == PreviewCaptureConfiguration(maxDisplayWidth: 960, framesPerSecond: 15, queueDepth: 1))

    let output = StudioStore.mediaConfiguration(
        StudioPerformanceMode.responsive.mediaConfiguration,
        outputResolution: .fullHD1080,
        outputFrameRate: .fps60
    )
    #expect(output.maxVideoWidth == 1_920)
    #expect(output.framesPerSecond == 60)
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
        signalProvider: provider,
        isDirectorRuntimeEnabled: true
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
func defaultDirectorRuntimeDoesNotStartSignalLoopWhenStreamStarts() async {
    let provider = ConfigurableSignalProvider()
    let store = StudioStore(
        mediaPipeline: ConfigurableMediaPipeline(),
        signalProvider: provider
    )

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
        signalProvider: provider,
        isDirectorRuntimeEnabled: true
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
        signalProvider: provider,
        isDirectorRuntimeEnabled: true
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
        signalProvider: provider,
        isDirectorRuntimeEnabled: true
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

@Test
@MainActor
func RecommendationExplanationPopulatesOnDemand() async throws {
    let snapshot = SignalSnapshot(
        isSpeaking: true,
        speechLevel: 0.76,
        screenMotion: 0.08,
        hasFace: true,
        activeApplication: "Notes"
    )
    let signalProvider = MutableSignalProvider(snapshot: snapshot)
    let explainingProvider = ExplainingProvider(explanationResult: .success("Cue used quiet-screen speech."))
    let store = StudioStore(
        intelligenceProvider: explainingProvider,
        signalProvider: signalProvider
    )

    store.advanceDirector()
    store.explainCurrentRecommendation()
    for _ in 0..<10 {
        if store.recommendationExplanation != nil { break }
        await Task.yield()
    }

    #expect(store.recommendationExplanation == "Cue used quiet-screen speech.")
    #expect(explainingProvider.requestedSnapshots.count == 1)
    let requestedSnapshot = try #require(explainingProvider.requestedSnapshots.first)
    #expect(requestedSnapshot.speechLevel == snapshot.speechLevel)
    #expect(requestedSnapshot.screenMotion == snapshot.screenMotion)
    #expect(requestedSnapshot.activeApplication == snapshot.activeApplication)
}

@Test
@MainActor
func RecommendationExplanationFallsBackToCueReasonOnProviderError() async throws {
    let signalProvider = MutableSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: true,
            speechLevel: 0.76,
            screenMotion: 0.08,
            hasFace: true,
            activeApplication: "Notes"
        )
    )
    let explainingProvider = ExplainingProvider(explanationResult: .failure(TestExplanationError()))
    let store = StudioStore(
        intelligenceProvider: explainingProvider,
        signalProvider: signalProvider
    )

    store.advanceDirector()
    let reason = try #require(store.recommendation?.reason)
    store.explainCurrentRecommendation()
    for _ in 0..<10 {
        if store.recommendationExplanation != nil { break }
        await Task.yield()
    }

    #expect(store.recommendationExplanation == reason)
}

@Test
@MainActor
func RecommendationExplanationClearsWhenRecommendationChanges() async throws {
    let firstSnapshot = SignalSnapshot(
        isSpeaking: true,
        speechLevel: 0.76,
        screenMotion: 0.08,
        hasFace: true,
        activeApplication: "Notes"
    )
    let signalProvider = MutableSignalProvider(snapshot: firstSnapshot)
    let explainingProvider = ExplainingProvider(explanationResult: .success("First explanation."))
    let store = StudioStore(
        intelligenceProvider: explainingProvider,
        signalProvider: signalProvider
    )

    store.advanceDirector()
    store.explainCurrentRecommendation()
    for _ in 0..<10 {
        if store.recommendationExplanation != nil { break }
        await Task.yield()
    }
    #expect(store.recommendationExplanation == "First explanation.")

    let secondSnapshot = SignalSnapshot(
        isSpeaking: true,
        speechLevel: 0.82,
        screenMotion: 0.72,
        hasFace: true,
        activeApplication: "Xcode"
    )
    signalProvider.currentSnapshot = secondSnapshot
    store.advanceDirector()

    #expect(store.recommendation?.target == .screenAndFace)
    #expect(store.recommendationExplanation == nil)
    #expect(store.latestRecommendationSnapshot?.speechLevel == secondSnapshot.speechLevel)
    #expect(store.latestRecommendationSnapshot?.screenMotion == secondSnapshot.screenMotion)
    #expect(store.latestRecommendationSnapshot?.activeApplication == secondSnapshot.activeApplication)
}

@Test
@MainActor
func RecommendationExplanationDoesNotMutateSceneState() async {
    let signalProvider = MutableSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: true,
            speechLevel: 0.76,
            screenMotion: 0.08,
            hasFace: true,
            activeApplication: "Notes"
        )
    )
    let explainingProvider = ExplainingProvider(explanationResult: .success("Display-only explanation."))
    let store = StudioStore(
        intelligenceProvider: explainingProvider,
        signalProvider: signalProvider
    )

    store.advanceDirector()
    let selectedSceneID = store.selectedSceneID
    let directorMode = store.directorMode
    let autoCueRemainingSeconds = store.autoCueRemainingSeconds
    let recommendationTarget = store.recommendation?.target
    let eventCount = store.events.count

    store.explainCurrentRecommendation()
    for _ in 0..<10 {
        if store.recommendationExplanation != nil { break }
        await Task.yield()
    }

    #expect(store.selectedSceneID == selectedSceneID)
    #expect(store.directorMode == directorMode)
    #expect(store.autoCueRemainingSeconds == autoCueRemainingSeconds)
    #expect(store.recommendation?.target == recommendationTarget)
    #expect(store.events.count == eventCount)
}
