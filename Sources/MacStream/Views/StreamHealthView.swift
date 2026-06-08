import SwiftUI
import MacStreamCore

struct StreamHealthView: View {
    var store: StudioStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(healthTitle, systemImage: transportSymbol)
                        .font(.headline)

                    Text(store.streamStatusDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    StudioBadge(title: store.streamState.title, systemImage: transportSymbol, tint: statusTint)
                    StudioBadge(title: store.recordingState.title, systemImage: "record.circle", tint: recordingTint)
                }
            }

            HStack {
                Label(store.streamTransport.title, systemImage: transportSymbol)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(store.streamTransport.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if store.preferences.performanceMode == .adaptive {
                Label("Using \(store.effectivePerformanceMode.title)", systemImage: "gauge.with.dots.needle.50percent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(store.effectivePerformanceMode == .efficiency ? .orange : .secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                metric("Bitrate", "\(store.health.bitrateKbps)", "kbps")
                metric("Frames", "\(store.health.droppedFrames)", "dropped")
                metric("Capture", "\(store.health.captureFPS)", "fps")
                metric("Latency", "\(store.health.roundTripMs)", "ms")
                metric("Thermal", store.systemPressure.thermalPressure.title, "")
                metric("Memory", "\(store.systemPressure.memoryUsedMB)", "MB")
            }

            if let efficiencyPressureDetail = store.systemPressure.efficiencyPressureDetail {
                Label(efficiencyPressureDetail, systemImage: "speedometer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .studioCard()
    }

    private var healthTitle: String {
        switch store.streamTransport {
        case .preview:
            "Preview"
        case .endpointValidation, .rtmpPublish:
            "Stream"
        }
    }

    private var statusTint: Color {
        switch store.streamState {
        case .offline: .secondary
        case .connecting: .orange
        case .live: .green
        case .degraded, .failed: .red
        }
    }

    private var recordingTint: Color {
        switch store.recordingState {
        case .stopped: .secondary
        case .starting: .orange
        case .recording: .red
        case .failed: .red
        }
    }

    private var transportSymbol: String {
        switch store.streamTransport {
        case .preview: "play.circle"
        case .endpointValidation: "network"
        case .rtmpPublish: "antenna.radiowaves.left.and.right"
        }
    }

    private func metric(_ title: String, _ value: String, _ unit: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(unit.isEmpty ? value : "\(value) \(unit)"))
    }
}
