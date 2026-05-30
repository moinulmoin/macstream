import SwiftUI
import OpenCueCore

struct StudioControlPanelView: View {
    @Bindable var store: StudioStore
    var onCollapse: (() -> Void)? = nil
    @AppStorage("performanceMode") private var performanceModeRaw = StudioPerformanceMode.balanced.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Studio Control", systemImage: "dial.high")
                    .font(.headline)
                Spacer()
                if let onCollapse {
                    Button {
                        onCollapse()
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .buttonStyle(.borderless)
                    .help("Hide controls")
                }
                Text(liveStateTitle)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(liveStateTint.opacity(0.14), in: Capsule())
                    .foregroundStyle(liveStateTint)
            }

            Picker("Director Mode", selection: $store.directorMode) {
                ForEach(DirectorMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Choose how OpenCue handles director cues")

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Performance", systemImage: "speedometer")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(performanceStatusTitle)
                        .font(.caption)
                        .foregroundStyle(performanceStatusTint)
                }

                Picker("Performance", selection: performanceModeBinding) {
                    ForEach(StudioPerformanceMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Adjust capture cost for this session")
            }

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
                        .minimumScaleFactor(0.82)
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
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!store.canStartRecording && !store.canStopRecording)
                .help(recordingActionHelp)
            }
            .controlSize(.large)

            if let primaryActionBlockerDetail {
                Label(primaryActionBlockerDetail, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var liveStateTitle: String {
        if store.isLive { return "Live" }
        if store.isStreamConnecting { return "Starting" }
        if isStreamFailed { return "Failed" }
        if store.recordingState == .recording { return "Recording" }
        if store.isRecordingStarting { return "Recording" }
        if store.isRecordingStopping { return "Stopping" }
        if store.shouldShowSetupChecklist { return "Setup" }
        return "Ready"
    }

    private var liveStateTint: Color {
        if store.isLive { return .red }
        if store.isStreamConnecting { return .orange }
        if isStreamFailed { return .red }
        if store.recordingState == .recording { return .red }
        if store.isRecordingStarting || store.isRecordingStopping { return .orange }
        if store.shouldShowSetupChecklist { return .orange }
        return .green
    }

    private var isStreamFailed: Bool {
        if case .failed = store.streamState { return true }
        return false
    }

    private var performanceStatusTitle: String {
        if store.preferences.performanceMode == .adaptive {
            return "Using \(store.effectivePerformanceMode.title)"
        }

        return store.preferences.performanceMode.title
    }

    private var performanceStatusTint: Color {
        if store.effectivePerformanceMode == .efficiency { return .orange }
        if store.preferences.performanceMode == .responsive { return .blue }
        return .secondary
    }

    private var performanceModeBinding: Binding<String> {
        Binding(
            get: { performanceModeRaw },
            set: { newValue in
                performanceModeRaw = newValue
                guard let mode = StudioPerformanceMode(rawValue: newValue) else { return }

                var preferences = store.preferences
                preferences.performanceMode = mode
                store.updatePreferences(preferences)
            }
        )
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
        if store.isRecordingStopping { return "Stopping Recording" }
        if store.recordingState == .recording { return "Stop Recording" }
        if store.isRecordingStarting { return "Cancel Recording" }
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
