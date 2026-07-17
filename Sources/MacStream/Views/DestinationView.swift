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
                subtitle: store.destinationSummary
            ) {
                HStack(spacing: StudioMetrics.sm) {
                    StudioBadge(title: destinationStatusTitle, systemImage: store.destinationMode.symbolName, tint: destinationDetailTint)

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

            if store.destinationMode == .rtmp {
                VStack(alignment: .leading, spacing: StudioMetrics.xs) {
                    Label(store.destinationSummary, systemImage: "list.bullet.rectangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(destinationDetailTint)

                    if let validationError = store.destinationValidationError {
                        Text(validationError)
                            .font(.caption)
                            .foregroundStyle(StudioPalette.warning)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(displayedDestinationStatuses) { status in
                        destinationStatusRow(status)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: StudioMetrics.sm) {
                    Label(store.destination.safeDisplayDetail, systemImage: store.destinationMode.symbolName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(destinationDetailTint)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: StudioMetrics.sm)
                }
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
            get: { store.destinationMode },
            set: { store.setDestinationMode($0) }
        )
    }

    private var destinationStatusTitle: String {
        store.destinationValidationError == nil ? "Ready" : "Needs setup"
    }

    private var destinationDetailTint: Color {
        store.destinationValidationError == nil ? .secondary : StudioPalette.warning
    }

    private var displayedDestinationStatuses: [StreamDestinationStatus] {
        if !store.destinationStatuses.isEmpty {
            return store.destinationStatuses
        }

        return store.destinations.map { destination in
            StreamDestinationStatus(
                id: destination.id,
                name: destination.name,
                state: destination.isEnabled ? (destination.isReadyToStart ? .idle : .failed) : .idle,
                failureDetail: destination.isEnabled ? destination.validationError : "Disabled"
            )
        }
    }

    private func destinationStatusRow(_ status: StreamDestinationStatus) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: StudioMetrics.sm) {
            Image(systemName: statusSymbol(status))
                .foregroundStyle(statusTint(status))
                .frame(width: 14)

            Text(status.name.isEmpty ? "RTMP Destination" : status.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            Text(status.state == .publishing ? "Live" : status.state.title)
                .font(.caption)
                .foregroundStyle(statusTint(status))

            if let failureDetail = status.failureDetail, !failureDetail.isEmpty {
                Text(failureDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: StudioMetrics.sm)
        }
        .accessibilityElement(children: .combine)
    }

    private func statusSymbol(_ status: StreamDestinationStatus) -> String {
        switch status.state {
        case .publishing: "checkmark.circle.fill"
        case .connecting, .degraded, .reconnecting: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.triangle.fill"
        case .idle: "circle"
        }
    }

    private func statusTint(_ status: StreamDestinationStatus) -> Color {
        switch status.state {
        case .publishing: StudioPalette.success
        case .connecting, .degraded, .reconnecting: StudioPalette.warning
        case .failed: StudioPalette.live
        case .idle: status.failureDetail == "Disabled" ? .secondary : destinationDetailTint
        }
    }
}
