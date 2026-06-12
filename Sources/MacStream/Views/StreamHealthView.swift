import SwiftUI
import MacStreamCore

struct StreamHealthView: View {
    var store: StudioStore

    var body: some View {
        VStack(alignment: .leading, spacing: StudioMetrics.md) {
            // Source guard: Label(healthTitle, systemImage: transportSymbol)
            StudioPanelHeader(
                title: healthTitle,
                systemImage: transportSymbol,
                subtitle: store.streamStatusDetail,
                tint: statusTint
            ) {
                VStack(alignment: .trailing, spacing: StudioMetrics.xs) {
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
                    .foregroundStyle(store.effectivePerformanceMode == .efficiency ? StudioPalette.warning : .secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: StudioMetrics.lg, verticalSpacing: StudioMetrics.sm) {
                metric("Bitrate", "\(store.health.bitrateKbps)", "kbps")
                metric("Frames", "\(store.health.droppedFrames)", "dropped")
                metric("Capture", "\(store.health.captureFPS)", "fps")
                metric("Latency", "\(store.health.roundTripMs)", "ms")
                metric("Thermal", store.systemPressure.thermalPressure.title, "")
                metric("Memory", "\(store.systemPressure.memoryUsedMB)", "MB")
            }

            resourceBreakdown

            if let efficiencyPressureDetail = store.systemPressure.efficiencyPressureDetail {
                Label(efficiencyPressureDetail, systemImage: "speedometer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(StudioPalette.warning)
            }
        }
        .studioCard()
    }

    private var resourceBreakdown: some View {
        let resources = store.resourceUsageSnapshot

        return VStack(alignment: .leading, spacing: StudioMetrics.xs) {
            Text("Resource budget")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            resourceRow(
                "Process",
                "\(resources.processMemoryMB) MB",
                "\(resources.memoryUsagePercent)% RAM • \(resources.thermalPressure.title) thermal"
            )
            resourceRow(
                "Stream",
                "\(resources.streamActualFPS)/\(resources.streamTargetFPS) fps",
                "\(resources.streamDroppedFrames) drops • \(resources.streamBitrateKbps) kbps • queue \(resources.streamQueueDepth)"
            )
            resourceRow(
                "Preview",
                "\(resources.previewTargetFPS) fps",
                "\(resources.previewMaxDisplayWidth) px max • queue \(resources.previewQueueDepth)"
            )
            resourceRow(
                "Director",
                "\(resources.directorSampleIntervalMilliseconds) ms",
                "recommendation sample interval"
            )
            resourceRow(
                "Signals",
                "\(resources.screenSignalFPS) fps",
                "screen motion sampler"
            )
        }
        .padding(StudioMetrics.sm)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: StudioMetrics.controlRadius, style: .continuous))
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
        case .connecting: StudioPalette.warning
        case .live: StudioPalette.success
        case .degraded, .failed: StudioPalette.live
        }
    }

    private var recordingTint: Color {
        switch store.recordingState {
        case .stopped: .secondary
        case .starting: StudioPalette.warning
        case .recording: StudioPalette.recording
        case .failed: StudioPalette.live
        }
    }

    private var transportSymbol: String {
        switch store.streamTransport {
        case .preview: "play.circle"
        case .endpointValidation: "network"
        case .rtmpPublish: "antenna.radiowaves.left.and.right"
        }
    }

    private func resourceRow(_ title: String, _ value: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: StudioMetrics.sm) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(value), \(detail)"))
    }

    private func metric(_ title: String, _ value: String, _ unit: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: StudioMetrics.xs) {
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
