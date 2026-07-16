import Foundation
import Observation

@MainActor
@Observable
public final class StudioStore {
    public static let defaultSetupPrompt = "I do coding streams with camera and screen."

    public private(set) var scenes: [StudioScene]
    public private(set) var sources: [StudioSource]
    public private(set) var selectedSceneID: StudioScene.ID
    public var directorMode: DirectorMode = .suggest {
        didSet {
            guard directorMode != oldValue else { return }
            directorModeDidChange()
        }
    }
    public private(set) var streamState: StreamState = .offline
    public private(set) var streamTransport: StreamTransportKind
    public private(set) var recordingState: RecordingState = .stopped
    public private(set) var lastRecordingURL: URL?
    public private(set) var health = StreamHealth()
    public private(set) var streamRecoveryMetrics = StreamRecoveryMetrics()
    public private(set) var systemPressure = SystemPressureSnapshot()
    public private(set) var latestSignals = SignalSnapshot()
    public private(set) var recommendation: DirectorRecommendation?
    public private(set) var latestRecommendationSnapshot: SignalSnapshot?
    public private(set) var recommendationExplanation: String?
    public private(set) var isExplainingRecommendation = false
    public private(set) var autoCueRemainingSeconds: Int?
    public private(set) var events: [StudioEvent] = []
    public private(set) var clipMarkers: [ClipMarker] = []
    public private(set) var latestClipExportURL: URL?
    public private(set) var latestSessionReportURL: URL?
    public var destination = StreamDestination() {
        didSet {
            guard !isRevertingDestinationChange else { return }
            guard destination != oldValue else { return }

            guard canEditDestination else {
                isRevertingDestinationChange = true
                destination = oldValue
                isRevertingDestinationChange = false
                return
            }

            destinationDidChange(from: oldValue)
        }
    }
    public var setupPrompt = StudioStore.defaultSetupPrompt
    public private(set) var setupSummary = "Talking + Screen preset ready."
    public private(set) var isGeneratingSetupPlan = false
    public private(set) var localIntelligenceStatus: LocalIntelligenceStatus
    public private(set) var directorProfile: DirectorProfile = .balanced
    public private(set) var preferences: StudioPreferences
    public private(set) var effectivePerformanceMode: StudioPerformanceMode
    public private(set) var captureReport = CapturePreflightReport()
    public private(set) var isScanningCapture = false
    public private(set) var hasRunInitialCaptureScan = false
    public private(set) var selectedScreenCaptureTarget: ScreenCaptureTarget?
    public private(set) var screenCaptureTargetPreference: ScreenCaptureTarget?
    public private(set) var selectedCameraDeviceID: String?
    public private(set) var cameraDeviceIDPreference: String?
    public private(set) var selectedMicrophoneDeviceID: String?
    public private(set) var microphoneDeviceIDPreference: String?
    public private(set) var streamStartAttempt = 0
    public private(set) var streamStartMaxAttempts = 1
    public private(set) var isStreamStopping = false
    public private(set) var isRecordingStopping = false

    private var director = DirectorEngine()
    private let mediaPipeline: any MediaPipeline
    private var intelligenceProvider: any LocalIntelligenceProvider
    private let captureDeviceProvider: any CaptureDeviceProvider
    private let signalProvider: any SignalProvider
    private let performanceMonitor: any SystemPerformanceMonitor
    private let streamStartRetryPolicy: StreamStartRetryPolicy
    private let isDirectorRuntimeEnabled: Bool
    @ObservationIgnored private var directorLoopTask: Task<Void, Never>?
    @ObservationIgnored private var mediaHealthLoopTask: Task<Void, Never>?
    @ObservationIgnored private var sourceMonitoringTask: Task<Void, Never>?
    @ObservationIgnored private var streamStartTask: Task<Void, Never>?
    @ObservationIgnored private var streamStartID: UUID?
    @ObservationIgnored private var streamRecoveryStartedAt: ContinuousClock.Instant?
    @ObservationIgnored private var streamStopTask: Task<Void, Never>?
    @ObservationIgnored private var setupGenerationTask: Task<Void, Never>?
    @ObservationIgnored private var setupGenerationID: UUID?
    @ObservationIgnored private var recommendationExplanationTask: Task<Void, Never>?
    @ObservationIgnored private var recommendationExplanationID: UUID?
    @ObservationIgnored private var autoCueTask: Task<Void, Never>?
    @ObservationIgnored private var pendingAutoRecommendation: DirectorRecommendation?
    @ObservationIgnored private var recordingStartTask: Task<Void, Never>?
    @ObservationIgnored private var recordingStartID: UUID?
    @ObservationIgnored private var recordingStopTask: Task<Void, Never>?
    @ObservationIgnored private var lifecycleShutdownTask: Task<Void, Never>?
    @ObservationIgnored private var recordingOwnedByStream = false
    @ObservationIgnored private var lastAutomaticClipMarkerAt: Date?
    @ObservationIgnored private var lastPerformanceWarningAt: Date?
    @ObservationIgnored private var isCaptureUnderPressure = false
    @ObservationIgnored private var activeHealthDegradationReason: String?
    @ObservationIgnored private var lastObservedDroppedFrames = 0
    @ObservationIgnored private var lastObservedRTMPAudioAppendRejections = 0
    @ObservationIgnored private var captureHealthRecoverySampleCount = 0
    @ObservationIgnored private var zeroCaptureFPSObservedAt: ContinuousClock.Instant?
    @ObservationIgnored private var hasOpenCaptureSession = false
    @ObservationIgnored private var lastAppliedSignalConfiguration: SignalSamplingConfiguration?
    @ObservationIgnored private var lastAppliedMediaConfiguration: MediaPipelineConfiguration?
    @ObservationIgnored private var isSignalProviderActive = false
    @ObservationIgnored private var isRevertingDestinationChange = false
    @ObservationIgnored private var activeOutputCaptureSettings: OutputCaptureSettings?
    private static let requiredCaptureHealthRecoverySamples = 2
    static let zeroCaptureFPSPressureDelay: Duration = .seconds(2)
    private static let sourceMonitoringSampleIntervalMilliseconds = 250
    private static let maxRetainedEvents = 40
    private static let maxClipMarkerReasonCharacters = 240

    private struct OutputCaptureSettings: Equatable {
        var resolution: StreamOutputResolution
        var frameRate: StreamFrameRate
    }

    public init(
        mediaPipeline: any MediaPipeline = PreviewMediaPipeline(),
        intelligenceProvider: any LocalIntelligenceProvider = StubLocalIntelligenceProvider(),
        captureDeviceProvider: any CaptureDeviceProvider = SystemCaptureDeviceProvider(),
        signalProvider: any SignalProvider = PreviewSignalProvider(),
        performanceMonitor: any SystemPerformanceMonitor = PreviewSystemPerformanceMonitor(),
        preferences: StudioPreferences = StudioPreferences(),
        streamStartRetryPolicy: StreamStartRetryPolicy = .rtmpStartup,
        isDirectorRuntimeEnabled: Bool = false
    ) {
        let initialPressure = SystemPressureSnapshot()
        let initialEffectivePerformanceMode = preferences.performanceMode.effectiveMode(for: initialPressure)

        self.mediaPipeline = mediaPipeline
        self.intelligenceProvider = intelligenceProvider
        self.captureDeviceProvider = captureDeviceProvider
        self.signalProvider = signalProvider
        self.performanceMonitor = performanceMonitor
        self.preferences = preferences
        self.streamStartRetryPolicy = streamStartRetryPolicy
        self.isDirectorRuntimeEnabled = isDirectorRuntimeEnabled
        self.effectivePerformanceMode = initialEffectivePerformanceMode
        self.localIntelligenceStatus = intelligenceProvider.status
        self.streamTransport = Self.streamTransport(for: StreamDestination(), pipelineTransport: mediaPipeline.streamTransport)

        let initialScenes = [
            StudioScene(kind: .face, subtitle: "Webcam-led explanation"),
            StudioScene(kind: .screenAndFace, subtitle: "Screen share with webcam"),
            StudioScene(kind: .screenOnly, subtitle: "Full focus on the work"),
            StudioScene(kind: .brb, subtitle: "Quiet idle fallback")
        ]
        let initialSources = [
            StudioSource(kind: .camera, title: "FaceTime Camera"),
            StudioSource(kind: .screen, title: "Main Display"),
            StudioSource(kind: .microphone, title: "Studio Mic"),
            StudioSource(kind: .systemAudio, title: "Mac Audio", isEnabled: false, level: 0.72)
        ]

        self.scenes = initialScenes
        self.sources = initialSources
        self.selectedSceneID = initialScenes[3].id
        addEvent(kind: .director, title: "Director armed", detail: "Suggest mode is ready.")
        applyPerformanceConfiguration()
    }

    public var selectedScene: StudioScene {
        scenes.first { $0.id == selectedSceneID } ?? scenes[0]
    }

    public var selectedSceneKind: SceneKind {
        selectedScene.kind
    }

    public var sourceConfiguration: [StudioSourceConfiguration] {
        sources.map(StudioSourceConfiguration.init(source:))
    }

    public static func boundedSetupPrompt(_ prompt: String) -> String {
        guard prompt.count > SetupPlanPromptBuilder.maxStreamDescriptionCharacters else { return prompt }
        return String(prompt.prefix(SetupPlanPromptBuilder.maxStreamDescriptionCharacters))
    }

    public var isLive: Bool {
        streamState.isLive
    }

    public var isStreamConnecting: Bool {
        if case .connecting = streamState { return true }
        return false
    }

    public var canStartStream: Bool {
        !streamState.isLive
            && !isStreamConnecting
            && !isStreamStopping
            && lifecycleShutdownTask == nil
            && !isRecordingStarting
            && !isRecordingStopping
            && destination.isReadyToStart
            && streamStartBlockedReason == nil
    }

    public var canStopStream: Bool {
        (streamState.isLive || isStreamConnecting) && !isStreamStopping
    }

    public var canEditDestination: Bool {
        !streamState.isLive && !isStreamConnecting && !isStreamStopping
    }

    public var canEditOutputCaptureSettings: Bool {
        !hasStartingOrActiveMediaCapture
    }

    public var isRecordingStarting: Bool {
        recordingState == .starting
    }

    public var canStartRecording: Bool {
        recordingState != .recording
            && recordingState != .starting
            && !isRecordingStopping
            && lifecycleShutdownTask == nil
            && !isStreamConnecting
            && !isStreamStopping
            && recordingStartBlockedReason == nil
    }

    public var canStopRecording: Bool {
        (recordingState == .recording || recordingState == .starting) && !isRecordingStopping
    }

    public var canGenerateSetupPlan: Bool {
        !isGeneratingSetupPlan && setupGenerationBlockedReason == nil
    }

    public var resourceUsageSnapshot: ResourceUsageSnapshot {
        let mediaConfiguration = currentMediaPipelineConfiguration
        let previewConfiguration = currentPreviewCaptureConfiguration
        let signalConfiguration = Self.signalSamplingConfiguration(
            for: effectivePerformanceMode,
            isRTMPPublishing: isRTMPPublishing
        )

        return ResourceUsageSnapshot(
            processMemoryMB: systemPressure.memoryUsedMB,
            memoryUsagePercent: systemPressure.memoryUsagePercent,
            thermalPressure: systemPressure.thermalPressure,
            isLowPowerModeEnabled: systemPressure.isLowPowerModeEnabled,
            streamTargetFPS: mediaConfiguration.framesPerSecond,
            streamActualFPS: health.captureFPS,
            streamDroppedFrames: health.droppedFrames,
            streamBitrateKbps: health.bitrateKbps,
            streamOutboundBytesPerSecond: health.outboundBytesPerSecond,
            streamPublishState: health.publishState,
            streamQueueDepth: mediaConfiguration.queueDepth,
            previewTargetFPS: previewConfiguration.framesPerSecond,
            previewMaxDisplayWidth: previewConfiguration.maxDisplayWidth,
            previewQueueDepth: previewConfiguration.queueDepth,
            directorSampleIntervalMilliseconds: Self.directorSampleIntervalMilliseconds(
                for: effectivePerformanceMode,
                isRTMPPublishing: isRTMPPublishing
            ),
            screenSignalFPS: signalConfiguration.screenMotionFramesPerSecond
        )
    }
    public var currentPreviewCaptureConfiguration: PreviewCaptureConfiguration {
        Self.previewCaptureConfiguration(
            for: effectivePerformanceMode,
            quality: preferences.previewRenderQuality,
            isRTMPPublishing: isRTMPPublishing
        )
    }

    public var mediaPreviewFrameSource: MediaPreviewFrameSource? {
        mediaPipeline.mediaPreviewFrameSource
    }

    public var shouldUseMediaOutputPreview: Bool {
        guard mediaPreviewFrameSource != nil else { return false }
        let isRealStreamActive = streamTransport == .rtmpPublish
            && (streamState.isLive || isStreamConnecting || isStreamStopping)
        let isRecordingActive = recordingState == .starting
            || recordingState == .recording
            || isRecordingStopping
        return isRealStreamActive || isRecordingActive
    }

    public var currentOutputResolutionWidth: Int {
        currentMediaPipelineConfiguration.maxVideoWidth
    }

    public var currentOutputFrameRate: Int {
        currentMediaPipelineConfiguration.framesPerSecond
    }

    public var outputCaptureSettingsLockedReason: String? {
        canEditOutputCaptureSettings
            ? nil
            : "Stop streaming or recording before changing resolution or FPS."
    }


    public var startBlockedReason: String? {
        streamStartBlockedReason
    }

    public var streamStartBlockedReason: String? {
        guard mediaPipeline.requiresCaptureReadinessForStart else { return nil }

        guard selectedSceneKind != .brb else {
            return "Choose Webcam, Screen + Webcam, or Screen before starting."
        }

        if !destination.isPreviewSession,
           !mediaPipeline.supportedSceneKindsForStream.contains(selectedSceneKind) {
            return Self.streamableScreenSceneRequiredReason
        }

        if mediaPipeline.requiresScreenCaptureVideoForStream,
           !destination.isPreviewSession,
           !selectedSceneUsesScreenCaptureVideo {
            return Self.streamableScreenSceneRequiredReason
        }

        return captureStartBlockedReason
    }

    public var recordingStartBlockedReason: String? {
        guard mediaPipeline.requiresCaptureReadinessForStart else { return nil }

        guard selectedSceneKind != .brb else {
            return "Choose Webcam, Screen + Webcam, or Screen before starting."
        }

        if !mediaPipeline.supportedSceneKindsForRecording.contains(selectedSceneKind) {
            return Self.recordableSceneRequiredReason
        }

        if mediaPipeline.requiresScreenCaptureVideoForRecording,
           !selectedSceneUsesScreenCaptureVideo {
            return Self.recordableSceneRequiredReason
        }

        return captureStartBlockedReason
    }

    public var captureStartBlockedReason: String? {
        guard mediaPipeline.requiresCaptureReadinessForStart else { return nil }

        let missingSceneSourceKinds = missingSelectedSceneSourceKinds
        guard missingSceneSourceKinds.isEmpty else {
            return "\(sourceRecoveryActionTitle(for: missingSceneSourceKinds)) \(Self.sourceListTitle(for: missingSceneSourceKinds)) for \(selectedScene.title) before starting."
        }

        let enabledSourceCount = sources.filter(\.isEnabled).count
        guard enabledSourceCount > 0 else {
            return "Enable at least one source before starting."
        }

        let readiness = captureReadiness
        switch readiness.state {
        case .ready:
            return nil
        case .unchecked:
            return "Check capture permissions before starting."
        case .checking:
            return "Finish checking capture permissions before starting."
        case .needsAccess, .needsRelaunch:
            return readiness.detail
        }
    }

    public var preflightAdvice: [PreflightAdvice] {
        PreflightCoach.advice(
            report: captureReport,
            sources: sources,
            selectedScene: selectedSceneKind,
            selectedScreenCaptureTarget: selectedScreenCaptureTarget,
            selectedCameraDeviceID: selectedCameraDeviceID,
            selectedMicrophoneDeviceID: selectedMicrophoneDeviceID,
            destination: destination,
            hasRunInitialCaptureScan: hasRunInitialCaptureScan,
            isScanningCapture: isScanningCapture
        )
    }

    public var availableScreenCaptureTargets: [ScreenCaptureTarget] {
        captureReport.screenCaptureTargets
    }

    public var availableCameraDevices: [CaptureDeviceInfo] {
        captureReport.devices.filter { $0.kind == .camera && $0.permission == .granted }
    }

    public var availableMicrophoneDevices: [CaptureDeviceInfo] {
        captureReport.devices.filter { $0.kind == .microphone && $0.permission == .granted }
    }

    public var canSelectInputDevice: Bool {
        canEditScreenCaptureTarget
    }

    public var missingRequiredCapturePermissionKinds: [CaptureDeviceKind] {
        guard hasRunInitialCaptureScan, !isScanningCapture else { return [] }
        return captureReport.missingPermissionKinds(
            requiredKinds: requiredCapturePermissionKinds
        )
    }

    public var promptableRequiredCapturePermissionKinds: [CaptureDeviceKind] {
        missingRequiredCapturePermissionKinds.filter { kind in
            !kind.requiresRestartAfterPermissionGrant
                && captureReport.permissionState(for: kind) == .notDetermined
        }
    }

    public var blockedRequiredCapturePermissionKinds: [CaptureDeviceKind] {
        missingRequiredCapturePermissionKinds.filter { kind in
            !kind.requiresRestartAfterPermissionGrant
                && captureReport.permissionState(for: kind) != nil
                && captureReport.permissionState(for: kind) != .notDetermined
        }
    }

    public var missingRequiredCaptureDeviceKinds: [CaptureDeviceKind] {
        missingRequiredCapturePermissionKinds.filter { kind in
            captureReport.permissionState(for: kind) == nil
        }
    }

    public var requiresRelaunchForRequiredCapturePermission: Bool {
        missingRequiredCapturePermissionKinds.contains { $0.requiresRestartAfterPermissionGrant }
    }

    public var canScanCaptureDevices: Bool {
        captureScanBlockedReason == nil
    }

    public var captureScanBlockedReason: String? {
        if isScanningCapture {
            return "Capture check is already running."
        }

        if isCaptureConfigurationLocked {
            return "Stop preview, stream, or recording before checking capture devices."
        }

        return nil
    }

    public var captureReadiness: CaptureReadiness {
        if isScanningCapture {
            return CaptureReadiness(
                state: .checking,
                title: "Checking",
                detail: captureReport.summary
            )
        }

        guard hasRunInitialCaptureScan else {
            return CaptureReadiness(
                state: .unchecked,
                title: "Not checked",
                detail: captureReport.summary
            )
        }

        let missingKinds = missingRequiredCapturePermissionKinds
        guard !missingKinds.isEmpty else {
            return CaptureReadiness(
                state: .ready,
                title: "Ready",
                detail: "Capture sources are ready."
            )
        }

        if missingKinds.contains(where: \.requiresRestartAfterPermissionGrant) {
            let otherKinds = missingKinds.filter { !$0.requiresRestartAfterPermissionGrant }
            let suffix = otherKinds.isEmpty
                ? ""
                : " \(Self.permissionListTitle(for: otherKinds)) also \(otherKinds.count == 1 ? "needs" : "need") access."
            return CaptureReadiness(
                state: .needsRelaunch,
                title: "Screen access",
                detail: "Grant Screen Recording, then reopen MacStream.\(suffix)"
            )
        }

        return CaptureReadiness(
            state: .needsAccess,
            title: "Needs access",
            detail: "\(Self.permissionListTitle(for: missingKinds)) \(missingKinds.count == 1 ? "needs" : "need") access."
        )
    }

    public var missingSelectedSceneSourceKinds: [SourceKind] {
        selectedSceneRequiredSourceKinds.filter { !isSourceReadyForSelectedScene($0) }
    }

    public var isSourceSetupReady: Bool {
        missingSelectedSceneSourceKinds.isEmpty && sources.contains(where: \.isEnabled)
    }

    public var sourceSetupTitle: String {
        let requiredKinds = selectedSceneRequiredSourceKinds
        let readyRequiredCount = requiredKinds.filter { isSourceReadyForSelectedScene($0) }.count
        if readyRequiredCount < requiredKinds.count {
            return "\(readyRequiredCount)/\(requiredKinds.count) ready"
        }

        return "\(sources.filter(\.isEnabled).count)/\(sources.count) on"
    }

    public var sourceSetupDetail: String {
        let missingSceneSourceKinds = missingSelectedSceneSourceKinds
        if !missingSceneSourceKinds.isEmpty {
            return "\(sourceRecoveryActionTitle(for: missingSceneSourceKinds)) \(Self.sourceListTitle(for: missingSceneSourceKinds)) for \(selectedScene.title)."
        }

        let enabledSources = sources
            .filter(\.isEnabled)
            .map(\.title)
            .joined(separator: ", ")
        return enabledSources.isEmpty ? "Enable at least one source." : enabledSources
    }

    public func setupRole(for sourceKind: SourceKind) -> SourceSetupRole {
        if selectedSceneRequiredSourceKinds.contains(sourceKind) {
            return .required
        }

        if selectedSceneKind != .brb, sourceKind == .microphone {
            return .recommended
        }

        if selectedSceneKind != .brb, sourceKind == .systemAudio {
            return .optional
        }

        return .unused
    }

    public var setupChecklistItems: [SetupChecklistItem] {
        [
            sceneSetupChecklistItem,
            captureSetupChecklistItem,
            destinationSetupChecklistItem,
            sourcesSetupChecklistItem
        ]
    }

    public var completedSetupItemCount: Int {
        setupChecklistItems.filter(\.isComplete).count
    }

    public var totalSetupItemCount: Int {
        setupChecklistItems.count
    }

    public var setupProgressFraction: Double {
        let total = totalSetupItemCount
        guard total > 0 else { return 1 }
        return Double(completedSetupItemCount) / Double(total)
    }

    public var nextSetupChecklistItem: SetupChecklistItem? {
        setupChecklistItems.first { !$0.isComplete }
    }

    public var shouldShowSetupChecklist: Bool {
        guard !streamState.isLive,
              !isStreamConnecting,
              recordingState != .recording,
              !isRecordingStarting
        else {
            return false
        }

        return setupChecklistItems.contains { !$0.isComplete }
    }

    public var canEditScreenCaptureTarget: Bool {
        !streamState.isLive
            && !isStreamConnecting
            && !isStreamStopping
            && recordingState != .recording
            && !isRecordingStarting
            && !isRecordingStopping
    }

    public var canMarkClip: Bool {
        (streamState.isLive || recordingState == .recording) && !isStreamStopping && !isRecordingStopping
    }

    public var canApplyRecommendation: Bool {
        guard let recommendation,
              recommendation.target != selectedSceneKind,
              let scene = scenes.first(where: { $0.kind == recommendation.target })
        else {
            return false
        }

        return canSelectScene(scene)
    }

    public var recommendationActionBlockedReason: String? {
        guard let recommendation,
              recommendation.target != selectedSceneKind
        else {
            return nil
        }

        guard let scene = scenes.first(where: { $0.kind == recommendation.target }) else {
            return "Cue scene is not available."
        }

        return sceneSelectionBlockedReason(for: scene)
    }

    public func canToggleSource(_ source: StudioSource) -> Bool {
        guard let currentSource = sources.first(where: { $0.id == source.id }) else { return false }
        guard currentSource.isEnabled,
              isCaptureConfigurationLocked,
              selectedSceneRequiredSourceKinds.contains(currentSource.kind)
        else {
            return true
        }

        return false
    }

    public func canAdjustSourceLevel(_ source: StudioSource) -> Bool {
        guard let currentSource = sources.first(where: { $0.id == source.id }),
              currentSource.kind.supportsLevelControl,
              currentSource.isEnabled
        else {
            return false
        }

        guard isCaptureConfigurationLocked,
              selectedSceneRequiredSourceKinds.contains(currentSource.kind)
        else {
            return true
        }

        return false
    }

    public func canSelectScene(_ scene: StudioScene) -> Bool {
        sceneSelectionBlockedReason(for: scene) == nil
    }

    public func sceneSelectionBlockedReason(for scene: StudioScene) -> String? {
        guard let scene = scenes.first(where: { $0.id == scene.id }) else {
            return "Scene is not available."
        }

        guard scene.id != selectedSceneID else { return nil }
        guard isCaptureConfigurationLocked else { return nil }

        if streamTransport != .preview,
           (streamState.isLive || isStreamConnecting || isStreamStopping),
           !mediaPipeline.supportedSceneKindsForStream.contains(scene.kind) {
            return "Stop real capture before choosing \(scene.title)."
        }

        if (recordingState == .recording || recordingState == .starting || isRecordingStopping),
           !mediaPipeline.supportedSceneKindsForRecording.contains(scene.kind) {
            return "Stop recording before choosing \(scene.title)."
        }

        if (recordingState == .recording || recordingState == .starting || isRecordingStopping),
           scene.kind != selectedSceneKind {
            return "Stop recording before switching recorded scenes."
        }

        if mediaPipeline.requiresScreenCaptureVideoForStream,
           streamTransport != .preview,
           (streamState.isLive || isStreamConnecting || isStreamStopping),
           !Self.sceneUsesScreenCaptureVideo(scene.kind) {
            return "Stop real capture before choosing Webcam or BRB."
        }

        if mediaPipeline.requiresScreenCaptureVideoForRecording,
           (recordingState == .recording || recordingState == .starting || isRecordingStopping),
           !Self.sceneUsesScreenCaptureVideo(scene.kind) {
            return "Stop recording before choosing Webcam or BRB."
        }

        let missingRequiredKinds = Self.requiredSourceKinds(for: scene.kind).filter { !isSourceEnabled($0) }
        guard missingRequiredKinds.isEmpty else {
            return "Enable \(Self.sourceListTitle(for: missingRequiredKinds)) before switching to \(scene.title)."
        }

        return nil
    }

    public var canExportClipMarkers: Bool {
        !clipMarkers.isEmpty
    }

    public var setupGenerationStatusDetail: String {
        if isGeneratingSetupPlan {
            return "Generating setup rules..."
        }

        return setupGenerationBlockedReason ?? localIntelligenceStatus.detail
    }

    public var recordingStatusDetail: String {
        if isRecordingStopping {
            return "Stopping local archive"
        }

        return recordingState.detail
    }

    public var streamStatusDetail: String {
        if isStreamStopping {
            return "Stopping stream"
        }

        return switch streamState {
        case .offline:
            destination.validationError ?? "Ready"
        case .connecting:
            switch streamTransport {
            case .preview:
                "Starting local preview session"
            case .endpointValidation:
                "Validating RTMP endpoint\(streamStartAttemptSuffix)"
            case .rtmpPublish:
                "Connecting RTMP publisher\(streamStartAttemptSuffix)"
            }
        case .live:
            switch streamTransport {
            case .preview:
                "Local preview running"
            case .endpointValidation:
                "Endpoint reachable"
            case .rtmpPublish:
                health.publishState == .publishing ? "Publishing media" : health.publishState.title
            }
        case let .degraded(reason):
            reason
        case let .failed(reason):
            reason
        }
    }

    public func selectScene(_ scene: StudioScene) {
        guard let scene = scenes.first(where: { $0.id == scene.id }) else { return }
        guard scene.id != selectedSceneID else { return }
        guard canSelectScene(scene) else { return }

        cancelPendingAutoCue()
        selectedSceneID = scene.id
        director.markSwitchAccepted()
        clearRecommendation()
        applyPerformanceConfiguration()
        addEvent(kind: .director, title: "Scene changed", detail: scene.title)
    }

    public func selectRecommendedStartingScene() {
        guard let scene = scenes.first(where: { $0.kind == .screenAndFace }) else { return }
        selectScene(scene)
    }

    public func applyLaunchSetupDefaults(defaultSceneKind: SceneKind?, setupPrompt: String) {
        applySavedSetupPrompt(setupPrompt)

        guard let defaultSceneKind,
              let scene = scenes.first(where: { $0.kind == defaultSceneKind })
        else {
            return
        }

        selectScene(scene)
    }

    public func applySavedDestination(_ savedDestination: StreamDestination) {
        guard canEditDestination, destination != savedDestination else { return }

        destination = savedDestination
    }

    public func applySavedSourceConfiguration(_ savedConfiguration: [StudioSourceConfiguration]) {
        guard !isCaptureConfigurationLocked, !savedConfiguration.isEmpty else { return }

        var nextSources = sources
        var didChange = false
        let configurationByKind = Dictionary(
            savedConfiguration.map { ($0.kind, $0) },
            uniquingKeysWith: { _, newest in newest }
        )

        for index in nextSources.indices {
            guard let configuration = configurationByKind[nextSources[index].kind] else { continue }

            let normalizedLevel = StudioSource.normalizedLevel(configuration.level)
            if nextSources[index].isEnabled != configuration.isEnabled {
                nextSources[index].isEnabled = configuration.isEnabled
                didChange = true
            }
            if nextSources[index].kind.supportsLevelControl,
               nextSources[index].level != normalizedLevel {
                nextSources[index].level = normalizedLevel
                didChange = true
            }
        }

        guard didChange else { return }

        sources = nextSources
        applyPerformanceConfiguration()
    }

    public func applySavedScreenCaptureTargetPreference(_ target: ScreenCaptureTarget?) {
        guard canEditScreenCaptureTarget, screenCaptureTargetPreference != target else { return }

        screenCaptureTargetPreference = target
        guard let target else { return }

        let availableTarget = availableScreenCaptureTargets.first { $0.id == target.id && $0.kind == target.kind }
        guard let availableTarget, selectedScreenCaptureTarget != availableTarget else { return }

        selectedScreenCaptureTarget = availableTarget
        applyPerformanceConfiguration()
    }

    public func applySavedCameraDeviceIDPreference(_ id: String?) {
        guard canSelectInputDevice, cameraDeviceIDPreference != id else { return }
        cameraDeviceIDPreference = id
        guard let id, let device = availableCameraDevices.first(where: { $0.id == id }), selectedCameraDeviceID != device.id else { return }
        selectedCameraDeviceID = device.id
        applyPerformanceConfiguration()
    }

    public func applySavedMicrophoneDeviceIDPreference(_ id: String?) {
        guard canSelectInputDevice, microphoneDeviceIDPreference != id else { return }
        microphoneDeviceIDPreference = id
        guard let id, let device = availableMicrophoneDevices.first(where: { $0.id == id }), selectedMicrophoneDeviceID != device.id else { return }
        selectedMicrophoneDeviceID = device.id
        applyPerformanceConfiguration()
    }

    public func applySavedSetupPrompt(_ prompt: String) {
        let boundedPrompt = Self.boundedSetupPrompt(prompt)
        guard setupPrompt != boundedPrompt else { return }

        setupPrompt = boundedPrompt
    }

    public func startStream() {
        guard canStartStream else { return }
        let startID = UUID()
        let startDestination = destination
        let retryPolicy = startDestination.isPreviewSession ? .none : streamStartRetryPolicy
        streamStartTask?.cancel()
        streamStartID = startID
        streamStartAttempt = 1
        streamStartMaxAttempts = retryPolicy.maxAttempts
        prepareCaptureSessionIfIdle()
        sampleSystemPressure()
        streamTransport = Self.streamTransport(for: startDestination, pipelineTransport: mediaPipeline.streamTransport)
        streamState = .connecting
        lockOutputCaptureSettingsIfNeeded()
        applyPerformanceConfiguration()
        cancelSetupGenerationIfNeeded(
            reason: startDestination.isPreviewSession
                ? "Stop preview before generating local setup rules."
                : "Stop streaming before generating local setup rules."
        )
        addEvent(kind: .stream, title: "Starting \(streamTransport.title)", detail: startDestination.safeDisplayDetail)

        streamStartTask = Task {
            do {
                try await startStreamWithRetry(
                    destination: startDestination,
                    policy: retryPolicy,
                    startID: startID
                )
                guard isCurrentStreamStart(startID) else {
                    return
                }
                streamStartTask = nil
                streamStartID = nil
                streamState = .live
                beginCaptureSession(
                    title: "Session started",
                    detail: startDestination.safeDisplayDetail
                )
                let mediaConfiguration = currentMediaPipelineConfiguration
                health = mediaPipeline.currentHealth ?? StreamHealth(
                    bitrateKbps: streamTransport == .rtmpPublish ? 0 : mediaConfiguration.videoBitrate / 1_000,
                    publishState: streamTransport == .rtmpPublish ? .handshaking : .publishing,
                    captureFPS: mediaConfiguration.framesPerSecond,
                    audioLevel: 0.42,
                    roundTripMs: 42
                )
                streamTransport = Self.streamTransport(for: startDestination, pipelineTransport: mediaPipeline.streamTransport)
                addEvent(kind: .stream, title: "\(streamTransport.title) ready", detail: streamTransport.detail)
                startDirectorLoop()
                syncMediaHealthLoop()
                if preferences.recordWhileStreaming {
                    startRecording(ownedByStream: true)
                }
            } catch {
                guard isCurrentStreamStart(startID) else { return }
                streamStartTask = nil
                streamStartID = nil
                streamState = .failed(error.localizedDescription)
                applyPerformanceConfiguration()
                releaseOutputCaptureSettingsIfIdle()
                health = StreamHealth()
                resetCaptureHealthPressure()
                cancelPendingAutoCue()
                stopDirectorLoop()
                syncMediaHealthLoop()
                addEvent(kind: .warning, title: "Stream failed", detail: error.localizedDescription)
            }
        }
    }

    public func stopStream() {
        guard canStopStream else { return }
        finishStreamRecovery(outcome: .cancelled)
        let shouldStopOwnedRecording = recordingOwnedByStream
        let pendingStartTask = streamStartTask
        pendingStartTask?.cancel()
        streamStartTask = nil
        streamStartID = nil
        streamStartAttempt = 0
        streamStartMaxAttempts = 1
        isStreamStopping = true
        clearRecommendation(cancelAutoCue: false)
        cancelPendingAutoCue()
        stopDirectorLoop()
        let stopTask = Task {
            await pendingStartTask?.value
            await mediaPipeline.stopStream()
            isStreamStopping = false
            streamState = .offline
            applyPerformanceConfiguration()
            health = StreamHealth()
            resetCaptureHealthPressure()
            syncMediaHealthLoop()
            if shouldStopOwnedRecording {
                stopRecording()
            }
            addEvent(kind: .stream, title: "Offline", detail: "Stream stopped.")
            endCaptureSessionIfIdle()
            releaseOutputCaptureSettingsIfIdle()
            streamStopTask = nil
        }
        streamStopTask = stopTask
    }

    public func startRecording() {
        startRecording(ownedByStream: false)
    }

    private func startRecording(ownedByStream: Bool) {
        guard canStartRecording else { return }
        let startID = UUID()
        recordingStartTask?.cancel()
        recordingStartID = startID
        recordingOwnedByStream = ownedByStream
        lockOutputCaptureSettingsIfNeeded()
        prepareCaptureSessionIfIdle()
        sampleSystemPressure()
        recordingState = .starting
        applyPerformanceConfiguration()
        cancelSetupGenerationIfNeeded(reason: "Stop recording before generating local setup rules.")
        addEvent(kind: .stream, title: "Recording", detail: "Preparing local archive.")

        recordingStartTask = Task {
            do {
                let url = try await mediaPipeline.startRecording()
                guard isCurrentRecordingStart(startID) else {
                    return
                }
                recordingStartTask = nil
                recordingStartID = nil
                recordingState = .recording
                for warning in mediaPipeline.captureSetupWarnings {
                    addWarningEventIfNeeded(title: "Recording degraded", detail: warning)
                }
                beginCaptureSession(
                    title: "Recording session started",
                    detail: url.lastPathComponent,
                    recordingURL: url
                )
                health = mediaPipeline.currentHealth ?? health
                addEvent(kind: .stream, title: "Recording", detail: url.lastPathComponent)
                syncMediaHealthLoop()
            } catch {
                guard isCurrentRecordingStart(startID) else { return }
                recordingStartTask = nil
                recordingStartID = nil
                recordingOwnedByStream = false
                recordingState = .failed(error.localizedDescription)
                applyPerformanceConfiguration()
                releaseOutputCaptureSettingsIfIdle()
                syncMediaHealthLoop()
                if !streamState.isLive {
                    resetCaptureHealthPressure()
                }
                addEvent(kind: .warning, title: "Recording failed", detail: error.localizedDescription)
            }
        }
    }

    public func stopRecording() {
        guard canStopRecording else { return }
        let pendingStartTask = recordingStartTask
        pendingStartTask?.cancel()
        recordingStartTask = nil
        recordingStartID = nil
        recordingOwnedByStream = false
        isRecordingStopping = true
        let stopTask = Task {
            await pendingStartTask?.value
            await mediaPipeline.stopRecording()
            let failureDetail = mediaPipeline.recordingFailureDetail
            isRecordingStopping = false
            if let failureDetail {
                recordingState = .failed(failureDetail)
            } else {
                recordingState = .stopped
            }
            applyPerformanceConfiguration()
            if !streamState.isLive {
                resetCaptureHealthPressure()
            }
            syncMediaHealthLoop()
            if let failureDetail {
                addWarningEventIfNeeded(title: "Recording failed", detail: failureDetail)
            } else {
                addEvent(kind: .stream, title: "Recording stopped", detail: "Local archive closed.")
            }
            endCaptureSessionIfIdle()
            releaseOutputCaptureSettingsIfIdle()
            recordingStopTask = nil
        }
        recordingStopTask = stopTask
    }

    public func shutdownForLifecycle() async {
        if let lifecycleShutdownTask {
            await lifecycleShutdownTask.value
            return
        }

        let shutdownTask = Task {
            await performLifecycleShutdown()
        }
        lifecycleShutdownTask = shutdownTask
        await shutdownTask.value
        lifecycleShutdownTask = nil
    }

    private func performLifecycleShutdown() async {
        stopSourceMonitoring()
        stopDirectorLoop()
        stopMediaHealthLoopIfNeeded()

        let pendingStreamStart = streamStartTask
        let pendingRecordingStart = recordingStartTask
        streamStartID = nil
        recordingStartID = nil
        pendingStreamStart?.cancel()
        pendingRecordingStart?.cancel()
        await pendingStreamStart?.value
        await pendingRecordingStart?.value

        if streamStopTask == nil, canStopStream {
            stopStream()
        }
        if let streamStopTask {
            await streamStopTask.value
        }

        if recordingStopTask == nil, canStopRecording {
            stopRecording()
        }
        if let recordingStopTask {
            await recordingStopTask.value
        }

        stopMediaHealthLoopIfNeeded()
        clearRecommendation()
        health = StreamHealth()
        resetCaptureHealthPressure()
        endCaptureSessionIfIdle()
        releaseOutputCaptureSettingsIfIdle()
    }

    public func toggleSource(_ source: StudioSource) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        guard canToggleSource(sources[index]) else { return }
        sources[index].isEnabled.toggle()
        applyPerformanceConfiguration()
        let state = sources[index].isEnabled ? "enabled" : "muted"
        addEvent(kind: .source, title: sources[index].title, detail: state)
    }

    public func enableRecommendedSources() {
        let recommendedKinds = recommendedSourceKindsForSelectedScene
        let repairableIndices = sources.indices.filter { index in
            guard recommendedKinds.contains(sources[index].kind) else { return false }
            return !sources[index].isEnabled
                || (sources[index].kind.supportsLevelControl && sources[index].level <= 0)
        }
        guard !repairableIndices.isEmpty else { return }

        for index in repairableIndices {
            sources[index].isEnabled = true
            if sources[index].kind.supportsLevelControl, sources[index].level <= 0 {
                sources[index].level = 1
            }
        }
        applyPerformanceConfiguration()
        addEvent(kind: .source, title: "Sources ready", detail: "Needed sources ready for \(selectedScene.title).")
    }

    public func updateLevel(for source: StudioSource, level: Double) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }),
              sources[index].kind.supportsLevelControl,
              canAdjustSourceLevel(sources[index])
        else { return }
        let normalizedLevel = StudioSource.normalizedLevel(level)
        guard sources[index].level != normalizedLevel else { return }
        sources[index].level = normalizedLevel
        applyPerformanceConfiguration()
    }

    public func isSourceEnabled(_ kind: SourceKind) -> Bool {
        sources.first(where: { $0.kind == kind })?.isEnabled ?? false
    }

    public func sourceLevel(_ kind: SourceKind) -> Double {
        sources.first(where: { $0.kind == kind })?.level ?? 0
    }

    public func setDestinationMode(_ mode: StreamDestinationMode) {
        guard canEditDestination, destination.mode != mode else { return }

        var nextDestination = destination
        nextDestination.mode = mode
        switch mode {
        case .preview:
            if nextDestination.name.isEmpty || nextDestination.name == "RTMP Destination" {
                nextDestination.name = "Preview Session"
            }
        case .rtmp:
            if nextDestination.name.isEmpty || nextDestination.name == "Preview Session" {
                nextDestination.name = "RTMP Destination"
            }
            if nextDestination.usesPreviewSentinelURL {
                nextDestination.rtmpURL = ""
            }
        }
        destination = nextDestination
    }


    public func setRTMPServerURL(_ serverURL: String) {
        guard canEditDestination else { return }
        var nextDestination = destination
        nextDestination.setRTMPServerURL(serverURL)
        guard nextDestination != destination else { return }
        destination = nextDestination
    }

    public func setRTMPStreamKey(_ streamKey: String) {
        guard canEditDestination else { return }
        var nextDestination = destination
        nextDestination.setRTMPStreamKey(streamKey)
        guard nextDestination != destination else { return }
        destination = nextDestination
    }
    public var matchingDestinationPreset: StreamPlatformPreset? {
        guard destination.mode == .rtmp else { return nil }
        let url = destination.rtmpURL.lowercased()
        guard !url.isEmpty else { return nil }
        return StreamPlatformPreset.allCases.first { preset in
            guard let base = preset.ingestURL?.lowercased() else { return false }
            return url.hasPrefix(base)
        }
    }

    public func applyDestinationPreset(_ preset: StreamPlatformPreset) {
        guard canEditDestination else { return }

        var nextDestination = destination
        nextDestination.mode = .rtmp
        if nextDestination.name.isEmpty
            || nextDestination.name == "Preview Session"
            || nextDestination.name == "RTMP Destination"
            || StreamPlatformPreset.allCases.contains(where: { $0.title == nextDestination.name }) {
            nextDestination.name = preset.title
        }
        if let ingestURL = preset.ingestURL {
            // Preserve an already-entered stream key for this platform; only (re)set the base
            // when the current URL isn't already this preset's endpoint.
            if !nextDestination.rtmpURL.lowercased().hasPrefix(ingestURL.lowercased()) {
                nextDestination.rtmpURL = ingestURL
            }
        } else if nextDestination.usesPreviewSentinelURL || urlBelongsToKnownPlatform(nextDestination.rtmpURL) {
            // Account- or broadcast-specific endpoint (X / Kick / Custom): the user must paste it.
            // Drop a URL carried over from a different known platform (or the preview sentinel),
            // but keep a custom URL the user already typed.
            nextDestination.rtmpURL = ""
        }

        guard destination != nextDestination else { return }
        destination = nextDestination
        addEvent(kind: .stream, title: "Destination preset", detail: preset.title)
    }

    private func urlBelongsToKnownPlatform(_ rtmpURL: String) -> Bool {
        let lowered = rtmpURL.lowercased()
        guard !lowered.isEmpty else { return false }
        return StreamPlatformPreset.allCases.contains { preset in
            guard let base = preset.ingestURL?.lowercased() else { return false }
            return lowered.hasPrefix(base)
        }
    }

    public func selectScreenCaptureTarget(_ target: ScreenCaptureTarget) {
        guard canEditScreenCaptureTarget else { return }
        guard selectedScreenCaptureTarget != target else {
            screenCaptureTargetPreference = target
            return
        }

        screenCaptureTargetPreference = target
        selectedScreenCaptureTarget = target
        applyPerformanceConfiguration()
        addEvent(kind: .source, title: "Screen target", detail: target.title)
    }

    public func selectCameraDevice(id: String) {
        guard canSelectInputDevice else { return }
        cameraDeviceIDPreference = id
        guard selectedCameraDeviceID != id else { return }
        selectedCameraDeviceID = id
        applyPerformanceConfiguration()
        if let name = captureReport.devices.first(where: { $0.id == id })?.name {
            addEvent(kind: .source, title: "Camera device", detail: name)
        }
    }

    public func selectMicrophoneDevice(id: String) {
        guard canSelectInputDevice else { return }
        microphoneDeviceIDPreference = id
        guard selectedMicrophoneDeviceID != id else { return }
        selectedMicrophoneDeviceID = id
        applyPerformanceConfiguration()
        if let name = captureReport.devices.first(where: { $0.id == id })?.name {
            addEvent(kind: .source, title: "Mic device", detail: name)
        }
    }

    public func advanceDirector() {
        sampleSystemPressure()
        latestSignals = signalSnapshotApplyingSourceState(signalProvider.snapshot())
        refreshStreamHealth()

        let previousRecommendation = recommendation
        var nextRecommendation = director.evaluate(
            snapshot: latestSignals,
            currentScene: selectedSceneKind,
            mode: directorMode
        )
        nextRecommendation = recommendationApplyingPreferences(nextRecommendation)
        nextRecommendation = recommendationRespectingSceneAvailability(nextRecommendation)

        if let nextRecommendation {
            latestRecommendationSnapshot = latestSignals
            if !nextRecommendation.hasSameCue(as: previousRecommendation) {
                clearRecommendationExplanation()
                addEvent(
                    kind: nextRecommendation.urgency == .immediate ? .warning : .director,
                    title: nextRecommendation.target == selectedSceneKind ? "Check stream" : "Cue \(nextRecommendation.target.title)",
                    detail: nextRecommendation.reason
                )
                maybeAddAutomaticClipMarker(for: nextRecommendation, snapshot: latestSignals)
            }
        } else {
            clearRecommendationExplanation()
            latestRecommendationSnapshot = nil
        }

        recommendation = nextRecommendation

        if let nextRecommendation {
            if directorMode == .auto && nextRecommendation.target != selectedSceneKind {
                scheduleAutoCue(for: nextRecommendation)
            } else {
                cancelPendingAutoCue()
            }
        } else {
            cancelPendingAutoCue()
        }
    }

    public func applyRecommendation() {
        cancelPendingAutoCue()
        guard let recommendation,
              let scene = scenes.first(where: { $0.kind == recommendation.target }),
              scene.kind != selectedSceneKind
        else {
            clearRecommendation(cancelAutoCue: false)
            return
        }
        guard canSelectScene(scene) else {
            if let blockedReason = sceneSelectionBlockedReason(for: scene) {
                addWarningEventIfNeeded(title: "Cue unavailable", detail: blockedReason)
            }
            clearRecommendation(cancelAutoCue: false)
            return
        }

        selectedSceneID = scene.id
        applyPerformanceConfiguration()
        director.markSwitchAccepted()
        addEvent(kind: .director, title: "Accepted cue", detail: scene.title)
        clearRecommendation(cancelAutoCue: false)
    }

    public func dismissRecommendation() {
        guard let recommendation else {
            cancelPendingAutoCue()
            return
        }

        director.markCueHeld(
            recommendation,
            duration: max(TimeInterval(preferences.directorCountdownSeconds), directorProfile.minimumSwitchInterval)
        )
        cancelPendingAutoCue()
        clearRecommendation(cancelAutoCue: false)
        addEvent(kind: .director, title: "Cue held", detail: "Staying on \(selectedScene.title).")
    }

    public func explainCurrentRecommendation() {
        guard !isExplainingRecommendation,
              let recommendation,
              let snapshot = latestRecommendationSnapshot
        else { return }

        let explanationID = UUID()
        recommendationExplanationID = explanationID
        isExplainingRecommendation = true
        recommendationExplanation = nil

        recommendationExplanationTask = Task {
            defer {
                if isCurrentRecommendationExplanation(explanationID, recommendation: recommendation) {
                    isExplainingRecommendation = false
                    recommendationExplanationTask = nil
                    recommendationExplanationID = nil
                }
            }

            do {
                let explanation = try await intelligenceProvider.explain(recommendation, snapshot: snapshot)
                guard isCurrentRecommendationExplanation(explanationID, recommendation: recommendation) else { return }
                recommendationExplanation = explanation
                localIntelligenceStatus = intelligenceProvider.status
            } catch is CancellationError {
                return
            } catch {
                guard isCurrentRecommendationExplanation(explanationID, recommendation: recommendation) else { return }
                recommendationExplanation = recommendation.reason
            }
        }
    }

    public func markClip(reason: String = "Marked by operator.") {
        guard canMarkClip else {
            addWarningEventIfNeeded(
                title: "Clip unavailable",
                detail: "Start streaming or recording before marking a clip."
            )
            return
        }

        addClipMarker(
            title: "Clip \(selectedScene.title)",
            reason: reason,
            scene: selectedSceneKind,
            source: .manual,
            timestamp: Date()
        )
    }

    @discardableResult
    public func exportClipMarkers(to directory: URL? = nil) -> URL? {
        guard canExportClipMarkers else {
            addWarningEventIfNeeded(title: "No clips", detail: "Mark a moment before exporting.")
            return nil
        }

        do {
            let url = try ClipMarkerExporter().export(clipMarkers, to: directory)
            latestClipExportURL = url
            addEvent(kind: .clip, title: "Clips exported", detail: url.lastPathComponent)
            return url
        } catch {
            addEvent(kind: .warning, title: "Clip export failed", detail: error.localizedDescription)
            return nil
        }
    }

    @discardableResult
    public func exportSessionReport(to directory: URL? = nil) -> URL? {
        let report = SessionReportPayload(
            exportedAt: Date(),
            destinationName: destination.name,
            streamTransport: streamTransport,
            recordingPath: lastRecordingURL?.path,
            sourceStates: sources.map(SessionSourceState.init(source:)),
            screenCaptureTarget: selectedScreenCaptureTarget,
            preferences: preferences,
            effectivePerformanceMode: effectivePerformanceMode,
            health: health,
            streamRecovery: streamRecoveryMetrics,
            systemPressure: systemPressure,
            latestSignals: latestSignals,
            clipMarkers: clipMarkers,
            events: events
        )

        do {
            let url = try SessionReportExporter().export(report, to: directory)
            latestSessionReportURL = url
            addEvent(kind: .stream, title: "Report exported", detail: url.lastPathComponent)
            return url
        } catch {
            addEvent(kind: .warning, title: "Report export failed", detail: error.localizedDescription)
            return nil
        }
    }

    public func reportPersistenceFailure(_ detail: String) {
        addWarningEventIfNeeded(title: "Settings not saved", detail: detail)
    }

    @discardableResult
    public func setIntelligenceProvider(_ provider: any LocalIntelligenceProvider) -> Bool {
        guard !isGeneratingSetupPlan else {
            addWarningEventIfNeeded(title: "Provider unchanged", detail: "Finish setup generation before changing providers.")
            return false
        }

        if let providerChangeBlockedReason {
            addWarningEventIfNeeded(title: "Provider unchanged", detail: providerChangeBlockedReason)
            return false
        }

        intelligenceProvider = provider
        localIntelligenceStatus = provider.status
        return true
    }

    public func notePreviewSetupIssue(_ detail: String) {
        addWarningEventIfNeeded(title: "Camera preview unavailable", detail: detail)
    }

    public func generateSetupPlan() {
        guard canGenerateSetupPlan else {
            if let setupGenerationBlockedReason {
                setupSummary = setupGenerationBlockedReason
                addWarningEventIfNeeded(title: "Setup paused", detail: setupGenerationBlockedReason)
            }
            return
        }

        let prompt = SetupPlanPromptBuilder.boundedStreamDescription(setupPrompt)
        let generationID = UUID()
        setupGenerationID = generationID
        isGeneratingSetupPlan = true
        localIntelligenceStatus = intelligenceProvider.status
        setupSummary = "Generating setup rules..."

        setupGenerationTask = Task {
            defer {
                if isCurrentSetupGeneration(generationID) {
                    isGeneratingSetupPlan = false
                    setupGenerationTask = nil
                    setupGenerationID = nil
                }
            }

            do {
                let plan = try await intelligenceProvider.generateSetupPlan(for: prompt)
                guard isCurrentSetupGeneration(generationID) else { return }
                localIntelligenceStatus = intelligenceProvider.status
                let currentPrompt = SetupPlanPromptBuilder.boundedStreamDescription(setupPrompt)
                if currentPrompt != prompt {
                    setupSummary = "Setup prompt changed; generate rules again."
                    addEvent(kind: .warning, title: "Setup changed", detail: setupSummary)
                    return
                }
                if let setupGenerationBlockedReason {
                    setupSummary = setupGenerationBlockedReason
                    addWarningEventIfNeeded(title: "Setup paused", detail: setupGenerationBlockedReason)
                    return
                }
                directorProfile = plan.directorProfile
                director.apply(profile: plan.directorProfile)
                clearRecommendation()
                setupSummary = plan.directorRuleSummary
                addEvent(kind: .director, title: plan.title, detail: "\(plan.directorProfile.kind.title) profile applied.")
            } catch is CancellationError {
                return
            } catch {
                guard isCurrentSetupGeneration(generationID) else { return }
                setupSummary = "Setup failed."
                addEvent(kind: .warning, title: "Setup failed", detail: error.localizedDescription)
            }
        }
    }

    public func scanCaptureDevices() {
        guard canScanCaptureDevices else { return }
        isScanningCapture = true
        let captureDeviceProvider = captureDeviceProvider

        Task.detached(priority: .userInitiated) { [weak self] in
            let report = await captureDeviceProvider.scan()
            await self?.finishCaptureScan(with: report)
        }
    }

    public func scanCaptureDevicesIfNeeded() {
        guard !hasRunInitialCaptureScan, captureReport.devices.isEmpty else { return }
        scanCaptureDevices()
    }

    public func updatePreferences(_ preferences: StudioPreferences) {
        self.preferences = preferences
        updateEffectivePerformanceMode()
        applyPerformanceConfiguration()
        recommendation = recommendationApplyingPreferences(recommendation)
        recommendation = recommendationRespectingSceneAvailability(recommendation)
        if let recommendation, directorMode == .auto {
            scheduleAutoCue(for: recommendation)
        } else {
            cancelPendingAutoCue()
        }
    }

    public func updateCameraEnhancements(_ cameraEnhancements: CameraEnhancementSettings) {
        guard preferences.cameraEnhancements != cameraEnhancements else { return }

        var nextPreferences = preferences
        nextPreferences.cameraEnhancements = cameraEnhancements
        updatePreferences(nextPreferences)
    }

    public func startSourceMonitoring() {
        guard sourceMonitoringTask == nil else { return }

        sourceMonitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Self.sourceMonitoringSampleIntervalMilliseconds))
                guard !Task.isCancelled else { break }
                self?.advanceSourceMonitoring()
            }
        }
        applyPerformanceConfiguration()
        advanceSourceMonitoring()
    }

    public func stopSourceMonitoring() {
        sourceMonitoringTask?.cancel()
        sourceMonitoringTask = nil
        stopSignalProviderIfNeeded()
    }

    func advanceSourceMonitoring() {
        guard !shouldUseMediaPipelineMicrophoneCapture else {
            return
        }

        guard sourceMonitoringTask != nil || shouldSampleSourceMonitoringInput else {
            publishSourceMonitoringSnapshot(SignalSnapshot(isMicMuted: true))
            stopSignalProviderIfNeeded()
            return
        }

        guard shouldSampleSourceMonitoringInput else {
            publishSourceMonitoringSnapshot(SignalSnapshot(isMicMuted: true))
            stopSignalProviderIfNeeded()
            return
        }

        startSignalProviderIfNeeded()
        publishSourceMonitoringSnapshot(signalProvider.snapshot())
    }

    private func publishSourceMonitoringSnapshot(_ snapshot: SignalSnapshot) {
        let nextSnapshot = signalSnapshotApplyingSourceState(snapshot)
        if !Self.hasSameSourceMonitoringValues(nextSnapshot, latestSignals) {
            latestSignals = nextSnapshot
        }
        if health.audioLevel != nextSnapshot.speechLevel {
            health.audioLevel = nextSnapshot.speechLevel
        }
    }

    private static func hasSameSourceMonitoringValues(
        _ lhs: SignalSnapshot,
        _ rhs: SignalSnapshot
    ) -> Bool {
        lhs.isSpeaking == rhs.isSpeaking
            && lhs.speechLevel == rhs.speechLevel
            && lhs.screenMotion == rhs.screenMotion
            && lhs.hasFace == rhs.hasFace
            && lhs.activeApplication == rhs.activeApplication
            && lhs.idleSeconds == rhs.idleSeconds
            && lhs.isScreenFrozen == rhs.isScreenFrozen
            && lhs.isMicMuted == rhs.isMicMuted
    }

    private func finishCaptureScan(with report: CapturePreflightReport) {
        let shouldPublishReport = !hasRunInitialCaptureScan || report != captureReport
        if shouldPublishReport {
            captureReport = report
            updateSelectedScreenCaptureTarget(from: report)
            updateSelectedInputDevices(from: report)
        }
        isScanningCapture = false
        hasRunInitialCaptureScan = true
        guard shouldPublishReport else { return }
        addEvent(kind: .source, title: "Capture scan", detail: report.summary)
    }

    public func startDirectorLoop() {
        guard isDirectorRuntimeEnabled else {
            cancelPendingAutoCue()
            return
        }
        guard streamState.isLive else {
            cancelPendingAutoCue()
            return
        }
        guard directorMode != .paused else {
            cancelPendingAutoCue()
            return
        }
        guard directorLoopTask == nil else { return }
        applyPerformanceConfiguration()
        startSignalProviderIfNeeded()
        directorLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.advanceDirectorIfLive()
                guard !Task.isCancelled else { break }

                let sleepMilliseconds = Self.directorSampleIntervalMilliseconds(
                    for: self?.effectivePerformanceMode,
                    isRTMPPublishing: self?.isRTMPPublishing ?? false
                )
                try? await Task.sleep(for: .milliseconds(sleepMilliseconds))
            }
        }
    }

    public func stopDirectorLoop() {
        directorLoopTask?.cancel()
        directorLoopTask = nil
        cancelPendingAutoCue()
        stopSignalProviderIfNeeded()
    }

    private func directorModeDidChange() {
        switch directorMode {
        case .paused:
            clearRecommendation()
            stopDirectorLoop()
            syncMediaHealthLoop()
        case .suggest:
            cancelPendingAutoCue()
            if streamState.isLive {
                startDirectorLoop()
            }
            syncMediaHealthLoop()
        case .auto:
            if streamState.isLive {
                startDirectorLoop()
            }
            syncMediaHealthLoop()
            if let recommendation {
                scheduleAutoCue(for: recommendation)
            } else {
                cancelPendingAutoCue()
            }
        }
    }

    private func advanceDirectorIfLive() {
        guard streamState.isLive, directorMode != .paused else {
            stopDirectorLoop()
            return
        }

        advanceDirector()
    }

    private func startSignalProviderIfNeeded() {
        guard !isSignalProviderActive else { return }
        signalProvider.start()
        isSignalProviderActive = true
    }

    private func stopSignalProviderIfNeeded() {
        guard isSignalProviderActive else { return }
        guard directorLoopTask == nil, !shouldKeepSignalProviderForSourceMonitoring else { return }
        signalProvider.stop()
        isSignalProviderActive = false
    }

    private var shouldKeepSignalProviderForSourceMonitoring: Bool {
        sourceMonitoringTask != nil
            && shouldSampleSourceMonitoringInput
            && !shouldUseMediaPipelineMicrophoneCapture
    }

    private var shouldUseSourceMonitoringSignalConfiguration: Bool {
        sourceMonitoringTask != nil
            && directorLoopTask == nil
            && !shouldUseMediaPipelineMicrophoneCapture
    }

    private var shouldSampleSourceMonitoringInput: Bool {
        isSourceEnabled(.microphone)
            && sourceLevel(.microphone) > 0
            && selectedMicrophoneDeviceID != nil
    }

    private var shouldRunMediaHealthLoop: Bool {
        (streamState.isLive && (!isDirectorRuntimeEnabled || directorMode == .paused))
            || (recordingState == .recording && !streamState.isLive)
    }

    private var hasActiveMediaCapture: Bool {
        streamState.isLive || recordingState == .recording
    }

    private var shouldUseMediaPipelineMicrophoneCapture: Bool {
        hasActiveMediaCapture || isStreamConnecting || recordingState == .starting
    }

    private func syncMediaHealthLoop() {
        if shouldRunMediaHealthLoop {
            startMediaHealthLoopIfNeeded()
        } else {
            stopMediaHealthLoopIfNeeded()
        }
    }

    private func startMediaHealthLoopIfNeeded() {
        guard shouldRunMediaHealthLoop else { return }
        guard mediaHealthLoopTask == nil else { return }

        mediaHealthLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.advanceMediaHealthIfNeeded()
                guard !Task.isCancelled else { break }

                let sleepMilliseconds = Self.directorSampleIntervalMilliseconds(
                    for: self?.effectivePerformanceMode,
                    isRTMPPublishing: self?.isRTMPPublishing ?? false
                )
                try? await Task.sleep(for: .milliseconds(sleepMilliseconds))
            }
        }
    }

    private func stopMediaHealthLoopIfNeeded() {
        mediaHealthLoopTask?.cancel()
        mediaHealthLoopTask = nil
    }

    private func advanceMediaHealthIfNeeded() {
        if handleRecordingFailureIfNeeded() || handleStreamFailureIfNeeded() {
            return
        }

        guard shouldRunMediaHealthLoop else {
            stopMediaHealthLoopIfNeeded()
            return
        }

        sampleSystemPressure()
        refreshStreamHealth()
    }

    @discardableResult
    private func handleRecordingFailureIfNeeded() -> Bool {
        guard recordingState == .recording,
              let detail = mediaPipeline.recordingFailureDetail
        else {
            return false
        }

        addWarningEventIfNeeded(title: "Recording failed", detail: detail)
        if canStopRecording {
            stopRecording()
        }
        return true
    }

    @discardableResult
    private func handleStreamFailureIfNeeded() -> Bool {
        guard streamState.isLive,
              !isStreamStopping,
              let detail = mediaPipeline.streamFailureDetail
        else {
            return false
        }

        if streamTransport == .rtmpPublish,
           mediaPipeline.recordingFailureDetail == nil {
            beginStreamRecovery(after: detail)
            return true
        }

        let shouldStopOwnedRecording = recordingOwnedByStream
        addWarningEventIfNeeded(title: "Stream failed", detail: detail)
        isStreamStopping = true
        streamState = .failed(detail)
        health = StreamHealth()
        resetCaptureHealthPressure()
        cancelPendingAutoCue()
        stopDirectorLoop()
        let stopTask = Task {
            await mediaPipeline.stopStream()
            isStreamStopping = false
            syncMediaHealthLoop()
            if shouldStopOwnedRecording {
                stopRecording()
            }
            endCaptureSessionIfIdle()
            streamStopTask = nil
        }
        streamStopTask = stopTask
        return true
    }

    private func beginStreamRecovery(after detail: String) {
        let recoveryID = UUID()
        let recoveryDestination = destination
        let retryPolicy = streamStartRetryPolicy
        streamRecoveryMetrics.interruptionCount += 1
        streamRecoveryStartedAt = ContinuousClock().now
        streamStartTask?.cancel()
        streamStartID = recoveryID
        streamStartAttempt = 1
        streamStartMaxAttempts = retryPolicy.maxAttempts
        streamState = .connecting
        health = StreamHealth()
        resetCaptureHealthPressure()
        cancelPendingAutoCue()
        stopDirectorLoop()
        applyPerformanceConfiguration()
        addWarningEventIfNeeded(title: "Stream interrupted", detail: detail)

        streamStartTask = Task {
            await mediaPipeline.stopStream()
            guard isCurrentStreamStart(recoveryID) else { return }

            do {
                try await startStreamWithRetry(
                    destination: recoveryDestination,
                    policy: retryPolicy,
                    startID: recoveryID
                )
                guard isCurrentStreamStart(recoveryID) else { return }

                streamStartTask = nil
                streamStartID = nil
                streamState = .live
                finishStreamRecovery(outcome: .succeeded)
                applyPerformanceConfiguration()
                health = mediaPipeline.currentHealth ?? StreamHealth(
                    bitrateKbps: 0,
                    publishState: .handshaking,
                    captureFPS: currentMediaPipelineConfiguration.framesPerSecond
                )
                addEvent(kind: .stream, title: "Stream recovered", detail: recoveryDestination.safeDisplayDetail)
                startDirectorLoop()
                syncMediaHealthLoop()
            } catch {
                guard isCurrentStreamStart(recoveryID) else { return }

                streamStartTask = nil
                streamStartID = nil
                streamState = .failed(error.localizedDescription)
                finishStreamRecovery(outcome: .failed)
                applyPerformanceConfiguration()
                health = StreamHealth()
                resetCaptureHealthPressure()
                syncMediaHealthLoop()
                addEvent(kind: .warning, title: "Stream recovery failed", detail: error.localizedDescription)
                if recordingOwnedByStream {
                    stopRecording()
                }
                endCaptureSessionIfIdle()
                releaseOutputCaptureSettingsIfIdle()
            }
        }
    }

    private func addEvent(kind: StudioEventKind, title: String, detail: String) {
        events.insert(StudioEvent(kind: kind, title: title, detail: detail), at: 0)
        if events.count > Self.maxRetainedEvents {
            events.removeLast(events.count - Self.maxRetainedEvents)
        }
    }

    private func addWarningEventIfNeeded(title: String, detail: String) {
        guard events.first?.kind != .warning
            || events.first?.title != title
            || events.first?.detail != detail
        else {
            return
        }

        addEvent(kind: .warning, title: title, detail: detail)
    }

    private func prepareCaptureSessionIfIdle() {
        guard !hasOpenCaptureSession, !canMarkClip else { return }

        clearRecommendation()
        streamRecoveryMetrics = StreamRecoveryMetrics()
        streamRecoveryStartedAt = nil
        clipMarkers.removeAll()
        latestClipExportURL = nil
        latestSessionReportURL = nil
        lastAutomaticClipMarkerAt = nil
        lastRecordingURL = nil
        events.removeAll()
    }

    private func beginCaptureSession(title: String, detail: String, recordingURL: URL? = nil) {
        if let recordingURL {
            lastRecordingURL = recordingURL
        }

        guard !hasOpenCaptureSession else { return }

        hasOpenCaptureSession = true
        addEvent(kind: .stream, title: title, detail: detail)
    }

    private func endCaptureSessionIfIdle() {
        guard !streamState.isLive,
              !isStreamStopping,
              recordingState != .recording,
              recordingState != .starting,
              !isRecordingStopping
        else {
            return
        }

        hasOpenCaptureSession = false
    }

    private enum StreamRecoveryOutcome {
        case succeeded
        case failed
        case cancelled
    }

    private func finishStreamRecovery(outcome: StreamRecoveryOutcome) {
        guard let streamRecoveryStartedAt else { return }

        let duration = ContinuousClock().now - streamRecoveryStartedAt
        let components = duration.components
        let totalMilliseconds = components.seconds * 1_000
            + components.attoseconds / 1_000_000_000_000_000
        let milliseconds = max(0, Int(clamping: totalMilliseconds))
        streamRecoveryMetrics.lastDowntimeMilliseconds = milliseconds
        streamRecoveryMetrics.totalDowntimeMilliseconds += milliseconds
        self.streamRecoveryStartedAt = nil

        switch outcome {
        case .succeeded:
            streamRecoveryMetrics.successfulRecoveryCount += 1
        case .failed:
            streamRecoveryMetrics.failedRecoveryCount += 1
        case .cancelled:
            streamRecoveryMetrics.cancelledRecoveryCount += 1
        }
    }

    private var hasStartingOrActiveMediaCapture: Bool {
        streamState.isLive
            || isStreamConnecting
            || isStreamStopping
            || recordingState == .recording
            || recordingState == .starting
            || isRecordingStopping
    }

    private var currentOutputCaptureSettings: OutputCaptureSettings {
        return OutputCaptureSettings(
            resolution: preferences.outputResolution,
            frameRate: preferences.outputFrameRate
        )
    }

    private func lockOutputCaptureSettingsIfNeeded() {
        guard activeOutputCaptureSettings == nil else { return }
        activeOutputCaptureSettings = currentOutputCaptureSettings
    }

    private func releaseOutputCaptureSettingsIfIdle() {
        guard !hasStartingOrActiveMediaCapture, activeOutputCaptureSettings != nil else { return }
        activeOutputCaptureSettings = nil
        applyPerformanceConfiguration()
    }

    private func sampleSystemPressure() {
        systemPressure = performanceMonitor.snapshot()
        let previousMode = effectivePerformanceMode
        updateEffectivePerformanceMode()
        if previousMode != effectivePerformanceMode {
            applyPerformanceConfiguration()
            if preferences.performanceMode == .adaptive, streamState.isLive || recordingState == .recording {
                addEvent(
                    kind: .warning,
                    title: "Adaptive performance",
                    detail: "\(effectivePerformanceMode.title) profile active."
                )
            }
        }

        guard streamState.isLive || recordingState == .recording else { return }
        guard systemPressure.shouldPreferEfficiency else { return }

        let now = systemPressure.timestamp
        if let lastPerformanceWarningAt,
           now.timeIntervalSince(lastPerformanceWarningAt) < 45 {
            return
        }

        lastPerformanceWarningAt = now
        addEvent(
            kind: .warning,
            title: "Performance pressure",
            detail: performancePressureDetail(for: systemPressure)
        )
    }

    private func performancePressureDetail(for pressure: SystemPressureSnapshot) -> String {
        pressure.efficiencyPressureDetail ?? "Efficiency mode is safer."
    }

    private func updateEffectivePerformanceMode() {
        effectivePerformanceMode = preferences.performanceMode.effectiveMode(
            for: systemPressure,
            isCaptureConstrained: isCaptureUnderPressure
        )
    }

    private func applyPerformanceConfiguration() {
        var signalConfiguration = Self.signalSamplingConfiguration(
            for: effectivePerformanceMode,
            isRTMPPublishing: isRTMPPublishing
        )
        signalConfiguration.isMicrophoneEnabled = isSourceEnabled(.microphone)
            && !shouldUseMediaPipelineMicrophoneCapture
        signalConfiguration.microphoneDeviceID = selectedMicrophoneDeviceID
        signalConfiguration.isScreenMotionEnabled = isSourceEnabled(.screen) && sourceLevel(.screen) > 0
        signalConfiguration.screenCaptureTarget = selectedScreenCaptureTarget
        if shouldUseSourceMonitoringSignalConfiguration {
            signalConfiguration = Self.sourceMonitoringSignalConfiguration(
                isMicrophoneEnabled: shouldSampleSourceMonitoringInput,
                microphoneDeviceID: selectedMicrophoneDeviceID
            )
        }
        if signalConfiguration != lastAppliedSignalConfiguration {
            signalProvider.update(configuration: signalConfiguration)
            lastAppliedSignalConfiguration = signalConfiguration
        }

        var mediaConfiguration = currentMediaPipelineConfiguration
        let systemAudioLevel = sourceLevel(.systemAudio)
        let microphoneLevel = sourceLevel(.microphone)
        mediaConfiguration.systemAudioLevel = systemAudioLevel
        mediaConfiguration.microphoneLevel = microphoneLevel
        mediaConfiguration.capturesSystemAudio = isSourceEnabled(.systemAudio) && systemAudioLevel > 0
        mediaConfiguration.capturesMicrophone = isSourceEnabled(.microphone) && microphoneLevel > 0
        mediaConfiguration.sceneKind = selectedSceneKind
        mediaConfiguration.screenCaptureTarget = selectedScreenCaptureTarget
        mediaConfiguration.cameraEnhancements = preferences.cameraEnhancements
        mediaConfiguration.layoutSettings = preferences.layoutSettings
        mediaConfiguration.cameraDeviceID = selectedCameraDeviceID
        mediaConfiguration.microphoneDeviceID = selectedMicrophoneDeviceID
        mediaConfiguration = Self.mediaConfiguration(
            mediaConfiguration,
            constrainedForRTMPPublishing: isRTMPPublishing
        )
        if mediaConfiguration != lastAppliedMediaConfiguration {
            mediaPipeline.update(configuration: mediaConfiguration)
            lastAppliedMediaConfiguration = mediaConfiguration
        }
    }

    private func updateSelectedScreenCaptureTarget(from report: CapturePreflightReport) {
        guard canEditScreenCaptureTarget else { return }

        let targets = report.screenCaptureTargets
        guard !targets.isEmpty else {
            guard selectedScreenCaptureTarget != nil else { return }
            selectedScreenCaptureTarget = nil
            applyPerformanceConfiguration()
            return
        }

        if let targetPreference = screenCaptureTargetPreference,
           let preferredTarget = targets.first(where: { $0.id == targetPreference.id && $0.kind == targetPreference.kind }) {
            guard selectedScreenCaptureTarget != preferredTarget else { return }
            selectedScreenCaptureTarget = preferredTarget
            applyPerformanceConfiguration()
            return
        }

        if let selectedScreenCaptureTarget,
           let refreshedTarget = targets.first(where: { $0.id == selectedScreenCaptureTarget.id && $0.kind == selectedScreenCaptureTarget.kind }) {
            guard selectedScreenCaptureTarget != refreshedTarget else { return }
            self.selectedScreenCaptureTarget = refreshedTarget
            applyPerformanceConfiguration()
            return
        }

        selectedScreenCaptureTarget = targets.first { $0.kind == .display } ?? targets.first
        applyPerformanceConfiguration()
    }

    private func updateSelectedInputDevices(from report: CapturePreflightReport) {
        guard canSelectInputDevice else { return }

        let cameras = report.devices.filter { $0.kind == .camera && $0.permission == .granted }
        let microphones = report.devices.filter { $0.kind == .microphone && $0.permission == .granted }
        let resolvedCamera = resolvedDeviceID(from: cameras, current: selectedCameraDeviceID, preference: cameraDeviceIDPreference)
        let resolvedMicrophone = resolvedDeviceID(from: microphones, current: selectedMicrophoneDeviceID, preference: microphoneDeviceIDPreference)

        var didChange = false
        if resolvedCamera != selectedCameraDeviceID {
            selectedCameraDeviceID = resolvedCamera
            didChange = true
        }
        if resolvedMicrophone != selectedMicrophoneDeviceID {
            selectedMicrophoneDeviceID = resolvedMicrophone
            didChange = true
        }
        if didChange {
            applyPerformanceConfiguration()
        }
    }

    private func resolvedDeviceID(from devices: [CaptureDeviceInfo], current: String?, preference: String?) -> String? {
        guard !devices.isEmpty else { return nil }
        if let preference, devices.contains(where: { $0.id == preference }) { return preference }
        if let current, devices.contains(where: { $0.id == current }) { return current }
        return devices.first?.id
    }

    private func destinationDidChange(from previousDestination: StreamDestination) {
        guard canEditDestination else { return }

        streamTransport = Self.streamTransport(for: destination, pipelineTransport: mediaPipeline.streamTransport)

        guard case .failed = streamState else { return }
        guard previousDestination.mode != destination.mode || previousDestination.rtmpURL != destination.rtmpURL else {
            return
        }

        streamState = .offline
        health = StreamHealth()
        resetCaptureHealthPressure()
    }

    private static func streamTransport(
        for destination: StreamDestination,
        pipelineTransport: @autoclosure () -> StreamTransportKind
    ) -> StreamTransportKind {
        destination.isPreviewSession ? .preview : pipelineTransport()
    }

    private var sceneSetupChecklistItem: SetupChecklistItem {
        if selectedSceneKind == .brb {
            return SetupChecklistItem(
                id: .scene,
                title: "Scene",
                detail: "Choose Webcam, Screen + Webcam, or Screen.",
                isComplete: false
            )
        }

        return SetupChecklistItem(
            id: .scene,
            title: "Scene",
            detail: "\(selectedScene.title) selected.",
            isComplete: true
        )
    }

    private var captureSetupChecklistItem: SetupChecklistItem {
        let readiness = captureReadiness
        return SetupChecklistItem(
            id: .capture,
            title: "Capture",
            detail: readiness.detail,
            isComplete: readiness.state == .ready
        )
    }

    private var destinationSetupChecklistItem: SetupChecklistItem {
        SetupChecklistItem(
            id: .destination,
            title: "Destination",
            detail: destination.isReadyToStart
                ? (destination.isPreviewSession ? "Preview session ready." : destination.safeDisplayDetail)
                : (destination.validationError ?? "Destination needs attention."),
            isComplete: destination.isReadyToStart
        )
    }

    private var sourcesSetupChecklistItem: SetupChecklistItem {
        return SetupChecklistItem(
            id: .sources,
            title: "Sources",
            detail: sourceSetupDetail,
            isComplete: isSourceSetupReady
        )
    }

    private var selectedSceneRequiredSourceKinds: [SourceKind] {
        Self.requiredSourceKinds(for: selectedSceneKind)
    }

    private static func requiredSourceKinds(for sceneKind: SceneKind) -> [SourceKind] {
        switch sceneKind {
        case .face:
            [.camera]
        case .screenAndFace:
            [.screen, .camera]
        case .screenOnly:
            [.screen]
        case .brb:
            []
        }
    }

    private var selectedSceneUsesScreenCaptureVideo: Bool {
        Self.sceneUsesScreenCaptureVideo(selectedSceneKind)
    }

    private static func sceneUsesScreenCaptureVideo(_ sceneKind: SceneKind) -> Bool {
        sceneKind == .screenAndFace || sceneKind == .screenOnly
    }

    private func isSourceReadyForSelectedScene(_ sourceKind: SourceKind) -> Bool {
        guard let source = sources.first(where: { $0.kind == sourceKind }),
              source.isEnabled
        else {
            return false
        }

        guard source.kind.supportsLevelControl else { return true }
        return source.level > 0
    }

    private func sourceRecoveryActionTitle(for sourceKinds: [SourceKind]) -> String {
        let hasMutedRequiredSource = sourceKinds.contains { sourceKind in
            guard let source = sources.first(where: { $0.kind == sourceKind }),
                  source.isEnabled,
                  source.kind.supportsLevelControl
            else {
                return false
            }

            return source.level <= 0
        }

        return hasMutedRequiredSource ? "Enable or raise" : "Enable"
    }

    private var isCaptureConfigurationLocked: Bool {
        streamState.isLive
            || isStreamConnecting
            || isStreamStopping
            || recordingState == .recording
            || recordingState == .starting
            || isRecordingStopping
    }

    private var recommendedSourceKindsForSelectedScene: [SourceKind] {
        var kinds = selectedSceneRequiredSourceKinds
        if selectedSceneKind != .brb {
            kinds.append(.microphone)
        }
        return kinds.reduce(into: []) { uniqueKinds, kind in
            guard !uniqueKinds.contains(kind) else { return }
            uniqueKinds.append(kind)
        }
    }

    private var requiredCapturePermissionKinds: [CaptureDeviceKind] {
        var kinds: [CaptureDeviceKind] = []

        switch selectedSceneKind {
        case .face:
            if isSourceEnabled(.camera) {
                kinds.append(.camera)
            }
        case .screenAndFace:
            if isSourceEnabled(.screen) {
                kinds.append(.display)
            }
            if isSourceEnabled(.camera) {
                kinds.append(.camera)
            }
        case .screenOnly:
            if isSourceEnabled(.screen) {
                kinds.append(.display)
            }
        case .brb:
            break
        }


        return kinds
    }

    private static func sourceListTitle(for kinds: [SourceKind]) -> String {
        let titles = kinds.map(\.title)

        guard let first = titles.first else { return "Sources" }
        guard titles.count > 1 else { return first }
        guard titles.count > 2 else { return "\(first) and \(titles[1])" }

        return titles.dropLast().joined(separator: ", ") + ", and " + titles.last!
    }

    private static var streamableScreenSceneRequiredReason: String {
        "Choose Screen or Screen + Webcam before starting real capture."
    }

    private static var recordableSceneRequiredReason: String {
        "Choose Screen or Screen + Webcam before starting a local recording."
    }

    private static func permissionListTitle(for kinds: [CaptureDeviceKind]) -> String {
        let titles = kinds.map { kind in
            switch kind {
            case .display, .window:
                "Screen Recording"
            case .camera:
                "Camera"
            case .microphone:
                "Microphone"
            }
        }

        guard let first = titles.first else { return "Capture" }
        guard titles.count > 1 else { return first }
        guard titles.count > 2 else { return "\(first) and \(titles[1])" }

        return titles.dropLast().joined(separator: ", ") + ", and " + titles.last!
    }

    private func maybeAddAutomaticClipMarker(for recommendation: DirectorRecommendation, snapshot: SignalSnapshot) {
        guard streamState.isLive else { return }
        guard recommendation.urgency == .immediate || recommendation.confidence >= 0.82 else { return }

        let now = snapshot.timestamp
        if let lastAutomaticClipMarkerAt,
           now.timeIntervalSince(lastAutomaticClipMarkerAt) < 30 {
            return
        }

        lastAutomaticClipMarkerAt = now
        addClipMarker(
            title: "Clip \(recommendation.target.title)",
            reason: recommendation.reason,
            scene: recommendation.target,
            source: .director,
            timestamp: now
        )
    }

    private func addClipMarker(
        title: String,
        reason: String,
        scene: SceneKind,
        source: ClipMarkerSource,
        timestamp: Date
    ) {
        let normalizedReason = normalizedClipMarkerReason(reason, source: source)
        clipMarkers.insert(
            ClipMarker(
                title: title,
                reason: normalizedReason,
                scene: scene,
                source: source,
                timestamp: timestamp
            ),
            at: 0
        )
        if clipMarkers.count > 12 {
            clipMarkers.removeLast(clipMarkers.count - 12)
        }
        addEvent(kind: .clip, title: title, detail: normalizedReason)
    }

    private func normalizedClipMarkerReason(_ reason: String, source: ClipMarkerSource) -> String {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackReason = source == .manual ? "Marked by operator." : "Director cue."
        let effectiveReason = trimmedReason.isEmpty ? fallbackReason : trimmedReason

        guard effectiveReason.count > Self.maxClipMarkerReasonCharacters else {
            return effectiveReason
        }

        return String(effectiveReason.prefix(Self.maxClipMarkerReasonCharacters))
    }

    private func signalSnapshotApplyingSourceState(_ snapshot: SignalSnapshot) -> SignalSnapshot {
        var snapshot = snapshot
        let microphoneLevel = sourceLevel(.microphone)
        let screenLevel = sourceLevel(.screen)

        if !isSourceEnabled(.microphone) {
            snapshot.isSpeaking = false
            snapshot.speechLevel = 0
            snapshot.isMicMuted = true
        } else {
            snapshot.speechLevel = min(max(snapshot.speechLevel * microphoneLevel, 0), 1)
            snapshot.isSpeaking = snapshot.isSpeaking && snapshot.speechLevel > 0.18
            if microphoneLevel == 0 {
                snapshot.isMicMuted = true
            }
        }

        if !isSourceEnabled(.screen) {
            snapshot.screenMotion = 0
            snapshot.isScreenFrozen = false
        } else {
            snapshot.screenMotion = min(max(snapshot.screenMotion * screenLevel, 0), 1)
            if screenLevel == 0 {
                snapshot.isScreenFrozen = false
            }
        }

        if !isSourceEnabled(.camera) {
            snapshot.hasFace = false
        }

        return snapshot
    }

    private func recommendationApplyingPreferences(_ recommendation: DirectorRecommendation?) -> DirectorRecommendation? {
        guard var recommendation else { return nil }
        guard recommendation.urgency != .immediate else { return recommendation }

        recommendation.delaySeconds = max(1, preferences.directorCountdownSeconds)
        return recommendation
    }

    private func recommendationRespectingSceneAvailability(_ recommendation: DirectorRecommendation?) -> DirectorRecommendation? {
        guard var recommendation else { return nil }
        guard recommendation.target != selectedSceneKind else { return recommendation }
        guard let scene = scenes.first(where: { $0.kind == recommendation.target }) else { return nil }
        guard !canSelectScene(scene) else { return recommendation }
        guard recommendation.urgency == .immediate else { return nil }

        let blockedReason = sceneSelectionBlockedReason(for: scene) ?? "Scene is not available right now."
        recommendation.target = selectedSceneKind
        recommendation.delaySeconds = 0
        recommendation.reason = "\(recommendation.reason) \(blockedReason)"
        return recommendation
    }

    private func scheduleAutoCue(for recommendation: DirectorRecommendation) {
        guard directorMode == .auto, recommendation.target != selectedSceneKind else {
            cancelPendingAutoCue()
            return
        }

        guard let scene = scenes.first(where: { $0.kind == recommendation.target }),
              canSelectScene(scene)
        else {
            cancelPendingAutoCue()
            return
        }

        guard recommendation.delaySeconds > 0 else {
            applyRecommendation()
            return
        }

        if recommendation.hasSameCue(as: pendingAutoRecommendation) {
            return
        }

        cancelPendingAutoCue()
        pendingAutoRecommendation = recommendation
        autoCueRemainingSeconds = recommendation.delaySeconds
        autoCueTask = Task { [weak self] in
            await self?.runAutoCueCountdown(for: recommendation)
        }
    }

    private func runAutoCueCountdown(for recommendation: DirectorRecommendation) async {
        var remainingSeconds = recommendation.delaySeconds
        while remainingSeconds > 0 {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            guard isCurrentAutoCue(recommendation) else {
                cancelPendingAutoCue()
                return
            }

            remainingSeconds -= 1
            autoCueRemainingSeconds = remainingSeconds
        }

        guard isCurrentAutoCue(recommendation) else {
            cancelPendingAutoCue()
            return
        }

        applyRecommendation()
    }

    private func clearRecommendation(cancelAutoCue: Bool = true) {
        recommendation = nil
        latestRecommendationSnapshot = nil
        clearRecommendationExplanation()
        if cancelAutoCue {
            cancelPendingAutoCue()
        }
    }

    private func clearRecommendationExplanation() {
        recommendationExplanationTask?.cancel()
        recommendationExplanationTask = nil
        recommendationExplanationID = nil
        recommendationExplanation = nil
        isExplainingRecommendation = false
    }

    private func isCurrentRecommendationExplanation(
        _ id: UUID,
        recommendation expectedRecommendation: DirectorRecommendation
    ) -> Bool {
        recommendationExplanationID == id
            && isExplainingRecommendation
            && recommendation?.hasSameCue(as: expectedRecommendation) == true
    }

    private func isCurrentAutoCue(_ recommendation: DirectorRecommendation) -> Bool {
        guard let scene = scenes.first(where: { $0.kind == recommendation.target }) else { return false }

        return directorMode == .auto
            && selectedSceneKind != recommendation.target
            && canSelectScene(scene)
            && self.recommendation?.hasSameCue(as: recommendation) == true
            && pendingAutoRecommendation?.hasSameCue(as: recommendation) == true
    }

    private func cancelPendingAutoCue() {
        autoCueTask?.cancel()
        autoCueTask = nil
        pendingAutoRecommendation = nil
        autoCueRemainingSeconds = nil
    }

    private func cancelSetupGenerationIfNeeded(reason: String) {
        guard isGeneratingSetupPlan else { return }

        setupGenerationTask?.cancel()
        setupGenerationTask = nil
        setupGenerationID = nil
        isGeneratingSetupPlan = false
        setupSummary = reason
        addWarningEventIfNeeded(title: "Setup paused", detail: reason)
    }

    private func isCurrentSetupGeneration(_ id: UUID) -> Bool {
        setupGenerationID == id && isGeneratingSetupPlan
    }

    private func isCurrentStreamStart(_ id: UUID) -> Bool {
        streamStartID == id && isStreamConnecting
    }

    private func isCurrentRecordingStart(_ id: UUID) -> Bool {
        recordingStartID == id && recordingState == .starting
    }

    private var setupGenerationBlockedReason: String? {
        if isStreamConnecting {
            return "Finish connecting before generating setup rules."
        }

        if streamState.isLive {
            return streamTransport == .preview
                ? "Stop preview before generating local setup rules."
                : "Stop streaming before generating local setup rules."
        }

        if isRecordingStarting {
            return "Finish recording startup before generating setup rules."
        }

        if isRecordingStopping {
            return "Finish recording stop before generating setup rules."
        }

        if recordingState == .recording {
            return "Stop recording before generating local setup rules."
        }

        if SetupPlanPromptBuilder.boundedStreamDescription(setupPrompt).isEmpty {
            return "Describe the stream before generating setup rules."
        }

        return nil
    }

    private var providerChangeBlockedReason: String? {
        if isStreamConnecting {
            return "Finish connecting before generating setup rules."
        }

        if streamState.isLive {
            return streamTransport == .preview
                ? "Stop preview before generating local setup rules."
                : "Stop streaming before generating local setup rules."
        }

        if isRecordingStarting {
            return "Finish recording startup before generating setup rules."
        }

        if isRecordingStopping {
            return "Finish recording stop before generating setup rules."
        }

        if recordingState == .recording {
            return "Stop recording before generating local setup rules."
        }

        return nil
    }

    private var streamStartAttemptSuffix: String {
        guard streamStartMaxAttempts > 1 else { return "" }
        return " (attempt \(streamStartAttempt)/\(streamStartMaxAttempts))"
    }

    private func startStreamWithRetry(
        destination: StreamDestination,
        policy: StreamStartRetryPolicy,
        startID: UUID
    ) async throws {
        var attempt = 1
        var lastError: (any Error)?

        while attempt <= policy.maxAttempts {
            try Task.checkCancellation()
            streamStartAttempt = attempt

            do {
                try await mediaPipeline.startStream(destination: destination)
                return
            } catch {
                lastError = error
                if error is CancellationError {
                    throw error
                }
                guard isCurrentStreamStart(startID),
                      let delay = policy.delayBeforeRetry(afterFailedAttempt: attempt)
                else {
                    throw error
                }

                addEvent(kind: .warning, title: "Retrying \(streamTransport.title)", detail: error.localizedDescription)
                try await Task.sleep(for: delay)
                attempt += 1
            }
        }

        throw lastError ?? MediaPipelineError.unavailable("Stream start failed.")
    }

    private func refreshStreamHealth() {
        if handleRecordingFailureIfNeeded() || handleStreamFailureIfNeeded() {
            return
        }
        let mediaConfiguration = currentMediaPipelineConfiguration
        if let pipelineHealth = mediaPipeline.currentHealth {
            let microphoneSourceLevel = isSourceEnabled(.microphone) ? sourceLevel(.microphone) : 0
            let scaledMicrophoneLevel = min(max(pipelineHealth.audioLevel * microphoneSourceLevel, 0), 1)
            latestSignals.speechLevel = scaledMicrophoneLevel
            latestSignals.isSpeaking = scaledMicrophoneLevel > 0.18
            latestSignals.isMicMuted = microphoneSourceLevel == 0
                || pipelineHealth.microphoneDeliveryState == .inactive
                || pipelineHealth.microphoneDeliveryState == .stalled
            health = pipelineHealth
            applyCaptureHealthPressure()
            return
        }

        health.audioLevel = shouldUseMediaPipelineMicrophoneCapture ? 0 : latestSignals.speechLevel
        health.bitrateKbps = streamState.isLive && streamTransport != .rtmpPublish
            ? (mediaConfiguration.videoBitrate / 1_000) + Int(latestSignals.screenMotion * 350)
            : 0
        health.outboundBytesPerSecond = 0
        health.publishState = streamState.isLive ? .publishing : .disconnected
        health.captureFPS = hasActiveMediaCapture ? mediaConfiguration.framesPerSecond : 0
        health.droppedFrames = latestSignals.isScreenFrozen ? health.droppedFrames + 12 : max(health.droppedFrames - 1, 0)
        applyCaptureHealthPressure()
    }

    private func applyCaptureHealthPressure() {
        guard hasActiveMediaCapture else {
            lastObservedDroppedFrames = health.droppedFrames
            lastObservedRTMPAudioAppendRejections = health.rtmpAudioAppendRejections
            zeroCaptureFPSObservedAt = nil
            return
        }

        let droppedFramesSinceLastSample = max(0, health.droppedFrames - lastObservedDroppedFrames)
        lastObservedDroppedFrames = health.droppedFrames
        let audioAppendRejectionsSinceLastSample = max(
            0,
            health.rtmpAudioAppendRejections - lastObservedRTMPAudioAppendRejections
        )
        lastObservedRTMPAudioAppendRejections = health.rtmpAudioAppendRejections

        let targetFPS = captureHealthTargetFPS
        let droppedFrameLimit = max(3, targetFPS / 10)
        let lowFPSLimit = max(10, Int((Double(targetFPS) * 0.67).rounded(.down)))
        let recoveredFPSLimit = max(10, Int((Double(targetFPS) * 0.8).rounded(.down)))

        let zeroFPSAge: Duration?
        if health.captureFPS == 0 {
            let now = ContinuousClock().now
            if let zeroCaptureFPSObservedAt {
                zeroFPSAge = now - zeroCaptureFPSObservedAt
            } else {
                zeroCaptureFPSObservedAt = now
                zeroFPSAge = .zero
            }
        } else {
            zeroCaptureFPSObservedAt = nil
            zeroFPSAge = nil
        }

        let droppedFramePressure = droppedFramesSinceLastSample >= droppedFrameLimit
        let audioAppendPressure = audioAppendRejectionsSinceLastSample > 0
        let appendQueuePressure = health.rtmpAppendCapacity > 0
            && health.rtmpPendingAppends >= health.rtmpAppendCapacity
        let lowFPSPressure = Self.captureFPSIndicatesPressure(
            health.captureFPS,
            lowFPSLimit: lowFPSLimit,
            zeroFPSAge: zeroFPSAge
        )
        let recoveredSample = droppedFramesSinceLastSample == 0
            && audioAppendRejectionsSinceLastSample == 0
            && !appendQueuePressure
            && health.captureFPS >= recoveredFPSLimit

        let nextCaptureUnderPressure: Bool
        if isCaptureUnderPressure {
            if recoveredSample {
                captureHealthRecoverySampleCount += 1
            } else {
                captureHealthRecoverySampleCount = 0
            }
            nextCaptureUnderPressure = captureHealthRecoverySampleCount < Self.requiredCaptureHealthRecoverySamples
        } else {
            captureHealthRecoverySampleCount = 0
            nextCaptureUnderPressure = droppedFramePressure
                || audioAppendPressure
                || appendQueuePressure
                || lowFPSPressure
        }

        if nextCaptureUnderPressure != isCaptureUnderPressure {
            isCaptureUnderPressure = nextCaptureUnderPressure
            let previousMode = effectivePerformanceMode
            updateEffectivePerformanceMode()
            if preferences.performanceMode == .adaptive, previousMode != effectivePerformanceMode {
                applyPerformanceConfiguration()
                addEvent(
                    kind: .warning,
                    title: "Adaptive performance",
                    detail: "\(effectivePerformanceMode.title) profile active."
                )
            }
        }

        if nextCaptureUnderPressure {
            let reason: String
            if droppedFramePressure {
                reason = "Dropped frames detected; reducing capture cost."
            } else if audioAppendPressure {
                reason = "RTMP audio backpressure detected; reducing capture cost."
            } else if appendQueuePressure {
                reason = "RTMP append queue saturated; reducing capture cost."
            } else if lowFPSPressure {
                reason = "Capture FPS below target; reducing capture cost."
            } else {
                reason = activeHealthDegradationReason ?? "Capture health is stabilizing; keeping capture cost reduced."
            }
            setHealthDegradation(reason)
        } else {
            clearHealthDegradationIfNeeded()
        }
    }

    private var captureHealthTargetFPS: Int {
        let outputCaptureSettings = activeOutputCaptureSettings ?? currentOutputCaptureSettings
        if preferences.performanceMode == .adaptive {
            return Self.mediaConfiguration(
                Self.mediaConfiguration(
                    StudioPerformanceMode.balanced.mediaConfiguration,
                    outputResolution: outputCaptureSettings.resolution,
                    outputFrameRate: outputCaptureSettings.frameRate
                ),
                constrainedForRTMPPublishing: isRTMPPublishing
            ).framesPerSecond
        }

        return currentMediaPipelineConfiguration.framesPerSecond
    }

    private var currentMediaPipelineConfiguration: MediaPipelineConfiguration {
        let outputCaptureSettings = activeOutputCaptureSettings ?? currentOutputCaptureSettings
        let outputConfiguration = Self.mediaConfiguration(
            effectivePerformanceMode.mediaConfiguration,
            outputResolution: outputCaptureSettings.resolution,
            outputFrameRate: outputCaptureSettings.frameRate
        )
        return Self.mediaConfiguration(
            outputConfiguration,
            constrainedForRTMPPublishing: isRTMPPublishing
        )
    }

    private var isRTMPPublishing: Bool {
        streamTransport == .rtmpPublish && (isStreamConnecting || streamState.isLive)
    }

    static func previewCaptureConfiguration(
        for mode: StudioPerformanceMode,
        isRTMPPublishing: Bool
    ) -> PreviewCaptureConfiguration {
        previewCaptureConfiguration(
            for: mode,
            quality: .automatic,
            isRTMPPublishing: isRTMPPublishing
        )
    }

    static func previewCaptureConfiguration(
        for mode: StudioPerformanceMode,
        quality: StudioPreviewRenderQuality,
        isRTMPPublishing: Bool
    ) -> PreviewCaptureConfiguration {
        let fullConfiguration = mode.previewCaptureConfiguration
        switch quality {
        case .automatic:
            guard isRTMPPublishing else { return fullConfiguration }
            let liveCap = StudioPerformanceMode.liveStreamingPreviewConfiguration
            return PreviewCaptureConfiguration(
                maxDisplayWidth: min(fullConfiguration.maxDisplayWidth, liveCap.maxDisplayWidth),
                framesPerSecond: min(fullConfiguration.framesPerSecond, liveCap.framesPerSecond),
                queueDepth: 1
            )
        case .half:
            return PreviewCaptureConfiguration(
                maxDisplayWidth: max(640, fullConfiguration.maxDisplayWidth / 2),
                framesPerSecond: fullConfiguration.framesPerSecond,
                queueDepth: 1
            )
        case .full:
            return fullConfiguration
        }
    }

    static func signalSamplingConfiguration(
        for mode: StudioPerformanceMode,
        isRTMPPublishing: Bool
    ) -> SignalSamplingConfiguration {
        isRTMPPublishing
            ? StudioPerformanceMode.liveStreamingSignalSamplingConfiguration
            : mode.signalSamplingConfiguration
    }

    static func sourceMonitoringSignalConfiguration(
        isMicrophoneEnabled: Bool,
        microphoneDeviceID: String?
    ) -> SignalSamplingConfiguration {
        SignalSamplingConfiguration(
            screenMotionFramesPerSecond: 1,
            isMicrophoneEnabled: isMicrophoneEnabled,
            microphoneDeviceID: microphoneDeviceID,
            isScreenMotionEnabled: false,
            isActivityContextEnabled: false
        )
    }

    static func directorSampleIntervalMilliseconds(
        for mode: StudioPerformanceMode?,
        isRTMPPublishing: Bool
    ) -> Int {
        let interval = mode?.directorSampleIntervalMilliseconds ?? 1_000
        guard isRTMPPublishing else { return interval }
        return max(interval, StudioPerformanceMode.liveStreamingDirectorSampleIntervalMilliseconds)
    }

    static func mediaConfiguration(
        _ configuration: MediaPipelineConfiguration,
        constrainedForRTMPPublishing isRTMPPublishing: Bool
    ) -> MediaPipelineConfiguration {
        guard isRTMPPublishing else { return configuration }
        var constrainedConfiguration = configuration
        constrainedConfiguration.framesPerSecond = min(configuration.framesPerSecond, 30)
        return constrainedConfiguration
    }

    static func mediaConfiguration(
        _ configuration: MediaPipelineConfiguration,
        outputResolution: StreamOutputResolution,
        outputFrameRate: StreamFrameRate
    ) -> MediaPipelineConfiguration {
        var outputConfiguration = configuration
        var didOverrideOutput = false

        if let maxVideoWidth = outputResolution.maxVideoWidth {
            outputConfiguration.maxVideoWidth = maxVideoWidth
            didOverrideOutput = true
        }

        if let framesPerSecond = outputFrameRate.framesPerSecond {
            outputConfiguration.framesPerSecond = framesPerSecond
            didOverrideOutput = true
        }

        if didOverrideOutput {
            outputConfiguration.videoBitrate = outputVideoBitrate(
                maxVideoWidth: outputConfiguration.maxVideoWidth,
                framesPerSecond: outputConfiguration.framesPerSecond
            )
        }

        return outputConfiguration
    }

    static func outputVideoBitrate(maxVideoWidth: Int, framesPerSecond: Int) -> Int {
        let baseBitrate: Double
        switch maxVideoWidth {
        case ...1_280:
            baseBitrate = 4_000_000
        case ...1_920:
            baseBitrate = 8_000_000
        case ...2_560:
            baseBitrate = 16_000_000
        default:
            baseBitrate = 30_000_000
        }

        let frameRateFactor: Double
        if framesPerSecond >= 60 {
            frameRateFactor = 1.4
        } else if framesPerSecond <= 24 {
            frameRateFactor = 0.85
        } else {
            frameRateFactor = 1
        }

        return Int(baseBitrate * frameRateFactor)
    }

    private func setHealthDegradation(_ reason: String) {
        if activeHealthDegradationReason == reason,
           case let .degraded(currentReason) = streamState,
           currentReason == reason {
            return
        }
        if activeHealthDegradationReason == reason, !streamState.isLive {
            return
        }

        activeHealthDegradationReason = reason
        if streamState.isLive {
            streamState = .degraded(reason)
        }
        addEvent(kind: .warning, title: streamState.isLive ? "Stream health" : "Capture health", detail: reason)
    }

    private func clearHealthDegradationIfNeeded() {
        guard let activeHealthDegradationReason else { return }

        self.activeHealthDegradationReason = nil
        if case let .degraded(reason) = streamState,
           reason == activeHealthDegradationReason {
            streamState = .live
            addEvent(kind: .stream, title: "Stream recovered", detail: "Capture health returned to target.")
        } else if recordingState == .recording {
            addEvent(kind: .stream, title: "Capture recovered", detail: "Capture health returned to target.")
        }
    }

    private func resetCaptureHealthPressure() {
        isCaptureUnderPressure = false
        activeHealthDegradationReason = nil
        lastObservedDroppedFrames = 0
        lastObservedRTMPAudioAppendRejections = 0
        captureHealthRecoverySampleCount = 0
        zeroCaptureFPSObservedAt = nil
        updateEffectivePerformanceMode()
    }

    static func captureFPSIndicatesPressure(
        _ captureFPS: Int,
        lowFPSLimit: Int,
        zeroFPSAge: Duration?
    ) -> Bool {
        guard captureFPS == 0 else { return captureFPS < lowFPSLimit }
        guard let zeroFPSAge else { return false }
        return zeroFPSAge >= zeroCaptureFPSPressureDelay
    }
}

private extension DirectorRecommendation {
    func hasSameCue(as other: DirectorRecommendation?) -> Bool {
        guard let other else { return false }

        return target == other.target
            && reason == other.reason
            && urgency == other.urgency
            && delaySeconds == other.delaySeconds
    }
}
