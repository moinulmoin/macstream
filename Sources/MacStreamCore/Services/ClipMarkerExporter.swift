import Foundation

public struct ClipMarkerExporter: Sendable {
    public init() {}

    public func export(
        _ markers: [ClipMarker],
        to directory: URL? = nil,
        now: Date = Date()
    ) throws -> URL {
        let directory = directory ?? Self.defaultExportDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let outputURL = MacStreamArtifactFileNamer.uniqueURL(
            in: directory,
            prefix: "MacStream-Clips",
            fileExtension: "json",
            now: now
        )
        let payload = ClipMarkerExportPayload(exportedAt: now, markers: markers)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(payload)
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    public static func defaultExportDirectory() -> URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        return (movies ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("MacStream", isDirectory: true)
            .appendingPathComponent("Clip Exports", isDirectory: true)
    }

}

public struct ClipMarkerExportPayload: Codable, Equatable, Sendable {
    public var exportedAt: Date
    public var markers: [ClipMarker]

    public init(exportedAt: Date, markers: [ClipMarker]) {
        self.exportedAt = exportedAt
        self.markers = markers
    }
}
