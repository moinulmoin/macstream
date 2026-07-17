import CoreGraphics
import Foundation

public enum SceneKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case face
    case screenAndFace
    case screenOnly
    case brb

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .face: "Webcam"
        case .screenAndFace: "Screen + Webcam"
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
        case .camera: "Webcam"
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

public enum OperatorRecoveryGuidanceKind: String, Codable, Equatable, Sendable {
    case failedStart
    case reconnecting
    case recoveryFailed
    case backpressure
}

public enum OperatorRecoveryAction: String, Codable, Equatable, Sendable {
    case retryStream
    case waitForRecovery
    case checkDestination
    case reduceOutputCost
}

public struct OperatorRecoveryGuidance: Identifiable, Codable, Equatable, Sendable {
    public var kind: OperatorRecoveryGuidanceKind
    public var title: String
    public var detail: String
    public var action: OperatorRecoveryAction

    public var id: String { kind.rawValue }

    public init(
        kind: OperatorRecoveryGuidanceKind,
        title: String,
        detail: String,
        action: OperatorRecoveryAction
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.action = action
    }
}

public enum RTMPPublishState: String, Codable, Equatable, Sendable {
    case disconnected
    case handshaking
    case publishing

    public var title: String {
        switch self {
        case .disconnected: "Disconnected"
        case .handshaking: "Handshaking"
        case .publishing: "Publishing"
        }
    }
}

public enum AudioDeliveryState: String, Codable, Equatable, Sendable {
    case inactive
    case awaiting
    case active
    case stalled
}

public struct StreamRecoveryMetrics: Codable, Equatable, Sendable {
    public var interruptionCount: Int
    public var successfulRecoveryCount: Int
    public var failedRecoveryCount: Int
    public var cancelledRecoveryCount: Int
    public var lastDowntimeMilliseconds: Int
    public var totalDowntimeMilliseconds: Int

    public init(
        interruptionCount: Int = 0,
        successfulRecoveryCount: Int = 0,
        failedRecoveryCount: Int = 0,
        cancelledRecoveryCount: Int = 0,
        lastDowntimeMilliseconds: Int = 0,
        totalDowntimeMilliseconds: Int = 0
    ) {
        self.interruptionCount = max(0, interruptionCount)
        self.successfulRecoveryCount = max(0, successfulRecoveryCount)
        self.failedRecoveryCount = max(0, failedRecoveryCount)
        self.cancelledRecoveryCount = max(0, cancelledRecoveryCount)
        self.lastDowntimeMilliseconds = max(0, lastDowntimeMilliseconds)
        self.totalDowntimeMilliseconds = max(0, totalDowntimeMilliseconds)
    }
}

public struct StreamHealth: Codable, Equatable, Sendable {
    public var bitrateKbps: Int
    public var outboundBytesPerSecond: Int64
    public var publishState: RTMPPublishState
    public var droppedFrames: Int
    public var captureFPS: Int
    public var audioLevel: Double
    public var roundTripMs: Int
    public var audioDeliveryState: AudioDeliveryState
    public var microphoneDeliveryState: AudioDeliveryState
    public var rtmpAudioAppendRejections: Int
    public var rtmpPendingAppends: Int
    public var rtmpAppendCapacity: Int
    public var avDriftMilliseconds: Int
    public var maxAbsoluteAVDriftMilliseconds: Int

    public init(
        bitrateKbps: Int = 0,
        outboundBytesPerSecond: Int64 = 0,
        publishState: RTMPPublishState = .disconnected,
        droppedFrames: Int = 0,
        captureFPS: Int = 0,
        audioLevel: Double = 0,
        roundTripMs: Int = 0,
        audioDeliveryState: AudioDeliveryState = .inactive,
        microphoneDeliveryState: AudioDeliveryState = .inactive,
        rtmpAudioAppendRejections: Int = 0,
        rtmpPendingAppends: Int = 0,
        rtmpAppendCapacity: Int = 0,
        avDriftMilliseconds: Int = 0,
        maxAbsoluteAVDriftMilliseconds: Int = 0
    ) {
        self.bitrateKbps = bitrateKbps
        self.outboundBytesPerSecond = outboundBytesPerSecond
        self.publishState = publishState
        self.droppedFrames = droppedFrames
        self.captureFPS = captureFPS
        self.audioLevel = audioLevel
        self.roundTripMs = roundTripMs
        self.audioDeliveryState = audioDeliveryState
        self.microphoneDeliveryState = microphoneDeliveryState
        self.rtmpAudioAppendRejections = rtmpAudioAppendRejections
        self.rtmpPendingAppends = max(0, rtmpPendingAppends)
        self.rtmpAppendCapacity = max(0, rtmpAppendCapacity)
        self.avDriftMilliseconds = avDriftMilliseconds
        self.maxAbsoluteAVDriftMilliseconds = max(0, maxAbsoluteAVDriftMilliseconds)
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
            return "MacStream is using \(memoryUsedMB) MB; Efficiency mode is safer."
        }

        return nil
    }

    public var shouldPreferEfficiency: Bool {
        efficiencyPressureDetail != nil
    }
}

public struct ResourceUsageSnapshot: Codable, Equatable, Sendable {
    public var processMemoryMB: Int
    public var memoryUsagePercent: Int
    public var thermalPressure: SystemPressureLevel
    public var isLowPowerModeEnabled: Bool
    public var streamTargetFPS: Int
    public var streamActualFPS: Int
    public var streamDroppedFrames: Int
    public var streamBitrateKbps: Int
    public var streamOutboundBytesPerSecond: Int64
    public var streamPublishState: RTMPPublishState
    public var streamQueueDepth: Int
    public var previewTargetFPS: Int
    public var previewMaxDisplayWidth: Int
    public var previewQueueDepth: Int
    public var directorSampleIntervalMilliseconds: Int
    public var screenSignalFPS: Int

    public init(
        processMemoryMB: Int,
        memoryUsagePercent: Int,
        thermalPressure: SystemPressureLevel,
        isLowPowerModeEnabled: Bool,
        streamTargetFPS: Int,
        streamActualFPS: Int,
        streamDroppedFrames: Int,
        streamBitrateKbps: Int,
        streamOutboundBytesPerSecond: Int64 = 0,
        streamPublishState: RTMPPublishState = .disconnected,
        streamQueueDepth: Int,
        previewTargetFPS: Int,
        previewMaxDisplayWidth: Int,
        previewQueueDepth: Int,
        directorSampleIntervalMilliseconds: Int,
        screenSignalFPS: Int
    ) {
        self.processMemoryMB = processMemoryMB
        self.memoryUsagePercent = memoryUsagePercent
        self.thermalPressure = thermalPressure
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.streamTargetFPS = streamTargetFPS
        self.streamActualFPS = streamActualFPS
        self.streamDroppedFrames = streamDroppedFrames
        self.streamBitrateKbps = streamBitrateKbps
        self.streamOutboundBytesPerSecond = streamOutboundBytesPerSecond
        self.streamPublishState = streamPublishState
        self.streamQueueDepth = streamQueueDepth
        self.previewTargetFPS = previewTargetFPS
        self.previewMaxDisplayWidth = previewMaxDisplayWidth
        self.previewQueueDepth = previewQueueDepth
        self.directorSampleIntervalMilliseconds = directorSampleIntervalMilliseconds
        self.screenSignalFPS = screenSignalFPS
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
    public var outputResolution: StreamOutputResolution
    public var outputFrameRate: StreamFrameRate
    public var previewRenderQuality: StudioPreviewRenderQuality
    public var layoutSettings: StudioLayoutSettings

    private enum CodingKeys: String, CodingKey {
        case recordWhileStreaming
        case directorCountdownSeconds
        case performanceMode
        case cameraEnhancements
        case outputResolution
        case outputFrameRate
        case previewRenderQuality
        case layoutSettings
    }

    public init(
        recordWhileStreaming: Bool = false,
        directorCountdownSeconds: Int = 2,
        performanceMode: StudioPerformanceMode = .balanced,
        cameraEnhancements: CameraEnhancementSettings = CameraEnhancementSettings(),
        outputResolution: StreamOutputResolution = .automatic,
        outputFrameRate: StreamFrameRate = .automatic,
        previewRenderQuality: StudioPreviewRenderQuality = .automatic,
        layoutSettings: StudioLayoutSettings = StudioLayoutSettings()
    ) {
        self.recordWhileStreaming = recordWhileStreaming
        self.directorCountdownSeconds = Self.normalizedDirectorCountdownSeconds(directorCountdownSeconds)
        self.performanceMode = performanceMode
        self.cameraEnhancements = cameraEnhancements
        self.outputResolution = outputResolution
        self.outputFrameRate = outputFrameRate
        self.previewRenderQuality = previewRenderQuality
        self.layoutSettings = layoutSettings
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
        outputResolution = try container.decodeIfPresent(
            StreamOutputResolution.self,
            forKey: .outputResolution
        ) ?? .automatic
        outputFrameRate = try container.decodeIfPresent(
            StreamFrameRate.self,
            forKey: .outputFrameRate
        ) ?? .automatic
        previewRenderQuality = try container.decodeIfPresent(
            StudioPreviewRenderQuality.self,
            forKey: .previewRenderQuality
        ) ?? .automatic
        layoutSettings = try container.decodeIfPresent(
            StudioLayoutSettings.self,
            forKey: .layoutSettings
        ) ?? StudioLayoutSettings()
    }

    public static func normalizedDirectorCountdownSeconds(_ seconds: Int) -> Int {
        min(max(seconds, minimumDirectorCountdownSeconds), maximumDirectorCountdownSeconds)
    }
}

public enum StreamOutputResolution: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic
    case hd720
    case fullHD1080
    case qhd2K
    case ultraHD4K

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: "Auto"
        case .hd720: "720p"
        case .fullHD1080: "1080p"
        case .qhd2K: "2K"
        case .ultraHD4K: "4K"
        }
    }

    public var detailTitle: String {
        switch self {
        case .automatic: "Follows performance mode"
        case .hd720: "Up to 1280 px wide"
        case .fullHD1080: "Up to 1920 px wide"
        case .qhd2K: "Up to 2560 px wide"
        case .ultraHD4K: "Up to 3840 px wide"
        }
    }

    public var maxVideoWidth: Int? {
        switch self {
        case .automatic: nil
        case .hd720: 1_280
        case .fullHD1080: 1_920
        case .qhd2K: 2_560
        case .ultraHD4K: 3_840
        }
    }
}

public enum StreamFrameRate: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic
    case fps24
    case fps30
    case fps60

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: "Auto"
        case .fps24: "24 FPS"
        case .fps30: "30 FPS"
        case .fps60: "60 FPS"
        }
    }

    public var framesPerSecond: Int? {
        switch self {
        case .automatic: nil
        case .fps24: 24
        case .fps30: 30
        case .fps60: 60
        }
    }
}

public enum StudioPreviewRenderQuality: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic
    case half
    case full

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: "Balanced"
        case .half: "Performance"
        case .full: "Sharp"
        }
    }

    public var detailTitle: String {
        switch self {
        case .automatic: "Balanced preview"
        case .half: "Performance preview"
        case .full: "Sharp preview"
        }
    }
}

public enum StudioLayoutPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case pictureInPicture
    case screen70Webcam30
    case evenSplit
    case screen30Webcam70

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pictureInPicture: "Picture in Picture"
        case .screen70Webcam30: "Screen 70 / Webcam 30"
        case .evenSplit: "Screen 50 / Webcam 50"
        case .screen30Webcam70: "Screen 30 / Webcam 70"
        }
    }

    public var shortTitle: String {
        switch self {
        case .pictureInPicture: "PiP"
        case .screen70Webcam30: "70/30"
        case .evenSplit: "50/50"
        case .screen30Webcam70: "30/70"
        }
    }

    public var symbolName: String {
        switch self {
        case .pictureInPicture: "rectangle.inset.filled"
        case .screen70Webcam30: "rectangle.leadingthird.inset.filled"
        case .evenSplit: "rectangle.split.2x1"
        case .screen30Webcam70: "rectangle.trailingthird.inset.filled"
        }
    }

    public var isSplit: Bool {
        self != .pictureInPicture
    }

    public var screenFraction: Double {
        switch self {
        case .pictureInPicture: 1
        case .screen70Webcam30: 0.70
        case .evenSplit: 0.50
        case .screen30Webcam70: 0.30
        }
    }
}

public enum StudioBackgroundStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case black
    case studio
    case stage
    case warm

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .black: "Black"
        case .studio: "Studio"
        case .stage: "Stage"
        case .warm: "Warm"
        }
    }
}

public struct StudioSourceViewportSettings: Codable, Equatable, Sendable {
    public var zoom: Double {
        didSet {
            zoom = StudioLayoutSettings.normalizedSourceZoom(zoom)
        }
    }
    public var panX: Double {
        didSet {
            panX = StudioLayoutSettings.normalizedSourcePan(panX)
        }
    }
    public var panY: Double {
        didSet {
            panY = StudioLayoutSettings.normalizedSourcePan(panY)
        }
    }

    public init(zoom: Double = 1, panX: Double = 0, panY: Double = 0) {
        self.zoom = StudioLayoutSettings.normalizedSourceZoom(zoom)
        self.panX = StudioLayoutSettings.normalizedSourcePan(panX)
        self.panY = StudioLayoutSettings.normalizedSourcePan(panY)
    }

    private enum CodingKeys: String, CodingKey {
        case zoom
        case panX
        case panY
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            zoom: try container.decodeIfPresent(Double.self, forKey: .zoom) ?? 1,
            panX: try container.decodeIfPresent(Double.self, forKey: .panX) ?? 0,
            panY: try container.decodeIfPresent(Double.self, forKey: .panY) ?? 0
        )
    }
}

public struct StudioRGBAColor: Codable, Equatable, Sendable {
    public var red: Double {
        didSet {
            red = StudioLayoutSettings.normalizedColorComponent(red)
        }
    }
    public var green: Double {
        didSet {
            green = StudioLayoutSettings.normalizedColorComponent(green)
        }
    }
    public var blue: Double {
        didSet {
            blue = StudioLayoutSettings.normalizedColorComponent(blue)
        }
    }
    public var alpha: Double {
        didSet {
            alpha = StudioLayoutSettings.normalizedColorComponent(alpha)
        }
    }

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = StudioLayoutSettings.normalizedColorComponent(red)
        self.green = StudioLayoutSettings.normalizedColorComponent(green)
        self.blue = StudioLayoutSettings.normalizedColorComponent(blue)
        self.alpha = StudioLayoutSettings.normalizedColorComponent(alpha)
    }

    private enum CodingKeys: String, CodingKey {
        case red
        case green
        case blue
        case alpha
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            red: try container.decodeIfPresent(Double.self, forKey: .red) ?? 0,
            green: try container.decodeIfPresent(Double.self, forKey: .green) ?? 0,
            blue: try container.decodeIfPresent(Double.self, forKey: .blue) ?? 0,
            alpha: try container.decodeIfPresent(Double.self, forKey: .alpha) ?? 1
        )
    }
}

public enum StudioCanvasBackground: Codable, Equatable, Sendable {
    case preset(StudioBackgroundStyle)
    case color(StudioRGBAColor)
    case localImage(path: String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case style
        case color
        case path
    }

    private enum Kind: String, Codable {
        case preset
        case color
        case localImage
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .preset
        switch kind {
        case .preset:
            self = .preset(try container.decodeIfPresent(StudioBackgroundStyle.self, forKey: .style) ?? .black)
        case .color:
            self = .color(try container.decodeIfPresent(StudioRGBAColor.self, forKey: .color) ?? StudioRGBAColor(red: 0, green: 0, blue: 0))
        case .localImage:
            self = .localImage(path: try container.decodeIfPresent(String.self, forKey: .path) ?? "")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .preset(style):
            try container.encode(Kind.preset, forKey: .kind)
            try container.encode(style, forKey: .style)
        case let .color(color):
            try container.encode(Kind.color, forKey: .kind)
            try container.encode(color, forKey: .color)
        case let .localImage(path):
            try container.encode(Kind.localImage, forKey: .kind)
            try container.encode(path, forKey: .path)
        }
    }

    public var presetStyle: StudioBackgroundStyle? {
        if case let .preset(style) = self { return style }
        return nil
    }
}

public enum StudioPresenterCompositionMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case preserveLayout
    case presenterOverlay

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .preserveLayout: "Framed"
        case .presenterOverlay: "Cutout"
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self(rawValue: rawValue) ?? .preserveLayout
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum StudioPresenterPlacement: String, CaseIterable, Codable, Identifiable, Sendable {
    case left
    case right
    case top
    case bottom
    case manual

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .top: "Top"
        case .bottom: "Bottom"
        case .manual: "Manual"
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self(rawValue: rawValue) ?? .right
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct StudioNormalizedPoint: Codable, Equatable, Sendable {
    public var x: Double {
        didSet {
            x = StudioLayoutSettings.normalizedUnitValue(x)
        }
    }
    public var y: Double {
        didSet {
            y = StudioLayoutSettings.normalizedUnitValue(y)
        }
    }

    public init(x: Double = 0.5, y: Double = 0.5) {
        self.x = StudioLayoutSettings.normalizedUnitValue(x)
        self.y = StudioLayoutSettings.normalizedUnitValue(y)
    }

    private enum CodingKeys: String, CodingKey {
        case x
        case y
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: try container.decodeIfPresent(Double.self, forKey: .x) ?? 0.5,
            y: try container.decodeIfPresent(Double.self, forKey: .y) ?? 0.5
        )
    }
}

public struct StudioPresenterCompositionSettings: Codable, Equatable, Sendable {
    public static let minimumScale = 0.12
    public static let maximumScale = 0.50
    public static let defaultScale = 0.28

    public var mode: StudioPresenterCompositionMode
    public var placement: StudioPresenterPlacement
    public var manualPosition: StudioNormalizedPoint
    public var scale: Double {
        didSet {
            scale = Self.normalizedScale(scale)
        }
    }

    public init(
        mode: StudioPresenterCompositionMode = .preserveLayout,
        placement: StudioPresenterPlacement = .right,
        manualPosition: StudioNormalizedPoint = StudioNormalizedPoint(x: 0.82, y: 0.24),
        scale: Double = Self.defaultScale
    ) {
        self.mode = mode
        self.placement = placement
        self.manualPosition = manualPosition
        self.scale = Self.normalizedScale(scale)
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case placement
        case manualPosition
        case scale
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            mode: try container.decodeIfPresent(StudioPresenterCompositionMode.self, forKey: .mode) ?? .preserveLayout,
            placement: try container.decodeIfPresent(StudioPresenterPlacement.self, forKey: .placement) ?? .right,
            manualPosition: try container.decodeIfPresent(StudioNormalizedPoint.self, forKey: .manualPosition)
                ?? StudioNormalizedPoint(x: 0.82, y: 0.24),
            scale: try container.decodeIfPresent(Double.self, forKey: .scale) ?? Self.defaultScale
        )
    }

    public static func normalizedScale(_ scale: Double) -> Double {
        let finiteScale = scale.isFinite ? scale : defaultScale
        let clamped = min(max(finiteScale, minimumScale), maximumScale)
        return (clamped * 100).rounded() / 100
    }
}

public struct StudioLayoutSettings: Codable, Equatable, Sendable {
    public static let minimumSourceZoom = 0.75
    public static let maximumSourceZoom = 2.0
    public static let minimumCanvasPadding = 0.0
    public static let maximumCanvasPadding = 0.12
    public static let minimumSourceGap = 0.0
    public static let maximumSourceGap = 0.12
    public static let minimumSourceCornerRadius = 0.0
    public static let maximumSourceCornerRadius = 0.12
    public static let defaultSourceCornerRadius = 0.018
    public static let minimumSourcePan = -1.0
    public static let maximumSourcePan = 1.0

    public var preset: StudioLayoutPreset
    public var background: StudioCanvasBackground
    public var canvasPadding: Double {
        didSet {
            canvasPadding = Self.normalizedCanvasPadding(canvasPadding)
        }
    }
    public var screenViewport: StudioSourceViewportSettings
    public var webcamViewport: StudioSourceViewportSettings
    public var sourceGap: Double {
        didSet {
            sourceGap = Self.normalizedSourceGap(sourceGap)
        }
    }
    public var sourceCornerRadius: Double {
        didSet {
            sourceCornerRadius = Self.normalizedSourceCornerRadius(sourceCornerRadius)
        }
    }
    public var presenterComposition: StudioPresenterCompositionSettings

    public var backgroundStyle: StudioBackgroundStyle {
        get {
            background.presetStyle ?? .black
        }
        set {
            background = .preset(newValue)
        }
    }

    public var screenZoom: Double {
        get {
            screenViewport.zoom
        }
        set {
            screenViewport.zoom = newValue
        }
    }
    public var webcamZoom: Double {
        get {
            webcamViewport.zoom
        }
        set {
            webcamViewport.zoom = newValue
        }
    }

    private enum CodingKeys: String, CodingKey {
        case preset
        case background
        case canvasPadding
        case screenViewport
        case webcamViewport
        case sourceGap
        case sourceCornerRadius
        case presenterComposition
    }

    public init(
        preset: StudioLayoutPreset = .pictureInPicture,
        backgroundStyle: StudioBackgroundStyle = .black,
        canvasPadding: Double = 0.04,
        screenZoom: Double = 1,
        webcamZoom: Double = 1,
        sourceGap: Double? = nil,
        sourceCornerRadius: Double = 0.018,
        presenterComposition: StudioPresenterCompositionSettings = StudioPresenterCompositionSettings()
    ) {
        self.init(
            preset: preset,
            background: .preset(backgroundStyle),
            canvasPadding: canvasPadding,
            screenViewport: StudioSourceViewportSettings(zoom: screenZoom),
            webcamViewport: StudioSourceViewportSettings(zoom: webcamZoom),
            sourceGap: sourceGap,
            sourceCornerRadius: sourceCornerRadius,
            presenterComposition: presenterComposition
        )
    }

    public init(
        preset: StudioLayoutPreset = .pictureInPicture,
        background: StudioCanvasBackground,
        canvasPadding: Double = 0.04,
        screenViewport: StudioSourceViewportSettings = StudioSourceViewportSettings(),
        webcamViewport: StudioSourceViewportSettings = StudioSourceViewportSettings(),
        sourceGap: Double? = nil,
        sourceCornerRadius: Double = 0.018,
        presenterComposition: StudioPresenterCompositionSettings = StudioPresenterCompositionSettings()
    ) {
        self.preset = preset
        self.canvasPadding = Self.normalizedCanvasPadding(canvasPadding)
        self.background = background
        self.screenViewport = StudioSourceViewportSettings(
            zoom: screenViewport.zoom,
            panX: screenViewport.panX,
            panY: screenViewport.panY
        )
        self.webcamViewport = StudioSourceViewportSettings(
            zoom: webcamViewport.zoom,
            panX: webcamViewport.panX,
            panY: webcamViewport.panY
        )
        self.sourceGap = Self.normalizedSourceGap(sourceGap ?? Self.defaultSourceGap(canvasPadding: self.canvasPadding))
        self.sourceCornerRadius = Self.normalizedSourceCornerRadius(sourceCornerRadius)
        self.presenterComposition = presenterComposition
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let canvasPadding = Self.normalizedCanvasPadding(
            try container.decodeIfPresent(Double.self, forKey: .canvasPadding) ?? 0.04
        )
        let background = try container.decodeIfPresent(
            StudioCanvasBackground.self,
            forKey: .background
        ) ?? .preset(.black)
        let screenViewport = try container.decodeIfPresent(
            StudioSourceViewportSettings.self,
            forKey: .screenViewport
        ) ?? StudioSourceViewportSettings()
        let webcamViewport = try container.decodeIfPresent(
            StudioSourceViewportSettings.self,
            forKey: .webcamViewport
        ) ?? StudioSourceViewportSettings()
        self.init(
            preset: try container.decodeIfPresent(StudioLayoutPreset.self, forKey: .preset) ?? .pictureInPicture,
            background: background,
            canvasPadding: canvasPadding,
            screenViewport: screenViewport,
            webcamViewport: webcamViewport,
            sourceGap: try container.decodeIfPresent(Double.self, forKey: .sourceGap) ?? Self.defaultSourceGap(canvasPadding: canvasPadding),
            sourceCornerRadius: try container.decodeIfPresent(Double.self, forKey: .sourceCornerRadius)
                ?? Self.defaultSourceCornerRadius,
            presenterComposition: try container.decodeIfPresent(
                StudioPresenterCompositionSettings.self,
                forKey: .presenterComposition
            ) ?? StudioPresenterCompositionSettings()
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(preset, forKey: .preset)
        try container.encode(background, forKey: .background)
        try container.encode(canvasPadding, forKey: .canvasPadding)
        try container.encode(screenViewport, forKey: .screenViewport)
        try container.encode(webcamViewport, forKey: .webcamViewport)
        try container.encode(sourceGap, forKey: .sourceGap)
        try container.encode(sourceCornerRadius, forKey: .sourceCornerRadius)
        try container.encode(presenterComposition, forKey: .presenterComposition)
    }

    public static func normalizedSourceZoom(_ zoom: Double) -> Double {
        quantizedClamp(zoom, minimum: minimumSourceZoom, maximum: maximumSourceZoom, fallback: 1, scale: 100)
    }

    public static func normalizedCanvasPadding(_ padding: Double) -> Double {
        quantizedClamp(padding, minimum: minimumCanvasPadding, maximum: maximumCanvasPadding, fallback: 0.04, scale: 100)
    }

    public static func normalizedSourceGap(_ gap: Double) -> Double {
        quantizedClamp(gap, minimum: minimumSourceGap, maximum: maximumSourceGap, fallback: defaultSourceGap(canvasPadding: 0.04), scale: 1_000)
    }

    public static func normalizedSourceCornerRadius(_ radius: Double) -> Double {
        quantizedClamp(
            radius,
            minimum: minimumSourceCornerRadius,
            maximum: maximumSourceCornerRadius,
            fallback: defaultSourceCornerRadius,
            scale: 1_000
        )
    }

    public static func normalizedSourcePan(_ pan: Double) -> Double {
        quantizedClamp(pan, minimum: minimumSourcePan, maximum: maximumSourcePan, fallback: 0, scale: 100)
    }

    public static func normalizedColorComponent(_ component: Double) -> Double {
        quantizedClamp(component, minimum: 0, maximum: 1, fallback: 1, scale: 1_000)
    }

    public static func normalizedUnitValue(_ value: Double) -> Double {
        quantizedClamp(value, minimum: 0, maximum: 1, fallback: 0.5, scale: 1_000)
    }

    public static func defaultSourceGap(canvasPadding: Double) -> Double {
        normalizedCanvasPadding(canvasPadding) > 0 ? 0.024 : 0
    }

    private static func quantizedClamp(
        _ value: Double,
        minimum: Double,
        maximum: Double,
        fallback: Double,
        scale: Double
    ) -> Double {
        let finiteValue = value.isFinite ? value : fallback
        let clamped = min(max(finiteValue, minimum), maximum)
        return (clamped * scale).rounded() / scale
    }
}

public struct StudioCanvasLayout: Equatable, Sendable {
    public var outputRect: CGRect
    public var contentRect: CGRect
    public var canvasInset: CGFloat
    public var sourceGap: CGFloat
    public var sourceCornerRadius: CGFloat
    public var settings: StudioLayoutSettings

    public init(size: CGSize, settings: StudioLayoutSettings) {
        let safeSize = CGSize(
            width: Self.safeDimension(size.width),
            height: Self.safeDimension(size.height)
        )
        self.outputRect = CGRect(origin: .zero, size: safeSize)
        self.settings = settings
        self.canvasInset = min(safeSize.width, safeSize.height) * settings.canvasPadding

        let contentWidth = max(1, safeSize.width - (canvasInset * 2))
        let contentHeight = max(1, safeSize.height - (canvasInset * 2))
        self.contentRect = CGRect(
            x: canvasInset,
            y: canvasInset,
            width: contentWidth,
            height: contentHeight
        )

        if settings.preset.isSplit {
            self.sourceGap = min(contentWidth - 1, min(contentWidth, contentHeight) * settings.sourceGap)
        } else {
            self.sourceGap = 0
        }
        self.sourceCornerRadius = min(contentWidth, contentHeight) * settings.sourceCornerRadius
    }

    public var splitScreenRect: CGRect {
        let screenWidth = max(1, (contentRect.width - sourceGap) * settings.preset.screenFraction)
        return CGRect(
            x: contentRect.minX,
            y: contentRect.minY,
            width: screenWidth,
            height: contentRect.height
        )
    }

    public var splitWebcamRect: CGRect {
        let x = splitScreenRect.maxX + sourceGap
        return CGRect(
            x: x,
            y: contentRect.minY,
            width: max(1, contentRect.maxX - x),
            height: contentRect.height
        )
    }

    public var pictureInPictureRect: CGRect {
        let margin = max(18, contentRect.width * 0.018)
        let width = min(contentRect.width * 0.28, 360)
        let height = width * 9 / 16
        return CGRect(
            x: contentRect.maxX - width - margin,
            y: contentRect.minY + margin,
            width: width,
            height: min(height, max(1, contentRect.height - (margin * 2)))
        )
    }

    public var presenterComposition: StudioPresenterCompositionGeometry {
        if settings.presenterComposition.mode == .preserveLayout {
            if settings.preset.isSplit {
                return StudioPresenterCompositionGeometry(
                    screenRect: splitScreenRect,
                    presenterRect: splitWebcamRect
                )
            }
            return StudioPresenterCompositionGeometry(
                screenRect: contentRect,
                presenterRect: pictureInPictureRect
            )
        }

        return StudioPresenterCompositionGeometry(
            screenRect: contentRect,
            presenterRect: presenterOverlayRect
        )
    }

    public var presenterOverlayRect: CGRect {
        let presenterSettings = settings.presenterComposition
        let margin = max(12, min(contentRect.width, contentRect.height) * 0.024)
        let presenterWidth = min(
            max(1, contentRect.width - (margin * 2)),
            max(1, contentRect.width * presenterSettings.scale)
        )
        let presenterHeight = min(
            max(1, contentRect.height - (margin * 2)),
            max(1, presenterWidth * 9 / 16)
        )
        let origin = presenterOverlayOrigin(
            size: CGSize(width: presenterWidth, height: presenterHeight),
            margin: margin
        )

        return CGRect(
            x: origin.x,
            y: origin.y,
            width: presenterWidth,
            height: presenterHeight
        )
    }

    private func presenterOverlayOrigin(size: CGSize, margin: CGFloat) -> CGPoint {
        let clampedMinX = contentRect.minX + margin
        let clampedMaxX = contentRect.maxX - margin - size.width
        let clampedMinY = contentRect.minY + margin
        let clampedMaxY = contentRect.maxY - margin - size.height
        let safeMinX = min(clampedMinX, clampedMaxX)
        let safeMaxX = max(clampedMinX, clampedMaxX)
        let safeMinY = min(clampedMinY, clampedMaxY)
        let safeMaxY = max(clampedMinY, clampedMaxY)
        let centeredX = min(max(contentRect.midX - (size.width / 2), safeMinX), safeMaxX)
        let centeredY = min(max(contentRect.midY - (size.height / 2), safeMinY), safeMaxY)

        switch settings.presenterComposition.placement {
        case .left:
            return CGPoint(x: safeMinX, y: centeredY)
        case .right:
            return CGPoint(x: safeMaxX, y: centeredY)
        case .top:
            return CGPoint(x: centeredX, y: safeMaxY)
        case .bottom:
            return CGPoint(x: centeredX, y: safeMinY)
        case .manual:
            let position = settings.presenterComposition.manualPosition
            let x = contentRect.minX + (contentRect.width * position.x) - (size.width / 2)
            let y = contentRect.minY + (contentRect.height * position.y) - (size.height / 2)
            return CGPoint(
                x: min(max(x, safeMinX), safeMaxX),
                y: min(max(y, safeMinY), safeMaxY)
            )
        }
    }

    private static func safeDimension(_ dimension: CGFloat) -> CGFloat {
        dimension.isFinite ? max(1, dimension) : 1
    }
}

public struct StudioPresenterCompositionGeometry: Equatable, Sendable {
    public var screenRect: CGRect
    public var presenterRect: CGRect

    public init(screenRect: CGRect, presenterRect: CGRect) {
        self.screenRect = screenRect
        self.presenterRect = presenterRect
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
    public static let liveStreamingPreviewConfiguration = PreviewCaptureConfiguration(
        maxDisplayWidth: 960,
        framesPerSecond: 12,
        queueDepth: 1
    )

    public static let liveStreamingSignalSamplingConfiguration = SignalSamplingConfiguration(
        screenMotionFramesPerSecond: 2
    )

    public static let liveStreamingDirectorSampleIntervalMilliseconds = 2_000

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
    public var microphoneDeviceID: String?
    public var isScreenMotionEnabled: Bool
    public var isActivityContextEnabled: Bool
    public var screenCaptureTarget: ScreenCaptureTarget?

    public init(
        screenMotionFramesPerSecond: Int = 4,
        isMicrophoneEnabled: Bool = true,
        microphoneDeviceID: String? = nil,
        isScreenMotionEnabled: Bool = true,
        isActivityContextEnabled: Bool = true,
        screenCaptureTarget: ScreenCaptureTarget? = nil
    ) {
        self.screenMotionFramesPerSecond = max(1, screenMotionFramesPerSecond)
        self.isMicrophoneEnabled = isMicrophoneEnabled
        self.microphoneDeviceID = microphoneDeviceID
        self.isScreenMotionEnabled = isScreenMotionEnabled
        self.isActivityContextEnabled = isActivityContextEnabled
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
    public var layoutSettings: StudioLayoutSettings
    public var cameraDeviceID: String?
    public var microphoneDeviceID: String?

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
        cameraEnhancements: CameraEnhancementSettings = CameraEnhancementSettings(),
        layoutSettings: StudioLayoutSettings = StudioLayoutSettings(),
        cameraDeviceID: String? = nil,
        microphoneDeviceID: String? = nil
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
        self.layoutSettings = layoutSettings
        self.cameraDeviceID = cameraDeviceID
        self.microphoneDeviceID = microphoneDeviceID
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

    public static func cameraID(uniqueID: String) -> String { "camera-\(uniqueID)" }
    public static func microphoneID(uniqueID: String) -> String { "microphone-\(uniqueID)" }

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
        return "Enable Screen Recording in System Settings. If it is already on, quit and reopen MacStream."
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


    public var permissionAttentionKindCount: Int {
        var keys: Set<String> = []
        for device in devices where device.permission != .granted {
            switch device.kind {
            case .camera, .microphone:
                keys.insert(device.kind.rawValue)
            case .display, .window:
                keys.insert("screen")
            }
        }
        return keys.count
    }

    public static func permissionAttentionSummary(for devices: [CaptureDeviceInfo]) -> String {
        let count = CapturePreflightReport(devices: devices).permissionAttentionKindCount
        switch count {
        case 0:
            return "Capture sources are ready."
        case 1:
            return "1 capture permission needs attention."
        default:
            return "\(count) capture permissions need attention."
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
