import Foundation

public struct SessionReportExporter: Sendable {
    public init() {}

    public func export(
        _ report: SessionReportPayload,
        to directory: URL? = nil
    ) throws -> URL {
        let directory = directory ?? Self.defaultExportDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let outputURL = MacStreamArtifactFileNamer.uniqueURL(
            in: directory,
            prefix: "MacStream-Session",
            fileExtension: "json",
            now: report.exportedAt
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(report)
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    public static func defaultExportDirectory() -> URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        return (movies ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("MacStream", isDirectory: true)
            .appendingPathComponent("Session Reports", isDirectory: true)
    }

}

public struct SessionReportPayload: Codable, Equatable, Sendable {
    public var exportedAt: Date
    public var destinationName: String
    public var streamTransport: StreamTransportKind
    public var recordingPath: String?
    public var sourceStates: [SessionSourceState]
    public var screenCaptureTarget: ScreenCaptureTarget?
    public var preferences: StudioPreferences
    public var effectivePerformanceMode: StudioPerformanceMode
    public var health: StreamHealth
    public var streamRecovery: StreamRecoveryMetrics?
    public var systemPressure: SystemPressureSnapshot
    public var latestSignals: SignalSnapshot
    public var clipMarkers: [ClipMarker]
    public var events: [StudioEvent]

    public init(
        exportedAt: Date,
        destinationName: String,
        streamTransport: StreamTransportKind,
        recordingPath: String?,
        sourceStates: [SessionSourceState] = [],
        screenCaptureTarget: ScreenCaptureTarget? = nil,
        preferences: StudioPreferences,
        effectivePerformanceMode: StudioPerformanceMode,
        health: StreamHealth,
        streamRecovery: StreamRecoveryMetrics? = nil,
        systemPressure: SystemPressureSnapshot = SystemPressureSnapshot(),
        latestSignals: SignalSnapshot,
        clipMarkers: [ClipMarker],
        events: [StudioEvent]
    ) {
        self.exportedAt = exportedAt
        self.destinationName = destinationName
        self.streamTransport = streamTransport
        self.recordingPath = recordingPath
        self.sourceStates = sourceStates
        self.screenCaptureTarget = screenCaptureTarget
        self.preferences = preferences
        self.effectivePerformanceMode = effectivePerformanceMode
        self.health = health
        self.streamRecovery = streamRecovery
        self.systemPressure = systemPressure
        self.latestSignals = latestSignals
        self.clipMarkers = clipMarkers
        self.events = events
    }
}

public struct SessionSourceState: Codable, Equatable, Sendable {
    public var kind: SourceKind
    public var title: String
    public var isEnabled: Bool
    public var level: Double

    public init(kind: SourceKind, title: String, isEnabled: Bool, level: Double) {
        self.kind = kind
        self.title = title
        self.isEnabled = isEnabled
        self.level = min(max(level, 0), 1)
    }

    public init(source: StudioSource) {
        self.init(
            kind: source.kind,
            title: source.title,
            isEnabled: source.isEnabled,
            level: source.level
        )
    }
}
