import AppKit
import SwiftUI
import OpenCueCore

struct EventLogView: View {
    var events: [StudioEvent]
    var clipMarkers: [ClipMarker] = []
    var latestClipExportURL: URL?
    var latestSessionReportURL: URL?
    var exportClips: () -> Void = {}
    var exportReport: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Timeline", systemImage: "list.bullet.rectangle")
                .font(.headline)

            ForEach(events.prefix(8)) { event in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: symbol(for: event.kind))
                        .foregroundStyle(tint(for: event.kind))
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.subheadline.weight(.semibold))
                        Text(event.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            Divider()

            HStack {
                Label(clipMarkers.isEmpty ? "Session" : "Clips", systemImage: clipMarkers.isEmpty ? "doc.text" : "bookmark")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    exportClips()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .disabled(clipMarkers.isEmpty)
                .help(clipMarkers.isEmpty ? "Mark a clip before exporting clips" : "Export clips")

                Button {
                    exportReport()
                } label: {
                    Image(systemName: "doc.badge.gearshape")
                }
                .buttonStyle(.borderless)
                .help("Export session report")
            }

            if !clipMarkers.isEmpty {
                ForEach(clipMarkers.prefix(4)) { marker in
                    ClipMarkerRow(marker: marker)
                }
            }

            if let latestClipExportURL {
                ExportedFileActions(title: "Clips", url: latestClipExportURL)
            }

            if let latestSessionReportURL {
                ExportedFileActions(title: "Report", url: latestSessionReportURL)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func symbol(for kind: StudioEventKind) -> String {
        switch kind {
        case .stream: "dot.radiowaves.left.and.right"
        case .director: "sparkles"
        case .warning: "exclamationmark.triangle"
        case .source: "slider.horizontal.3"
        case .clip: "bookmark"
        }
    }

    private func tint(for kind: StudioEventKind) -> Color {
        switch kind {
        case .stream: .green
        case .director: .accentColor
        case .warning: .orange
        case .source: .secondary
        case .clip: .blue
        }
    }
}

private struct ExportedFileActions: View {
    var title: String
    var url: URL

    var body: some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label("Open", systemImage: "doc.text")
            }
            .disabled(!FileManager.default.fileExists(atPath: url.path))

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Label("Reveal", systemImage: "folder")
            }
            .disabled(!FileManager.default.fileExists(atPath: url.path))
        }
        .controlSize(.small)
    }
}

private struct ClipMarkerRow: View {
    var marker: ClipMarker

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(marker.title)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(marker.source.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(marker.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var symbolName: String {
        marker.source == .director ? "sparkles" : "bookmark.fill"
    }

    private var tint: Color {
        marker.source == .director ? .accentColor : .secondary
    }
}
