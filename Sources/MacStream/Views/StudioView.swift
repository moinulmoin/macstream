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
            PreviewCanvasView(
                scene: store.selectedScene,
                previewConfiguration: previewConfiguration,
                cameraEnhancements: store.preferences.cameraEnhancements,
                layoutSettings: store.preferences.layoutSettings,
                cameraDeviceID: store.selectedCameraDeviceID,
                isCameraEnabled: store.isSourceEnabled(.camera),
                isCameraCaptureReady: store.captureReport.hasGrantedPermission(for: .camera),
                isScreenEnabled: store.isSourceEnabled(.screen),
                screenLevel: store.sourceLevel(.screen),
                isScreenCaptureReady: store.captureReport.isScreenCapturePermissionGranted,
                screenCaptureTarget: store.selectedScreenCaptureTarget,
                mediaPreviewFrameSource: store.mediaPreviewFrameSource,
                shouldUseMediaOutputPreview: store.shouldUseMediaOutputPreview,
                onCameraPreviewFailure: { detail in
                    store.notePreviewSetupIssue(detail)
                },
                onLayoutSettingsPreview: { layoutSettings in
                    store.previewLayoutSettings(layoutSettings)
                },
                onLayoutSettingsChange: { layoutSettings in
                    store.commitLayoutSettings(layoutSettings)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            StudioControlPanelView(store: store)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewConfiguration: PreviewCaptureConfiguration {
        store.currentPreviewCaptureConfiguration
    }
}

private struct InspectorView: View {
    var store: StudioStore
    @SceneStorage("MacStream.InspectorView.selectedTab") private var selectedTabRaw = InspectorTab.live.rawValue

    var body: some View {
        VStack(spacing: 14) {
            InspectorTabBarView(selection: selectedTabBinding)

            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        Color.clear
                            .frame(height: 0)
                            .id(InspectorPanelID.detailTop)

                        rightSidebarPanels
                    }
                    .padding(.bottom, 18)
                }
                .onChange(of: store.shouldShowSetupChecklist) { _, _ in
                    if store.shouldShowSetupChecklist {
                        selectedTabRaw = InspectorTab.live.rawValue
                    }
                    withAnimation(.snappy(duration: 0.18)) {
                        scrollProxy.scrollTo(InspectorPanelID.detailTop, anchor: .top)
                    }
                }
                .onChange(of: selectedTabRaw) { _, _ in
                    withAnimation(.snappy(duration: 0.18)) {
                        scrollProxy.scrollTo(InspectorPanelID.detailTop, anchor: .top)
                    }
                }
            }
        }
        .padding(18)
    }

    @ViewBuilder
    private var rightSidebarPanels: some View {
        switch selectedTab {
        case .live:
            livePanels
        case .layout:
            LayoutComposerView(store: store)
        case .sources:
            SourceRackView(store: store)
            CapturePreflightView(store: store)
        case .health:
            LiveStatusPanelView(store: store)
            StreamHealthView(store: store)
            DestinationView(store: store)
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

    @ViewBuilder
    private var livePanels: some View {
        if store.shouldShowSetupChecklist {
            setupDetailPanels
        } else {
            LiveStatusPanelView(store: store)
        }
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
            LayoutComposerView(store: store)
        }
    }

    private var selectedTab: InspectorTab {
        InspectorTab(rawValue: selectedTabRaw) ?? .live
    }

    private var selectedTabBinding: Binding<InspectorTab> {
        Binding(
            get: { selectedTab },
            set: { selectedTabRaw = $0.rawValue }
        )
    }
}

private enum InspectorPanelID: Hashable {
    case detailTop
}

private enum InspectorTab: String, CaseIterable, Identifiable {
    case live
    case layout
    case sources
    case health

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: "Live"
        case .layout: "Layout"
        case .sources: "Sources"
        case .health: "Health"
        }
    }

    var symbolName: String {
        switch self {
        case .live: "dot.radiowaves.left.and.right"
        case .layout: "rectangle.split.2x1"
        case .sources: "slider.horizontal.3"
        case .health: "waveform.path.ecg"
        }
    }
}

private struct InspectorTabBarView: View {
    @Binding var selection: InspectorTab

    var body: some View {
        Picker("Sidebar", selection: $selection) {
            ForEach(InspectorTab.allCases) { tab in
                Label(tab.title, systemImage: tab.symbolName)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel(Text("Sidebar section"))
    }
}

private struct LiveStatusPanelView: View {
    var store: StudioStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StudioPanelHeader(
                title: "Live",
                systemImage: "dot.radiowaves.left.and.right",
                subtitle: statusDetail
            ) {
                StudioBadge(title: statusTitle, systemImage: statusSymbol, tint: statusTint, isFilled: statusIsFilled)
            }

            HStack(spacing: 8) {
                statusTile("Stream", value: streamTitle, symbol: streamSymbol, tint: streamTint)
                statusTile("Record", value: recordingTitle, symbol: recordingSymbol, tint: recordingTint)
            }

            StudioMicrophoneLevelMeterView(
                store: store,
                title: "Mic",
                showsStatusDetail: true
            )

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    outputBadge
                    previewBadge
                }
                VStack(alignment: .leading, spacing: 8) {
                    outputBadge
                    previewBadge
                }
            }
        }
        .studioCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Live status"))
        .accessibilityValue(Text("\(streamTitle). \(recordingTitle). \(outputTitle). \(previewTitle)."))
    }

    private func statusTile(_ title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var statusDetail: String {
        if store.isLive || store.isStreamConnecting || hasStreamFailure {
            return store.streamStatusDetail
        }

        if store.recordingState != .stopped {
            return store.recordingStatusDetail
        }

        let layoutSettings = store.preferences.layoutSettings
        if store.selectedScene.kind == .screenAndFace,
           layoutSettings.presenterComposition.mode == .presenterOverlay {
            return "\(store.selectedScene.title) with Cutout · \(layoutSettings.presenterComposition.placement.title)."
        }

        return "\(store.selectedScene.title) with \(layoutSettings.preset.shortTitle) layout."
    }

    private var statusTitle: String {
        if store.isLive { return "Live" }
        if store.isStreamConnecting { return "Starting" }
        if store.recordingState == .recording { return "Rec" }
        if store.isRecordingStarting || store.isRecordingStopping { return "Working" }
        if hasStreamFailure || store.recordingState.isFailed { return "Fix" }
        return "Ready"
    }

    private var statusSymbol: String {
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

    private var streamTitle: String {
        if store.isLive { return store.streamTransport == .preview ? "Preview Live" : "Live" }
        if store.isStreamConnecting { return "Starting" }
        if hasStreamFailure { return "Failed" }
        return store.streamTransport == .preview ? "Preview Ready" : "Ready"
    }

    private var streamSymbol: String {
        if store.isLive { return "record.circle.fill" }
        if store.isStreamConnecting { return "hourglass.circle.fill" }
        if hasStreamFailure { return "exclamationmark.triangle.fill" }
        return switch store.streamTransport {
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

    private var recordingTitle: String {
        if store.recordingState == .recording { return "Recording" }
        if store.isRecordingStarting { return "Starting" }
        if store.isRecordingStopping { return "Stopping" }
        if store.recordingState.isFailed { return "Failed" }
        return "Ready"
    }

    private var recordingSymbol: String {
        if store.recordingState == .recording { return "record.circle.fill" }
        if store.isRecordingStarting || store.isRecordingStopping { return "hourglass.circle.fill" }
        if store.recordingState.isFailed { return "exclamationmark.triangle.fill" }
        return "record.circle"
    }

    private var recordingTint: Color {
        switch store.recordingState {
        case .stopped: .secondary
        case .starting: StudioPalette.warning
        case .recording: StudioPalette.recording
        case .failed: StudioPalette.live
        }
    }

    private var outputBadge: some View {
        StudioBadge(title: outputTitle, systemImage: outputSymbol, tint: .secondary)
    }

    private var previewBadge: some View {
        StudioBadge(title: previewTitle, systemImage: "eye", tint: .secondary)
    }

    private var outputTitle: String {
        "\(store.currentOutputResolutionWidth)w · \(store.currentOutputFrameRate) FPS"
    }

    private var outputSymbol: String {
        store.canEditOutputCaptureSettings ? "rectangle.dashed" : "lock.fill"
    }

    private var previewTitle: String {
        "Preview \(store.preferences.previewRenderQuality.title)"
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
