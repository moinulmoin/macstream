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
                InspectorRailView(store: store, isInspectorCollapsed: $isInspectorCollapsed)
                    .frame(width: 54)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                InspectorView(store: store, isInspectorCollapsed: $isInspectorCollapsed)
                    .frame(width: 340)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .navigationTitle(store.selectedScene.title)
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
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)

            if !store.shouldShowSetupChecklist {
                DirectorPanelView(store: store)
            }
        }
    }
}

private struct InspectorView: View {
    @Bindable var store: StudioStore
    @Binding var isInspectorCollapsed: Bool

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    StudioControlPanelView(store: store) {
                        isInspectorCollapsed = true
                    }
                    .id(InspectorPanelID.studioControl)

                    if store.shouldShowSetupChecklist {
                        setupDetailPanels
                    } else {
                        operatingPanels
                    }
                }
                .padding(18)
            }
            .onChange(of: store.shouldShowSetupChecklist) { _, shouldShowSetupChecklist in
                guard !shouldShowSetupChecklist else { return }
                withAnimation(.snappy(duration: 0.18)) {
                    scrollProxy.scrollTo(InspectorPanelID.studioControl, anchor: .top)
                }
            }
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
            EmptyView()
        }
    }

    @ViewBuilder
    private var operatingPanels: some View {
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
    case studioControl
}

private struct InspectorRailView: View {
    @Bindable var store: StudioStore
    @Binding var isInspectorCollapsed: Bool

    var body: some View {
        VStack(spacing: 14) {
            Button {
                isInspectorCollapsed = false
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("Show controls")

            Divider()
                .frame(width: 28)

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
