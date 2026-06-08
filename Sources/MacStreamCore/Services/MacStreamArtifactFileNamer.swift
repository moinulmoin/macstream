import Foundation

enum MacStreamArtifactFileNamer {
    static func uniqueURL(
        in directory: URL,
        prefix: String,
        fileExtension: String,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> URL {
        let timestamp = timestamp(from: now)
        let baseName = "\(prefix)-\(timestamp)"
        var outputURL = directory.appendingPathComponent(baseName).appendingPathExtension(fileExtension)
        var suffix = 2

        while fileManager.fileExists(atPath: outputURL.path) {
            outputURL = directory
                .appendingPathComponent("\(baseName)-\(suffix)")
                .appendingPathExtension(fileExtension)
            suffix += 1
        }

        return outputURL
    }

    static func timestamp(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
            .withDashSeparatorInDate,
            .withColonSeparatorInTime
        ]
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
    }
}
