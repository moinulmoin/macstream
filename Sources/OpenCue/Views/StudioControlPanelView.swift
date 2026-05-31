import SwiftUI
import OpenCueCore

struct StudioControlPanelView: View {
    @Bindable var store: StudioStore
    @AppStorage("performanceMode") private var performanceModeRaw = StudioPerformanceMode.balanced.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                horizontalControls
                wrappedControls
            }

            if let primaryActionBlockerDetail {
                Label(primaryActionBlockerDetail, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var horizontalControls: some View {
        HStack(spacing: 10) {
            sceneControls
                .frame(width: 228)

            directorControls
                .frame(width: 140)

            outputControls
                .frame(width: 220)

            Spacer(minLength: 0)

            performanceControls
                .frame(width: 104)
        }
    }

    private var wrappedControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                sceneControls
                directorControls
            }

            HStack(spacing: 10) {
                outputControls
                performanceControls
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
        .help("Choose how OpenCue handles director cues")
    }

    private var outputControls: some View {
        HStack(spacing: 8) {
            Button {
                if store.canStopStream {
                    store.stopStream()
                } else {
                    store.startStream()
                }
            } label: {
                Label(streamActionTitle, systemImage: streamActionSymbol)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(streamActionTint)
            .disabled(!store.canStartStream && !store.canStopStream)
            .help(streamActionHelp)

            Button {
                if store.canStopRecording {
                    store.stopRecording()
                } else {
                    store.startRecording()
                }
            } label: {
                Label(recordingActionTitle, systemImage: recordingActionSymbol)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!store.canStartRecording && !store.canStopRecording)
            .help(recordingActionHelp)
        }
        .controlSize(.small)
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
                .minimumScaleFactor(0.76)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Adjust capture cost for this session")
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
