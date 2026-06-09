import SwiftUI
import MacStreamCore

struct StudioControlPanelView: View {
    @Bindable var store: StudioStore
    @AppStorage("performanceMode") private var performanceModeRaw = StudioPerformanceMode.balanced.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: StudioMetrics.md) {
            HStack(spacing: StudioMetrics.sm) {
                StudioGroupLabel(title: "Control Room", systemImage: "slider.horizontal.3")

                Spacer()

                if primaryActionBlockerDetail == nil {
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            ViewThatFits(in: .horizontal) {
                horizontalControls
                wrappedControls
            }

            if let primaryActionBlockerDetail {
                Label(primaryActionBlockerDetail, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(StudioMetrics.md)
                    .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: StudioMetrics.controlRadius, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard(padding: StudioMetrics.cardPadding, cornerRadius: StudioMetrics.cardRadius)
    }

    private var horizontalControls: some View {
        HStack(alignment: .top, spacing: StudioMetrics.lg) {
            controlGroup("Scenes", systemImage: "rectangle.stack") {
                sceneControls
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            controlDivider

            controlGroup("Director", systemImage: "sparkles") {
                directorControls
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            controlDivider

            outputControls
                .frame(maxWidth: .infinity, alignment: .leading)

            controlDivider

            controlGroup("Performance", systemImage: "speedometer") {
                performanceControls
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var controlDivider: some View {
        Divider()
            .frame(height: 46)
            .overlay(Color.white.opacity(0.06))
    }

    private var wrappedControls: some View {
        VStack(spacing: StudioMetrics.md) {
            HStack(alignment: .top, spacing: StudioMetrics.lg) {
                controlGroup("Scenes", systemImage: "rectangle.stack") {
                    sceneControls
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                controlGroup("Director", systemImage: "sparkles") {
                    directorControls
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .top, spacing: StudioMetrics.lg) {
                outputControls
                    .frame(maxWidth: .infinity, alignment: .leading)

                controlGroup("Performance", systemImage: "speedometer") {
                    performanceControls
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var sceneControls: some View {
        Picker("Scene", selection: sceneSelectionBinding) {
            ForEach(store.scenes) { scene in
                Label(sceneDeckTitle(for: scene), systemImage: scene.kind.symbolName)
                    .tag(scene.id)
                    .disabled(!store.canSelectScene(scene))
                    .help(store.sceneSelectionBlockedReason(for: scene) ?? scene.subtitle)
                    .accessibilityLabel(Text(scene.title))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .help(store.selectedScene.subtitle)
        .accessibilityLabel(Text("Scene deck"))
        .accessibilityValue(Text(store.selectedScene.title))
        .accessibilityHint(Text("Choose the scene shown in the preview and output."))
    }

    private var directorControls: some View {
        Picker("Director Mode", selection: $store.directorMode) {
            ForEach(DirectorMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .help("Choose how MacStream handles director cues")
        .accessibilityLabel(Text("Director mode"))
        .accessibilityValue(Text(store.directorMode.title))
        .accessibilityHint(Text("Paused disables cues, Suggest asks before switching, Auto can switch after the countdown."))
    }

    private var outputControls: some View {
        VStack(alignment: .leading, spacing: StudioMetrics.sm) {
            StudioGroupLabel(title: "Output", systemImage: "dot.radiowaves.left.and.right")
                .padding(.bottom, StudioMetrics.xs)

            HStack(spacing: StudioMetrics.sm) {
                Button {
                    if store.canStopStream {
                        store.stopStream()
                    } else {
                        store.startStream()
                    }
                } label: {
                    Label(streamActionTitle, systemImage: streamActionSymbol)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StudioPrimaryButtonStyle(tint: streamActionTint))
                .disabled(!store.canStartStream && !store.canStopStream)
                .help(streamActionHelp)
                .accessibilityLabel(Text(streamActionTitle))
                .accessibilityValue(Text(store.streamStatusDetail))
                .accessibilityHint(Text(streamActionHelp))

                Button {
                    if store.canStopRecording {
                        store.stopRecording()
                    } else {
                        store.startRecording()
                    }
                } label: {
                    Label(recordingActionTitle, systemImage: recordingActionSymbol)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StudioSecondaryButtonStyle())
                .disabled(!store.canStartRecording && !store.canStopRecording)
                .help(recordingActionHelp)
                .accessibilityLabel(Text(recordingActionTitle))
                .accessibilityValue(Text(store.recordingStatusDetail))
                .accessibilityHint(Text(recordingActionHelp))
            }
        }
    }

    private var performanceControls: some View {
        Menu {
            Picker("Performance", selection: performanceModeBinding) {
                ForEach(StudioPerformanceMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
        } label: {
            Label(performanceMenuTitle, systemImage: "speedometer")
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .help("Adjust capture cost for this session")
        .accessibilityLabel(Text("Performance mode"))
        .accessibilityValue(Text(performanceMenuTitle))
        .accessibilityHint(Text("Adjust preview capture cost and director sample rate."))
    }

    private func controlGroup<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: StudioMetrics.sm) {
            StudioGroupLabel(title: title, systemImage: systemImage)
                .padding(.bottom, StudioMetrics.xs)
            content()
        }
    }

    private var statusLine: String {
        if store.isLive || store.isStreamConnecting || isStreamFailed {
            return store.streamStatusDetail
        }

        if store.recordingState != .stopped {
            return store.recordingStatusDetail
        }

        return "Ready to preview, record, or stream"
    }

    private var sceneSelectionBinding: Binding<StudioScene.ID> {
        Binding(
            get: { store.selectedSceneID },
            set: { newSceneID in
                guard let scene = store.scenes.first(where: { $0.id == newSceneID }) else { return }
                store.selectScene(scene)
            }
        )
    }

    private func sceneDeckTitle(for scene: StudioScene) -> String {
        switch scene.kind {
        case .face: "Face"
        case .screenAndFace: "S+F"
        case .screenOnly: "Screen"
        case .brb: "BRB"
        }
    }

    private var performanceMenuTitle: String {
        if store.preferences.performanceMode == .adaptive {
            return store.effectivePerformanceMode.title
        }

        return store.preferences.performanceMode.title
    }

    private var performanceModeBinding: Binding<String> {
        Binding(
            get: { store.preferences.performanceMode.rawValue },
            set: { newValue in
                guard let newMode = StudioPerformanceMode(rawValue: newValue) else { return }
                performanceModeRaw = newValue
                var preferences = store.preferences
                preferences.performanceMode = newMode
                store.updatePreferences(preferences)
            }
        )
    }

    private var isStreamFailed: Bool {
        if case .failed = store.streamState { return true }
        return false
    }

    private var streamActionTitle: String {
        if store.isLive {
            if store.streamTransport == .preview { return "Stop Preview" }
            if store.streamTransport == .endpointValidation { return "Stop Check" }
            return "Stop Stream"
        }
        if store.isStreamConnecting {
            if store.streamTransport == .preview { return "Cancel Preview" }
            if store.streamTransport == .endpointValidation { return "Cancel Check" }
            return "Cancel Stream"
        }
        if !store.destination.isPreviewSession, store.streamTransport == .endpointValidation {
            return "Check Endpoint"
        }
        return store.destination.isPreviewSession ? "Start Preview" : "Go Live"
    }

    private var streamActionSymbol: String {
        if store.isLive { return "stop.fill" }
        if store.isStreamConnecting { return "xmark.circle" }
        return store.destination.isPreviewSession ? "play.rectangle" : "dot.radiowaves.left.and.right"
    }

    private var streamActionTint: Color {
        if store.isLive { return .red }
        if store.isStreamConnecting { return .orange }
        if isStreamFailed { return .red }
        if !store.canStartStream && !store.canStopStream { return .secondary }
        return .accentColor
    }

    private var streamActionHelp: String {
        if store.canStopStream { return "Stop or cancel the current stream session" }
        if let startBlockedReason = store.streamStartBlockedReason {
            return startBlockedReason
        }
        if !store.canStartStream { return store.streamStatusDetail }
        if !store.destination.isPreviewSession, store.streamTransport == .endpointValidation {
            return "Validate RTMP endpoint reachability"
        }
        return store.destination.isPreviewSession ? "Start local preview" : "Start stream"
    }

    private var recordingActionTitle: String {
        if store.isRecordingStopping { return "Stopping" }
        if store.recordingState == .recording { return "Stop Rec" }
        if store.isRecordingStarting { return "Cancel Rec" }
        return "Record"
    }

    private var recordingActionSymbol: String {
        if store.recordingState == .recording { return "stop.circle" }
        if store.isRecordingStarting { return "xmark.circle" }
        if store.isRecordingStopping { return "hourglass.circle" }
        return "record.circle"
    }

    private var recordingActionHelp: String {
        if store.canStopRecording { return "Stop or cancel local recording" }
        if let startBlockedReason = store.recordingStartBlockedReason {
            return startBlockedReason
        }
        if !store.canStartRecording { return store.recordingStatusDetail }
        return "Start local recording"
    }

    private var primaryActionBlockerDetail: String? {
        if !store.canStartStream, !store.canStopStream {
            if let startBlockedReason = store.streamStartBlockedReason {
                return startBlockedReason
            }
            if let validationError = store.destination.validationError {
                return validationError
            }
        }

        if !store.canStartRecording, !store.canStopRecording,
           let startBlockedReason = store.recordingStartBlockedReason {
            return "Recording: \(startBlockedReason)"
        }

        return nil
    }
}
