import AppKit
import SwiftUI
import MacStreamCore

struct EventLogView: View {
    var events: [StudioEvent]
    var clipMarkers: [ClipMarker] = []
    var latestClipExportURL: URL?
    var latestSessionReportURL: URL?
    var exportClips: () -> Void = {}
    var exportReport: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: StudioMetrics.md) {
            StudioPanelHeader(title: "Timeline", systemImage: "list.bullet.rectangle", tint: StudioPalette.info)

            ForEach(events.prefix(8)) { event in
                HStack(alignment: .top, spacing: StudioMetrics.sm) {
                    Image(systemName: symbol(for: event.kind))
                        .foregroundStyle(tint(for: event.kind))
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: StudioMetrics.xs) {
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

            HStack(spacing: StudioMetrics.sm) {
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
                .accessibilityLabel(Text("Export clips"))

                Button {
                    exportReport()
                } label: {
                    Image(systemName: "doc.badge.gearshape")
                }
                .buttonStyle(.borderless)
                .help("Export session report")
                .accessibilityLabel(Text("Export session report"))
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
        .studioCard()
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
        case .stream: StudioPalette.success
        case .director: StudioPalette.accent
        case .warning: StudioPalette.warning
        case .source: .secondary
        case .clip: StudioPalette.info
        }
    }
}

private struct ExportedFileActions: View {
    var title: String
    var url: URL

    var body: some View {
        HStack(spacing: StudioMetrics.sm) {
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
        HStack(alignment: .top, spacing: StudioMetrics.sm) {
            Image(systemName: symbolName)
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: StudioMetrics.xs) {
                HStack(spacing: StudioMetrics.sm) {
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
        marker.source == .director ? StudioPalette.accent : .secondary
    }
}
