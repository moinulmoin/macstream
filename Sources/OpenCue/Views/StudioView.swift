import SwiftUI
import OpenCueCore

struct StudioView: View {
    @Bindable var store: StudioStore
    @SceneStorage("OpenCue.StudioView.isInspectorCollapsed") private var isInspectorCollapsed = false

    var body: some View {
        HStack(spacing: 0) {
            PreviewColumnView(store: store)
                .padding(20)

            Divider()

            if isInspectorCollapsed {
                InspectorRailView(store: store)
                    .frame(width: 38)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                InspectorView(store: store)
                    .frame(width: 340)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
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
    @Bindable var store: StudioStore

    var body: some View {
        VStack(spacing: 16) {
            PreviewCanvasView(
                scene: store.selectedScene,
                signals: store.latestSignals,
                previewConfiguration: store.effectivePerformanceMode.previewCaptureConfiguration,
                cameraEnhancements: store.preferences.cameraEnhancements,
                isCameraEnabled: store.isSourceEnabled(.camera),
                isCameraCaptureReady: store.captureReport.hasGrantedPermission(for: .camera),
                isScreenEnabled: store.isSourceEnabled(.screen),
                screenLevel: store.sourceLevel(.screen),
                isScreenCaptureReady: store.captureReport.isScreenCapturePermissionGranted,
                screenCaptureTarget: store.selectedScreenCaptureTarget
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)

            StudioControlPanelView(store: store)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct InspectorView: View {
    @Bindable var store: StudioStore

    var body: some View {
        VStack(spacing: 14) {
            InspectorHeaderView(isSetupFocused: store.shouldShowSetupChecklist)

            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
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
    var isSetupFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Label(isSetupFocused ? "Setup" : "Details", systemImage: "sidebar.right")
                .font(.headline)

            Spacer()

            Text(isSetupFocused ? "Setup" : "Ready")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusTint.opacity(0.14), in: Capsule())
                .foregroundStyle(statusTint)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusTint: Color {
        isSetupFocused ? .orange : .green
    }
}

private struct InspectorRailView: View {
    @Bindable var store: StudioStore

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: statusSymbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(statusTint)
                .help(statusHelp)

            Spacer()
        }
        .padding(.vertical, 16)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
    }

    private var statusSymbol: String {
        if store.isLive { return "record.circle.fill" }
        if store.isStreamConnecting || store.isRecordingStarting || store.isRecordingStopping {
            return "hourglass.circle.fill"
        }
        if store.recordingState == .recording { return "record.circle" }
        if store.shouldShowSetupChecklist { return "checklist" }
        return "checkmark.circle.fill"
    }

    private var statusTint: Color {
        if store.isLive || store.recordingState == .recording { return .red }
        if store.isStreamConnecting || store.isRecordingStarting || store.isRecordingStopping {
            return .orange
        }
        if store.shouldShowSetupChecklist { return .orange }
        return .green
    }

    private var statusHelp: String {
        if store.isLive { return "Preview or stream is active" }
        if store.isStreamConnecting { return "Starting preview or stream" }
        if store.recordingState == .recording { return "Recording" }
        if store.isRecordingStarting { return "Starting recording" }
        if store.isRecordingStopping { return "Stopping recording" }
        if store.shouldShowSetupChecklist { return "Setup needs attention" }
        return "Ready"
    }
}
