import AppKit
import SwiftUI
import MacStreamCore

struct DestinationView: View {
    var store: StudioStore

    var body: some View {
        VStack(alignment: .leading, spacing: StudioMetrics.md) {
            StudioPanelHeader(
                title: "Destination",
                systemImage: "point.3.connected.trianglepath.dotted",
                subtitle: store.destination.safeDisplayDetail
            ) {
                HStack(spacing: StudioMetrics.sm) {
                    StudioBadge(title: store.destination.isReadyToStart ? "Ready" : "Needs setup", systemImage: store.destination.mode.symbolName, tint: destinationDetailTint)

                    SettingsLink {
                        Label("Configure", systemImage: "gearshape")
                            .labelStyle(.titleAndIcon)
                    }
                    .controlSize(.small)
                    .help("Open destination setup")
                }
            }
            Picker("Destination Mode", selection: destinationMode) {
                ForEach(StreamDestinationMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbolName)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!store.canEditDestination)

            HStack(alignment: .firstTextBaseline, spacing: StudioMetrics.sm) {
                Label(store.destination.safeDisplayDetail, systemImage: store.destination.mode.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(destinationDetailTint)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: StudioMetrics.sm)
            }

            if let url = store.lastRecordingURL {
                VStack(alignment: .leading, spacing: StudioMetrics.sm) {
                    Divider()

                    Label("Last Recording", systemImage: "record.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)

                    HStack(spacing: StudioMetrics.sm) {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("Open", systemImage: "play.rectangle")
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
        }
        .studioCard()
    }

    private var destinationMode: Binding<StreamDestinationMode> {
        Binding(
            get: { store.destination.mode },
            set: { store.setDestinationMode($0) }
        )
    }

    private var destinationDetailTint: Color {
        store.destination.isReadyToStart ? .secondary : StudioPalette.warning
    }
}
