import Foundation

public enum SceneKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case face
    case screenAndFace
    case screenOnly
    case brb

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .face: "Face"
        case .screenAndFace: "Screen + Face"
        case .screenOnly: "Screen"
        case .brb: "BRB"
        }
    }

    public var symbolName: String {
        switch self {
        case .face: "person.crop.rectangle"
        case .screenAndFace: "rectangle.inset.filled.and.person.filled"
        case .screenOnly: "display"
        case .brb: "pause.rectangle"
        }
    }
}

public struct StudioScene: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var kind: SceneKind
    public var title: String
    public var subtitle: String

    public init(id: UUID = UUID(), kind: SceneKind, title: String? = nil, subtitle: String) {
        self.id = id
        self.kind = kind
        self.title = title ?? kind.title
        self.subtitle = subtitle
    }
}

public enum SourceKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case camera
    case screen
    case microphone
    case systemAudio

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .camera: "Camera"
        case .screen: "Screen"
        case .microphone: "Mic"
        case .systemAudio: "System Audio"
        }
    }

    public var symbolName: String {
        switch self {
        case .camera: "video"
        case .screen: "macwindow"
        case .microphone: "mic"
        case .systemAudio: "speaker.wave.2"
        }
    }

    public var supportsLevelControl: Bool {
        switch self {
        case .camera:
            false
        case .screen, .microphone, .systemAudio:
            true
        }
    }
}

public struct StudioSource: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var kind: SourceKind
    public var title: String
    public var isEnabled: Bool
    public var level: Double

    public init(
        id: UUID = UUID(),
        kind: SourceKind,
        title: String? = nil,
        isEnabled: Bool = true,
        level: Double = 1
    ) {
        self.id = id
        self.kind = kind
        self.title = title ?? kind.title
        self.isEnabled = isEnabled
        self.level = Self.normalizedLevel(level)
    }

    static func normalizedLevel(_ level: Double) -> Double {
        let clampedLevel = min(max(level, 0), 1)
        return (clampedLevel * 100).rounded() / 100
    }
}

public struct StudioSourceConfiguration: Codable, Equatable, Sendable {
    public var kind: SourceKind
    public var isEnabled: Bool
    public var level: Double

    public init(kind: SourceKind, isEnabled: Bool, level: Double) {
        self.kind = kind
        self.isEnabled = isEnabled
        self.level = StudioSource.normalizedLevel(level)
    }

    public init(source: StudioSource) {
        self.init(kind: source.kind, isEnabled: source.isEnabled, level: source.level)
    }
}

public enum SourceSetupRole: String, Equatable, Sendable {
    case required
    case recommended
    case optional
    case unused

    public var title: String {
        switch self {
        case .required: "Required"
        case .recommended: "Recommended"
        case .optional: "Optional"
        case .unused: "Not needed"
        }
    }
}

public enum DirectorMode: String, CaseIterable, Identifiable, Sendable {
    case paused
    case suggest
    case auto

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .paused: "Paused"
        case .suggest: "Suggest"
        case .auto: "Auto"
        }
    }
}

public enum StreamState: Equatable, Sendable {
    case offline
    case connecting
    case live
    case degraded(String)
    case failed(String)

    public var title: String {
        switch self {
        case .offline: "Offline"
        case .connecting: "Connecting"
        case .live: "Live"
        case .degraded: "Degraded"
        case .failed: "Failed"
        }
    }

    public var detail: String {
        switch self {
        case .offline: "Ready"
        case .connecting: "Validating RTMP endpoint"
        case .live: "Endpoint reachable"
        case let .degraded(reason): reason
        case let .failed(reason): reason
        }
    }

    public var isLive: Bool {
        if case .live = self { return true }
        if case .degraded = self { return true }
        return false
    }
}

public struct StreamStartRetryPolicy: Equatable, Sendable {
    public var maxAttempts: Int
    public var backoffMilliseconds: [Int]

    public init(maxAttempts: Int = 1, backoffMilliseconds: [Int] = []) {
        self.maxAttempts = max(1, maxAttempts)
        self.backoffMilliseconds = backoffMilliseconds.map { max(0, $0) }
    }

    public static let none = StreamStartRetryPolicy()

    public static let rtmpStartup = StreamStartRetryPolicy(
        maxAttempts: 3,
        backoffMilliseconds: [300, 900]
    )

    public func delayBeforeRetry(afterFailedAttempt attempt: Int) -> Duration? {
        guard attempt < maxAttempts else { return nil }

        let index = max(0, attempt - 1)
        let milliseconds = backoffMilliseconds.indices.contains(index)
            ? backoffMilliseconds[index]
            : backoffMilliseconds.last ?? 0

        return .milliseconds(milliseconds)
    }
}

public enum RecordingState: Equatable, Sendable {
    case stopped
    case starting
    case recording
    case failed(String)

    public var title: String {
        switch self {
        case .stopped: "Stopped"
        case .starting: "Starting"
        case .recording: "Recording"
        case .failed: "Failed"
        }
    }

    public var detail: String {
        switch self {
        case .stopped: "Ready"
        case .starting: "Preparing local file"
        case .recording: "Writing local archive"
        case let .failed(reason): reason
        }
    }

    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

public struct StreamHealth: Codable, Equatable, Sendable {
    public var bitrateKbps: Int
    public var droppedFrames: Int
    public var captureFPS: Int
    public var audioLevel: Double
    public var roundTripMs: Int

    public init(
        bitrateKbps: Int = 0,
        droppedFrames: Int = 0,
        captureFPS: Int = 60,
        audioLevel: Double = 0,
        roundTripMs: Int = 0
    ) {
        self.bitrateKbps = bitrateKbps
        self.droppedFrames = droppedFrames
        self.captureFPS = captureFPS
        self.audioLevel = audioLevel
        self.roundTripMs = roundTripMs
    }
}

public enum SystemPressureLevel: String, Codable, Sendable {
    case nominal
    case fair
    case serious
    case critical

    public var title: String {
        switch self {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        }
    }

    public var isConstrained: Bool {
        self == .serious || self == .critical
    }
}

public struct SystemPressureSnapshot: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var thermalPressure: SystemPressureLevel
    public var memoryUsedMB: Int
    public var physicalMemoryMB: Int
    public var isLowPowerModeEnabled: Bool

    public init(
        timestamp: Date = Date(),
        thermalPressure: SystemPressureLevel = .nominal,
        memoryUsedMB: Int = 0,
        physicalMemoryMB: Int = 0,
        isLowPowerModeEnabled: Bool = false
    ) {
        self.timestamp = timestamp
        self.thermalPressure = thermalPressure
        self.memoryUsedMB = memoryUsedMB
        self.physicalMemoryMB = physicalMemoryMB
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
    }

    public var memoryUsagePercent: Int {
        guard physicalMemoryMB > 0 else { return 0 }
        return min(max(Int((Double(memoryUsedMB) / Double(physicalMemoryMB)) * 100), 0), 100)
    }

    public var isMemoryConstrained: Bool {
        memoryUsedMB >= 2_048 || memoryUsagePercent >= 25
    }

    public var efficiencyPressureDetail: String? {
        if isLowPowerModeEnabled {
            return "Low Power Mode is on; Efficiency mode is safer."
        }

        if thermalPressure.isConstrained {
            return "Thermal pressure is \(thermalPressure.title.lowercased()); Efficiency mode is safer."
        }

        if isMemoryConstrained {
            return "OpenCue is using \(memoryUsedMB) MB; Efficiency mode is safer."
        }

        return nil
    }

    public var shouldPreferEfficiency: Bool {
        efficiencyPressureDetail != nil
    }
}

public struct StudioPreferences: Codable, Equatable, Sendable {
    public static let minimumDirectorCountdownSeconds = 1
    public static let maximumDirectorCountdownSeconds = 5

    public var recordWhileStreaming: Bool
    public var directorCountdownSeconds: Int {
        didSet {
            directorCountdownSeconds = Self.normalizedDirectorCountdownSeconds(directorCountdownSeconds)
        }
    }
    public var performanceMode: StudioPerformanceMode
    public var cameraEnhancements: CameraEnhancementSettings

    private enum CodingKeys: String, CodingKey {
        case recordWhileStreaming
        case directorCountdownSeconds
        case performanceMode
        case cameraEnhancements
    }

    public init(
        recordWhileStreaming: Bool = false,
        directorCountdownSeconds: Int = 2,
        performanceMode: StudioPerformanceMode = .balanced,
        cameraEnhancements: CameraEnhancementSettings = CameraEnhancementSettings()
    ) {
        self.recordWhileStreaming = recordWhileStreaming
        self.directorCountdownSeconds = Self.normalizedDirectorCountdownSeconds(directorCountdownSeconds)
        self.performanceMode = performanceMode
        self.cameraEnhancements = cameraEnhancements
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordWhileStreaming = try container.decodeIfPresent(Bool.self, forKey: .recordWhileStreaming) ?? false
        directorCountdownSeconds = Self.normalizedDirectorCountdownSeconds(
            try container.decodeIfPresent(Int.self, forKey: .directorCountdownSeconds) ?? 2
        )
        performanceMode = try container.decodeIfPresent(
            StudioPerformanceMode.self,
            forKey: .performanceMode
        ) ?? .balanced
        cameraEnhancements = try container.decodeIfPresent(
            CameraEnhancementSettings.self,
            forKey: .cameraEnhancements
        ) ?? CameraEnhancementSettings()
    }

    public static func normalizedDirectorCountdownSeconds(_ seconds: Int) -> Int {
        min(max(seconds, minimumDirectorCountdownSeconds), maximumDirectorCountdownSeconds)
    }
}

public enum CameraPreviewRotation: Int, CaseIterable, Codable, Identifiable, Sendable {
    case degrees0 = 0
    case degrees90 = 90
    case degrees180 = 180
    case degrees270 = 270

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .degrees0: "0"
        case .degrees90: "90"
        case .degrees180: "180"
        case .degrees270: "270"
        }
    }

    public var radians: Double {
        Double(rawValue) * .pi / 180
    }

    public var isSideways: Bool {
        self == .degrees90 || self == .degrees270
    }
}

public struct CameraEnhancementSettings: Codable, Equatable, Sendable {
    public var mirrorsPreview: Bool
    public var rotation: CameraPreviewRotation
    public var usesAutoLight: Bool
    public var autoLightAmount: Double {
        didSet {
            autoLightAmount = Self.normalizedAutoLightAmount(autoLightAmount)
        }
    }

    public init(
        mirrorsPreview: Bool = true,
        rotation: CameraPreviewRotation = .degrees0,
        usesAutoLight: Bool = false,
        autoLightAmount: Double = 0.35
    ) {
        self.mirrorsPreview = mirrorsPreview
        self.rotation = rotation
        self.usesAutoLight = usesAutoLight
        self.autoLightAmount = Self.normalizedAutoLightAmount(autoLightAmount)
    }

    public static func normalizedAutoLightAmount(_ amount: Double) -> Double {
        let clamped = min(max(amount, 0), 1)
        return (clamped * 100).rounded() / 100
    }
}

public enum StudioPerformanceMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case adaptive
    case efficiency
    case balanced
    case responsive

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .adaptive: "Adaptive"
        case .efficiency: "Efficiency"
        case .balanced: "Balanced"
        case .responsive: "Responsive"
        }
    }

    public var directorSampleIntervalMilliseconds: Int {
        switch self {
        case .adaptive: StudioPerformanceMode.balanced.directorSampleIntervalMilliseconds
        case .efficiency: 2_000
        case .balanced: 1_000
        case .responsive: 500
        }
    }

    public var signalSamplingConfiguration: SignalSamplingConfiguration {
        switch self {
        case .adaptive:
            StudioPerformanceMode.balanced.signalSamplingConfiguration
        case .efficiency:
            SignalSamplingConfiguration(screenMotionFramesPerSecond: 2)
        case .balanced:
            SignalSamplingConfiguration(screenMotionFramesPerSecond: 4)
        case .responsive:
            SignalSamplingConfiguration(screenMotionFramesPerSecond: 8)
        }
    }

    public var mediaConfiguration: MediaPipelineConfiguration {
        switch self {
        case .adaptive:
            StudioPerformanceMode.balanced.mediaConfiguration
        case .efficiency:
            MediaPipelineConfiguration(maxVideoWidth: 1_280, framesPerSecond: 24, videoBitrate: 4_000_000, queueDepth: 3)
        case .balanced:
            MediaPipelineConfiguration(maxVideoWidth: 1_920, framesPerSecond: 30, videoBitrate: 8_000_000, queueDepth: 5)
        case .responsive:
            MediaPipelineConfiguration(maxVideoWidth: 1_920, framesPerSecond: 60, videoBitrate: 10_000_000, queueDepth: 5)
        }
    }

    public var previewCaptureConfiguration: PreviewCaptureConfiguration {
        switch self {
        case .adaptive:
            StudioPerformanceMode.balanced.previewCaptureConfiguration
        case .efficiency:
            PreviewCaptureConfiguration(maxDisplayWidth: 960, framesPerSecond: 8, queueDepth: 1)
        case .balanced:
            PreviewCaptureConfiguration(maxDisplayWidth: 1_280, framesPerSecond: 12, queueDepth: 2)
        case .responsive:
            PreviewCaptureConfiguration(maxDisplayWidth: 1_920, framesPerSecond: 15, queueDepth: 3)
        }
    }

    public func effectiveMode(
        for pressure: SystemPressureSnapshot,
        isCaptureConstrained: Bool = false
    ) -> StudioPerformanceMode {
        guard self == .adaptive else { return self }
        return pressure.shouldPreferEfficiency || isCaptureConstrained ? .efficiency : .balanced
    }
}

public struct SignalSamplingConfiguration: Equatable, Sendable {
    public var screenMotionFramesPerSecond: Int
    public var isMicrophoneEnabled: Bool
    public var isScreenMotionEnabled: Bool
    public var screenCaptureTarget: ScreenCaptureTarget?

    public init(
        screenMotionFramesPerSecond: Int = 4,
        isMicrophoneEnabled: Bool = true,
        isScreenMotionEnabled: Bool = true,
        screenCaptureTarget: ScreenCaptureTarget? = nil
    ) {
        self.screenMotionFramesPerSecond = max(1, screenMotionFramesPerSecond)
        self.isMicrophoneEnabled = isMicrophoneEnabled
        self.isScreenMotionEnabled = isScreenMotionEnabled
        self.screenCaptureTarget = screenCaptureTarget
    }
}

public struct MediaPipelineConfiguration: Equatable, Sendable {
    public var maxVideoWidth: Int
    public var framesPerSecond: Int
    public var videoBitrate: Int
    public var queueDepth: Int
    public var sceneKind: SceneKind
    public var capturesSystemAudio: Bool
    public var capturesMicrophone: Bool
    public var systemAudioLevel: Double
    public var microphoneLevel: Double
    public var screenCaptureTarget: ScreenCaptureTarget?
    public var cameraEnhancements: CameraEnhancementSettings

    public init(
        maxVideoWidth: Int = 1_920,
        framesPerSecond: Int = 30,
        videoBitrate: Int = 8_000_000,
        queueDepth: Int = 5,
        sceneKind: SceneKind = .screenOnly,
        capturesSystemAudio: Bool = true,
        capturesMicrophone: Bool = true,
        systemAudioLevel: Double = 1,
        microphoneLevel: Double = 1,
        screenCaptureTarget: ScreenCaptureTarget? = nil,
        cameraEnhancements: CameraEnhancementSettings = CameraEnhancementSettings()
    ) {
        self.maxVideoWidth = max(320, maxVideoWidth)
        self.framesPerSecond = min(max(framesPerSecond, 10), 60)
        self.videoBitrate = max(1_000_000, videoBitrate)
        self.queueDepth = min(max(queueDepth, 2), 8)
        self.sceneKind = sceneKind
        self.capturesSystemAudio = capturesSystemAudio
        self.capturesMicrophone = capturesMicrophone
        self.systemAudioLevel = min(max(systemAudioLevel, 0), 1)
        self.microphoneLevel = min(max(microphoneLevel, 0), 1)
        self.screenCaptureTarget = screenCaptureTarget
        self.cameraEnhancements = cameraEnhancements
    }
}

public struct PreviewCaptureConfiguration: Equatable, Sendable {
    public var maxDisplayWidth: Int
    public var framesPerSecond: Int
    public var queueDepth: Int

    public init(maxDisplayWidth: Int = 1_280, framesPerSecond: Int = 12, queueDepth: Int = 2) {
        self.maxDisplayWidth = min(max(maxDisplayWidth, 640), 1_920)
        self.framesPerSecond = min(max(framesPerSecond, 5), 30)
        self.queueDepth = min(max(queueDepth, 1), 4)
    }
}

public struct SignalSnapshot: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var isSpeaking: Bool
    public var speechLevel: Double
    public var screenMotion: Double
    public var hasFace: Bool
    public var activeApplication: String
    public var idleSeconds: TimeInterval
    public var isScreenFrozen: Bool
    public var isMicMuted: Bool

    public init(
        timestamp: Date = Date(),
        isSpeaking: Bool = false,
        speechLevel: Double = 0,
        screenMotion: Double = 0,
        hasFace: Bool = true,
        activeApplication: String = "Finder",
        idleSeconds: TimeInterval = 0,
        isScreenFrozen: Bool = false,
        isMicMuted: Bool = false
    ) {
        self.timestamp = timestamp
        self.isSpeaking = isSpeaking
        self.speechLevel = speechLevel
        self.screenMotion = screenMotion
        self.hasFace = hasFace
        self.activeApplication = activeApplication
        self.idleSeconds = idleSeconds
        self.isScreenFrozen = isScreenFrozen
        self.isMicMuted = isMicMuted
    }
}

public enum RecommendationUrgency: String, Sendable {
    case calm
    case soon
    case immediate
}

public struct DirectorRecommendation: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var target: SceneKind
    public var confidence: Double
    public var reason: String
    public var urgency: RecommendationUrgency
    public var delaySeconds: Int

    public init(
        id: UUID = UUID(),
        target: SceneKind,
        confidence: Double,
        reason: String,
        urgency: RecommendationUrgency = .soon,
        delaySeconds: Int = 2
    ) {
        self.id = id
        self.target = target
        self.confidence = confidence
        self.reason = reason
        self.urgency = urgency
        self.delaySeconds = delaySeconds
    }
}

public enum DirectorProfileKind: String, CaseIterable, Identifiable, Sendable {
    case balanced
    case coding
    case demo
    case teaching
    case podcast

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .balanced: "Balanced"
        case .coding: "Coding"
        case .demo: "Demo"
        case .teaching: "Teaching"
        case .podcast: "Podcast"
        }
    }
}

public struct DirectorProfile: Equatable, Sendable {
    public var kind: DirectorProfileKind
    public var minimumSwitchInterval: TimeInterval
    public var quietScreenMotionThreshold: Double
    public var activeScreenMotionThreshold: Double
    public var idleToBRBSeconds: TimeInterval
    public var prefersFaceWhenSpeaking: Bool
    public var defaultScene: SceneKind

    public init(
        kind: DirectorProfileKind = .balanced,
        minimumSwitchInterval: TimeInterval = 4,
        quietScreenMotionThreshold: Double = 0.24,
        activeScreenMotionThreshold: Double = 0.42,
        idleToBRBSeconds: TimeInterval = 35,
        prefersFaceWhenSpeaking: Bool = true,
        defaultScene: SceneKind = .screenAndFace
    ) {
        self.kind = kind
        self.minimumSwitchInterval = minimumSwitchInterval
        self.quietScreenMotionThreshold = quietScreenMotionThreshold
        self.activeScreenMotionThreshold = activeScreenMotionThreshold
        self.idleToBRBSeconds = idleToBRBSeconds
        self.prefersFaceWhenSpeaking = prefersFaceWhenSpeaking
        self.defaultScene = defaultScene
    }

    public static let balanced = DirectorProfile()

    public static let coding = DirectorProfile(
        kind: .coding,
        minimumSwitchInterval: 5,
        quietScreenMotionThreshold: 0.18,
        activeScreenMotionThreshold: 0.3,
        idleToBRBSeconds: 45,
        prefersFaceWhenSpeaking: false,
        defaultScene: .screenAndFace
    )

    public static let demo = DirectorProfile(
        kind: .demo,
        minimumSwitchInterval: 4,
        quietScreenMotionThreshold: 0.28,
        activeScreenMotionThreshold: 0.38,
        idleToBRBSeconds: 30,
        prefersFaceWhenSpeaking: true,
        defaultScene: .screenAndFace
    )

    public static let teaching = DirectorProfile(
        kind: .teaching,
        minimumSwitchInterval: 6,
        quietScreenMotionThreshold: 0.34,
        activeScreenMotionThreshold: 0.5,
        idleToBRBSeconds: 50,
        prefersFaceWhenSpeaking: true,
        defaultScene: .face
    )

    public static let podcast = DirectorProfile(
        kind: .podcast,
        minimumSwitchInterval: 8,
        quietScreenMotionThreshold: 0.48,
        activeScreenMotionThreshold: 0.72,
        idleToBRBSeconds: 60,
        prefersFaceWhenSpeaking: true,
        defaultScene: .face
    )
}

public enum StudioEventKind: String, Codable, Sendable {
    case stream
    case director
    case warning
    case source
    case clip
}

public struct StudioEvent: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var kind: StudioEventKind
    public var title: String
    public var detail: String
    public var timestamp: Date

    public init(
        id: UUID = UUID(),
        kind: StudioEventKind,
        title: String,
        detail: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
    }
}

public enum ClipMarkerSource: String, Codable, Sendable {
    case manual
    case director

    public var title: String {
        switch self {
        case .manual: "Manual"
        case .director: "Director"
        }
    }
}

public struct ClipMarker: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var title: String
    public var reason: String
    public var scene: SceneKind
    public var source: ClipMarkerSource
    public var timestamp: Date

    public init(
        id: UUID = UUID(),
        title: String,
        reason: String,
        scene: SceneKind,
        source: ClipMarkerSource,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.reason = reason
        self.scene = scene
        self.source = source
        self.timestamp = timestamp
    }
}

public enum CaptureDeviceKind: String, CaseIterable, Identifiable, Sendable {
    case camera
    case microphone
    case display
    case window

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .camera: "Camera"
        case .microphone: "Microphone"
        case .display: "Display"
        case .window: "Window"
        }
    }

    public var symbolName: String {
        switch self {
        case .camera: "video"
        case .microphone: "mic"
        case .display: "display"
        case .window: "macwindow"
        }
    }

    public var requiresRestartAfterPermissionGrant: Bool {
        switch self {
        case .display, .window:
            true
        case .camera, .microphone:
            false
        }
    }
}

public enum ScreenCaptureTargetKind: String, Codable, Sendable {
    case display
    case window

    public var title: String {
        switch self {
        case .display: "Display"
        case .window: "Window"
        }
    }
}

public struct ScreenCaptureTarget: Equatable, Hashable, Codable, Identifiable, Sendable {
    public var id: String
    public var kind: ScreenCaptureTargetKind
    public var name: String
    public var detail: String

    public init(id: String, kind: ScreenCaptureTargetKind, name: String, detail: String = "") {
        self.id = id
        self.kind = kind
        self.name = name
        self.detail = detail
    }

    public var title: String {
        detail.isEmpty ? name : "\(name) - \(detail)"
    }
}

public enum CapturePermissionState: String, Sendable {
    case granted
    case denied
    case notDetermined
    case unknown

    public var title: String {
        switch self {
        case .granted: "Granted"
        case .denied: "Denied"
        case .notDetermined: "Ask"
        case .unknown: "Unknown"
        }
    }
}

public struct CaptureDeviceInfo: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: CaptureDeviceKind
    public var name: String
    public var detail: String
    public var permission: CapturePermissionState

    public init(
        id: String,
        kind: CaptureDeviceKind,
        name: String,
        detail: String = "",
        permission: CapturePermissionState
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.detail = detail
        self.permission = permission
    }

    public var screenCaptureTarget: ScreenCaptureTarget? {
        switch kind {
        case .display:
            ScreenCaptureTarget(id: id, kind: .display, name: name, detail: detail)
        case .window:
            ScreenCaptureTarget(id: id, kind: .window, name: name, detail: detail)
        case .camera, .microphone:
            nil
        }
    }

    public var permissionRecoveryHint: String? {
        guard permission != .granted, kind.requiresRestartAfterPermissionGrant else { return nil }
        return "Enable Screen Recording in System Settings. If it is already on, quit and reopen OpenCue."
    }
}

public enum CaptureReadinessState: String, Equatable, Sendable {
    case unchecked
    case checking
    case ready
    case needsAccess
    case needsRelaunch
}

public struct CaptureReadiness: Equatable, Sendable {
    public var state: CaptureReadinessState
    public var title: String
    public var detail: String

    public init(state: CaptureReadinessState, title: String, detail: String) {
        self.state = state
        self.title = title
        self.detail = detail
    }
}

public enum SetupChecklistItemID: String, Codable, Sendable {
    case scene
    case capture
    case destination
    case sources
}

public struct SetupChecklistItem: Identifiable, Equatable, Sendable {
    public var id: SetupChecklistItemID
    public var title: String
    public var detail: String
    public var isComplete: Bool

    public init(id: SetupChecklistItemID, title: String, detail: String, isComplete: Bool) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isComplete = isComplete
    }
}

public struct CapturePreflightReport: Equatable, Sendable {
    public var devices: [CaptureDeviceInfo]
    public var summary: String

    public init(devices: [CaptureDeviceInfo] = [], summary: String = "Not scanned yet.") {
        self.devices = devices
        self.summary = summary
    }

    public var screenCaptureTargets: [ScreenCaptureTarget] {
        devices
            .filter { $0.permission == .granted }
            .compactMap(\.screenCaptureTarget)
    }

    public var requiresRelaunchToRefreshPermissionState: Bool {
        devices.contains { device in
            device.permission != .granted && device.kind.requiresRestartAfterPermissionGrant
        }
    }

    public var isScreenCapturePermissionGranted: Bool {
        devices.contains { device in
            device.permission == .granted && device.kind.requiresRestartAfterPermissionGrant
        }
    }

    public func hasGrantedPermission(for kind: CaptureDeviceKind) -> Bool {
        switch kind {
        case .display, .window:
            isScreenCapturePermissionGranted
        case .camera, .microphone:
            devices.contains { device in
                device.kind == kind && device.permission == .granted
            }
        }
    }

    public func missingPermissionKinds(requiredKinds: [CaptureDeviceKind]) -> [CaptureDeviceKind] {
        var missingKinds: [CaptureDeviceKind] = []
        for kind in requiredKinds where !hasGrantedPermission(for: kind) {
            guard !missingKinds.contains(kind) else { continue }
            missingKinds.append(kind)
        }
        return missingKinds
    }

    public func permissionState(for kind: CaptureDeviceKind) -> CapturePermissionState? {
        switch kind {
        case .display, .window:
            if isScreenCapturePermissionGranted {
                return .granted
            }
            return devices.first { $0.kind == .display || $0.kind == .window }?.permission
        case .camera, .microphone:
            return devices.first { $0.kind == kind }?.permission
        }
    }
}
