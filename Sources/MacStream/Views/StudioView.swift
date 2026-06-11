import SwiftUI
import MacStreamCore

struct StudioView: View {
    var store: StudioStore
    @SceneStorage("MacStream.StudioView.isInspectorCollapsed") private var isInspectorCollapsed = false

    var body: some View {
        HStack(spacing: 0) {
            PreviewColumnView(store: store)
                .padding(.horizontal, 24)
                .padding(.vertical, 22)

            Divider()
                .opacity(0.55)

            if isInspectorCollapsed {
                InspectorRailView(store: store)
                    .frame(width: 52)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                InspectorView(store: store)
                    .frame(width: 372)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.07),
                    StudioPalette.accent.opacity(0.05),
                    Color.black.opacity(0.02)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isInspectorCollapsed.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help(isInspectorCollapsed ? "Show sidebar" : "Hide sidebar")
            }
        }
        .animation(.snappy(duration: 0.18), value: isInspectorCollapsed)
    }
}

private struct PreviewColumnView: View {
    var store: StudioStore

    var body: some View {
        VStack(spacing: 14) {
            SessionStatusStripView(store: store)

            ZStack(alignment: .topTrailing) {
                PreviewCanvasView(
                    scene: store.selectedScene,
                    signals: store.latestSignals,
                    previewConfiguration: previewConfiguration,
                    cameraEnhancements: store.preferences.cameraEnhancements,
                    cameraDeviceID: store.selectedCameraDeviceID,
                    isCameraEnabled: store.isSourceEnabled(.camera),
                    isCameraCaptureReady: store.captureReport.hasGrantedPermission(for: .camera),
                    isScreenEnabled: store.isSourceEnabled(.screen),
                    screenLevel: store.sourceLevel(.screen),
                    isScreenCaptureReady: store.captureReport.isScreenCapturePermissionGranted,
                    screenCaptureTarget: store.selectedScreenCaptureTarget
                )

                PreviewOutputHUD(store: store)
                    .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            StudioControlPanelView(store: store)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewConfiguration: PreviewCaptureConfiguration {
        guard store.streamTransport == .rtmpPublish,
              store.isStreamConnecting || store.streamState.isLive
        else {
            return store.effectivePerformanceMode.previewCaptureConfiguration
        }

        return StudioPerformanceMode.efficiency.previewCaptureConfiguration
    }
}

private struct InspectorView: View {
    var store: StudioStore

    var body: some View {
        VStack(spacing: 14) {
            InspectorHeaderView(store: store)

            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        Color.clear
                            .frame(height: 0)
                            .id(InspectorPanelID.detailTop)

                        if store.shouldShowSetupChecklist {
                            setupDetailPanels
                        } else {
                            operatingPanels
                        }
                    }
                    .padding(.bottom, 18)
                }
                .onChange(of: store.shouldShowSetupChecklist) { _, _ in
                    withAnimation(.snappy(duration: 0.18)) {
                        scrollProxy.scrollTo(InspectorPanelID.detailTop, anchor: .top)
                    }
                }
            }
        }
        .padding(18)
    }

    @ViewBuilder
    private var setupDetailPanels: some View {
        SetupChecklistView(store: store)

        switch store.nextSetupChecklistItem?.id {
        case .capture:
            CapturePreflightView(store: store)
        case .destination:
            DestinationView(store: store)
        case .sources:
            SourceRackView(store: store)
        case .scene, nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var operatingPanels: some View {
        DirectorPanelView(store: store)
        StreamHealthView(store: store)
        DestinationView(store: store)
        CapturePreflightView(store: store)
        SourceRackView(store: store)
        EventLogView(
            events: store.events,
            clipMarkers: store.clipMarkers,
            latestClipExportURL: store.latestClipExportURL,
            latestSessionReportURL: store.latestSessionReportURL
        ) {
            store.exportClipMarkers()
        } exportReport: {
            store.exportSessionReport()
        }
    }
}

private enum InspectorPanelID: Hashable {
    case detailTop
}

private struct InspectorHeaderView: View {
    var store: StudioStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(headerTitle, systemImage: headerSymbol)
                        .font(.headline)

                    Text(headerDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                StudioBadge(title: statusTitle, systemImage: statusSymbol, tint: statusTint, isFilled: statusIsFilled)
            }

            HStack(spacing: 8) {
                StudioBadge(title: store.streamState.title, systemImage: streamSymbol, tint: streamTint)
                StudioBadge(title: store.recordingState.title, systemImage: "record.circle", tint: recordingTint)
            }
        }
        .studioCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(headerTitle))
        .accessibilityValue(Text("\(store.streamState.title). \(store.recordingState.title). \(headerDetail)"))
    }

    private var headerTitle: String {
        if store.shouldShowSetupChecklist { return "Preflight" }
        if store.isLive { return "On Air" }
        if store.recordingState == .recording { return "Recording" }
        if hasStreamFailure || store.recordingState.isFailed { return "Needs Attention" }
        return "Director Ready"
    }

    private var headerDetail: String {
        if store.shouldShowSetupChecklist {
            if let nextItem = store.nextSetupChecklistItem {
                return "Next: \(nextItem.title). \(nextItem.detail)"
            }

            return "\(store.completedSetupItemCount)/\(max(store.totalSetupItemCount, 1)) setup checks are ready."
        }

        if store.isLive || store.isStreamConnecting || hasStreamFailure {
            return store.streamStatusDetail
        }

        if store.recordingState != .stopped {
            return store.recordingStatusDetail
        }

        return "AI director is watching motion, speech, app focus, and idle time."
    }

    private var headerSymbol: String {
        if store.shouldShowSetupChecklist { return "checklist.checked" }
        if store.isLive { return "dot.radiowaves.left.and.right" }
        if store.recordingState == .recording { return "record.circle" }
        if hasStreamFailure || store.recordingState.isFailed { return "exclamationmark.triangle.fill" }
        return "sparkles.tv"
    }

    private var statusTitle: String {
        if store.shouldShowSetupChecklist {
            return "\(store.completedSetupItemCount)/\(max(store.totalSetupItemCount, 1)) ready"
        }
        if store.isLive { return "Live" }
        if store.isStreamConnecting { return "Starting" }
        if store.recordingState == .recording { return "Rec" }
        if store.isRecordingStarting || store.isRecordingStopping { return "Working" }
        if hasStreamFailure || store.recordingState.isFailed { return "Fix" }
        return "Ready"
    }

    private var statusSymbol: String {
        if store.shouldShowSetupChecklist { return "arrow.right.circle.fill" }
        if store.isLive { return "record.circle.fill" }
        if store.isStreamConnecting || store.isRecordingStarting || store.isRecordingStopping { return "hourglass.circle.fill" }
        if store.recordingState == .recording { return "record.circle.fill" }
        if hasStreamFailure || store.recordingState.isFailed { return "exclamationmark.triangle.fill" }
        return "checkmark.circle.fill"
    }

    private var statusTint: Color {
        if store.isLive { return StudioPalette.live }
        if store.recordingState == .recording { return StudioPalette.recording }
        if store.isStreamConnecting || store.isRecordingStarting || store.isRecordingStopping { return StudioPalette.warning }
        if store.shouldShowSetupChecklist { return StudioPalette.warning }
        if hasStreamFailure || store.recordingState.isFailed { return StudioPalette.live }
        return StudioPalette.success
    }

    private var statusIsFilled: Bool {
        store.isLive || store.recordingState == .recording || hasStreamFailure || store.recordingState.isFailed
    }

    private var hasStreamFailure: Bool {
        if case .failed = store.streamState { return true }
        return false
    }

    private var streamSymbol: String {
        switch store.streamTransport {
        case .preview: "play.circle"
        case .endpointValidation: "network"
        case .rtmpPublish: "antenna.radiowaves.left.and.right"
        }
    }

    private var streamTint: Color {
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
}

private struct SessionStatusStripView: View {
    var store: StudioStore

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("MacStream Studio")
                    .font(.title3.weight(.semibold))

                Text("\(store.selectedScene.title) · \(store.selectedScene.subtitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            ViewThatFits(in: .horizontal) {
                badgeRow
                compactBadgeRow
            }
        }
        .studioCard(padding: 12, cornerRadius: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Studio session status"))
        .accessibilityValue(Text(sessionAccessibilityValue))
    }

    private var badgeRow: some View {
        HStack(spacing: 8) {
            if store.isLive {
                StudioStatusDot(tint: StudioPalette.live, pulsing: true)
            }
            streamBadge
            recordingBadge
            StudioBadge(title: store.directorMode.title, systemImage: "sparkles", tint: directorTint)
            StudioBadge(title: store.effectivePerformanceMode.title, systemImage: "speedometer", tint: .secondary)
        }
    }

    private var compactBadgeRow: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 8) {
                if store.isLive {
                    StudioStatusDot(tint: StudioPalette.live, pulsing: true)
                }
                streamBadge
                recordingBadge
            }
            HStack(spacing: 8) {
                StudioBadge(title: store.directorMode.title, systemImage: "sparkles", tint: directorTint)
                StudioBadge(title: store.effectivePerformanceMode.title, systemImage: "speedometer", tint: .secondary)
            }
        }
    }

    private var streamBadge: some View {
        StudioBadge(
            title: streamTitle,
            systemImage: streamSymbol,
            tint: streamTint,
            isFilled: store.isLive
        )
    }

    private var recordingBadge: some View {
        StudioBadge(
            title: recordingTitle,
            systemImage: recordingSymbol,
            tint: recordingTint,
            isFilled: store.recordingState == .recording
        )
    }

    private var streamTitle: String {
        if store.isLive { return store.streamTransport == .preview ? "Preview Live" : "Live" }
        if store.isStreamConnecting { return "Starting" }
        if hasStreamFailure { return "Stream Failed" }
        return store.streamTransport == .preview ? "Preview Ready" : "Stream Ready"
    }

    private var streamSymbol: String {
        if store.isLive { return "record.circle.fill" }
        if store.isStreamConnecting { return "hourglass.circle.fill" }
        if hasStreamFailure { return "exclamationmark.triangle.fill" }
        return store.streamTransport == .preview ? "play.circle" : "antenna.radiowaves.left.and.right"
    }

    private var streamTint: Color {
        if store.isLive { return StudioPalette.live }
        if store.isStreamConnecting { return StudioPalette.warning }
        if hasStreamFailure { return StudioPalette.live }
        return .secondary
    }

    private var recordingTitle: String {
        if store.recordingState == .recording { return "Recording" }
        if store.isRecordingStarting { return "Starting Rec" }
        if store.isRecordingStopping { return "Stopping Rec" }
        if store.recordingState.isFailed { return "Rec Failed" }
        return "Record Ready"
    }

    private var recordingSymbol: String {
        if store.recordingState == .recording { return "record.circle.fill" }
        if store.isRecordingStarting || store.isRecordingStopping { return "hourglass.circle.fill" }
        if store.recordingState.isFailed { return "exclamationmark.triangle.fill" }
        return "record.circle"
    }

    private var recordingTint: Color {
        if store.recordingState == .recording { return StudioPalette.recording }
        if store.isRecordingStarting || store.isRecordingStopping { return StudioPalette.warning }
        if store.recordingState.isFailed { return StudioPalette.live }
        return .secondary
    }

    private var directorTint: Color {
        switch store.directorMode {
        case .paused: .secondary
        case .suggest: StudioPalette.info
        case .auto: StudioPalette.accent
        }
    }

    private var hasStreamFailure: Bool {
        if case .failed = store.streamState { return true }
        return false
    }

    private var sessionAccessibilityValue: String {
        "\(streamTitle). \(recordingTitle). Director \(store.directorMode.title). Performance \(store.effectivePerformanceMode.title)."
    }
}

private struct PreviewOutputHUD: View {
    var store: StudioStore

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if store.isLive || store.isStreamConnecting {
                StudioBadge(title: streamTitle, systemImage: streamSymbol, tint: streamTint, isFilled: store.isLive)
            }

            if store.recordingState == .recording || store.isRecordingStarting || store.isRecordingStopping {
                StudioBadge(title: recordingTitle, systemImage: recordingSymbol, tint: recordingTint, isFilled: store.recordingState == .recording)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Output overlay"))
    }

    private var streamTitle: String {
        if store.isLive { return store.streamTransport == .preview ? "Preview Live" : "Live" }
        if store.isStreamConnecting { return "Starting" }
        return store.streamState.title
    }

    private var streamSymbol: String {
        if store.isLive { return "record.circle.fill" }
        if store.isStreamConnecting { return "hourglass.circle.fill" }
        return "dot.radiowaves.left.and.right"
    }

    private var streamTint: Color {
        if store.isLive { return StudioPalette.live }
        if store.isStreamConnecting { return StudioPalette.warning }
        return .secondary
    }

    private var recordingTitle: String {
        if store.recordingState == .recording { return "Recording" }
        if store.isRecordingStarting { return "Starting Rec" }
        if store.isRecordingStopping { return "Stopping Rec" }
        return store.recordingState.title
    }

    private var recordingSymbol: String {
        if store.recordingState == .recording { return "record.circle.fill" }
        if store.isRecordingStarting || store.isRecordingStopping { return "hourglass.circle.fill" }
        return "record.circle"
    }

    private var recordingTint: Color {
        if store.recordingState == .recording { return StudioPalette.recording }
        if store.isRecordingStarting || store.isRecordingStopping { return StudioPalette.warning }
        return .secondary
    }
}

private struct InspectorRailView: View {
    var store: StudioStore

    var body: some View {
        VStack(spacing: 10) {
            if store.isLive || store.isStreamConnecting || hasStreamFailure {
                statusIcon(streamSymbol, tint: streamTint, help: store.streamStatusDetail)
            }

            if store.recordingState == .recording || store.isRecordingStarting || store.isRecordingStopping || store.recordingState.isFailed {
                statusIcon(recordingSymbol, tint: recordingTint, help: store.recordingStatusDetail)
            }

            if store.shouldShowSetupChecklist {
                statusIcon("checklist.checked", tint: StudioPalette.warning, help: "Preflight needs attention")
            }

            if showsReadyIcon {
                statusIcon("checkmark.circle.fill", tint: StudioPalette.success, help: "Ready")
            }

            Spacer()
        }
        .padding(.vertical, 16)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Studio status"))
        .accessibilityValue(Text(railAccessibilityValue))
    }

    private func statusIcon(_ symbol: String, tint: Color, help: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 32, height: 32)
            .background(tint.opacity(0.14), in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(tint.opacity(0.18), lineWidth: 1)
            }
            .help(help)
    }

    private var showsReadyIcon: Bool {
        !store.isLive
            && !store.isStreamConnecting
            && store.recordingState != .recording
            && !store.isRecordingStarting
            && !store.isRecordingStopping
            && !store.shouldShowSetupChecklist
            && !hasStreamFailure
            && !store.recordingState.isFailed
    }

    private var hasStreamFailure: Bool {
        if case .failed = store.streamState { return true }
        return false
    }

    private var streamSymbol: String {
        if store.isLive { return "record.circle.fill" }
        if store.isStreamConnecting { return "hourglass.circle.fill" }
        if hasStreamFailure { return "exclamationmark.triangle.fill" }
        return "dot.radiowaves.left.and.right"
    }

    private var streamTint: Color {
        if store.isLive { return StudioPalette.live }
        if store.isStreamConnecting { return StudioPalette.warning }
        if hasStreamFailure { return StudioPalette.live }
        return .secondary
    }

    private var recordingSymbol: String {
        if store.recordingState == .recording { return "record.circle.fill" }
        if store.isRecordingStarting || store.isRecordingStopping { return "hourglass.circle.fill" }
        if store.recordingState.isFailed { return "exclamationmark.triangle.fill" }
        return "record.circle"
    }

    private var recordingTint: Color {
        if store.recordingState == .recording { return StudioPalette.recording }
        if store.isRecordingStarting || store.isRecordingStopping { return StudioPalette.warning }
        if store.recordingState.isFailed { return StudioPalette.live }
        return .secondary
    }

    private var railAccessibilityValue: String {
        "Stream \(store.streamState.title). Recording \(store.recordingState.title)."
    }
}
