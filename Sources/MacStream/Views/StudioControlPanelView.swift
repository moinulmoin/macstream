import SwiftUI
import MacStreamCore

struct StudioControlPanelView: View {
    @Bindable var store: StudioStore
    @Environment(\.openSettings) private var openSettings
    @AppStorage(StudioSettingsTab.storageKey) private var selectedSettingsTabRaw = StudioSettingsTab.general.rawValue
    @AppStorage("performanceMode") private var performanceModeRaw = StudioPerformanceMode.balanced.rawValue
    @AppStorage("outputResolution") private var outputResolutionRaw = StreamOutputResolution.automatic.rawValue
    @AppStorage("outputFrameRate") private var outputFrameRateRaw = StreamFrameRate.automatic.rawValue
    @AppStorage("previewRenderQuality") private var previewRenderQualityRaw = StudioPreviewRenderQuality.automatic.rawValue

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

            if let guidance = store.operatorRecoveryGuidance {
                HStack(alignment: .center, spacing: StudioMetrics.md) {
                    Label {
                        Text("\(guidance.title): \(guidance.detail)")
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: recoverySymbol(for: guidance.action))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text(guidance.title))
                    .accessibilityValue(Text(guidance.detail))

                    Spacer(minLength: StudioMetrics.sm)

                    recoveryAction(for: guidance)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(recoveryTint(for: guidance.kind))
                .padding(StudioMetrics.md)
                .background(recoveryTint(for: guidance.kind).opacity(0.10), in: RoundedRectangle(cornerRadius: StudioMetrics.controlRadius, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard(padding: StudioMetrics.cardPadding, cornerRadius: StudioMetrics.cardRadius)
        .task {
            store.startSourceMonitoring()
        }
        .onDisappear {
            store.stopSourceMonitoring()
        }
    }

    private var horizontalControls: some View {
        HStack(alignment: .top, spacing: StudioMetrics.lg) {
            controlGroup("Scenes", systemImage: "rectangle.stack") {
                sceneControls
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            controlDivider

            outputControls
                .frame(maxWidth: .infinity, alignment: .leading)

            controlDivider

            controlGroup("Mic", systemImage: "waveform") {
                microphoneControls
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            controlDivider

            controlGroup("Output", systemImage: "speedometer") {
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

                outputControls
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .top, spacing: StudioMetrics.lg) {
                controlGroup("Mic", systemImage: "waveform") {
                    microphoneControls
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                controlGroup("Output", systemImage: "speedometer") {
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

    private var microphoneControls: some View {
        StudioMicrophoneLevelMeterView(
            store: store,
            title: "Input",
            showsStatusDetail: true
        )
    }

    private var performanceControls: some View {
        Menu {
            Picker("Performance", selection: performanceModeBinding) {
                ForEach(StudioPerformanceMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }

            if let lockedReason = store.outputCaptureSettingsLockedReason {
                Divider()

                Label(lockedReason, systemImage: "lock.fill")
                    .font(.caption)
            }

            Divider()

            Picker("Resolution", selection: outputResolutionBinding) {
                ForEach(StreamOutputResolution.allCases) { resolution in
                    Text(resolution.title).tag(resolution.rawValue)
                }
            }
            .disabled(!store.canEditOutputCaptureSettings)
            .help(store.outputCaptureSettingsLockedReason ?? "Choose the encoded stream and recording resolution.")

            Picker("FPS", selection: outputFrameRateBinding) {
                ForEach(StreamFrameRate.allCases) { frameRate in
                    Text(frameRate.title).tag(frameRate.rawValue)
                }
            }
            .disabled(!store.canEditOutputCaptureSettings)
            .help(store.outputCaptureSettingsLockedReason ?? "Choose the encoded stream and recording frame rate.")

            Picker("Preview", selection: previewRenderQualityBinding) {
                ForEach(StudioPreviewRenderQuality.allCases) { quality in
                    Text(quality.detailTitle).tag(quality.rawValue)
                }
            }
        } label: {
            Label(performanceMenuTitle, systemImage: performanceMenuSymbol)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .help("Adjust output quality and capture cost")
        .accessibilityLabel(Text("Output settings"))
        .accessibilityValue(Text(performanceMenuTitle))
        .accessibilityHint(Text("Adjust resolution, FPS, preview rendering, and performance mode."))
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
        case .face: "Cam"
        case .screenAndFace: "S+W"
        case .screenOnly: "Screen"
        case .brb: "BRB"
        }
    }

    private var performanceMenuTitle: String {
        "\(outputResolutionTitle) \(outputFrameRateTitle) · \(store.preferences.previewRenderQuality.title) preview"
    }

    private var performanceMenuSymbol: String {
        store.canEditOutputCaptureSettings ? "speedometer" : "lock"
    }

    private var outputResolutionTitle: String {
        if store.preferences.outputResolution == .automatic {
            return "\(Int((Double(store.currentOutputResolutionWidth) * 9.0 / 16.0).rounded()))p"
        }

        return store.preferences.outputResolution.title
    }

    private var outputFrameRateTitle: String {
        "\(store.currentOutputFrameRate) FPS"
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

    private var outputResolutionBinding: Binding<String> {
        Binding(
            get: { store.preferences.outputResolution.rawValue },
            set: { newValue in
                guard store.canEditOutputCaptureSettings else { return }
                guard let newResolution = StreamOutputResolution(rawValue: newValue) else { return }
                outputResolutionRaw = newValue
                var preferences = store.preferences
                preferences.outputResolution = newResolution
                store.updatePreferences(preferences)
            }
        )
    }

    private var outputFrameRateBinding: Binding<String> {
        Binding(
            get: { store.preferences.outputFrameRate.rawValue },
            set: { newValue in
                guard store.canEditOutputCaptureSettings else { return }
                guard let newFrameRate = StreamFrameRate(rawValue: newValue) else { return }
                outputFrameRateRaw = newValue
                var preferences = store.preferences
                preferences.outputFrameRate = newFrameRate
                store.updatePreferences(preferences)
            }
        )
    }

    private var previewRenderQualityBinding: Binding<String> {
        Binding(
            get: { store.preferences.previewRenderQuality.rawValue },
            set: { newValue in
                guard let newQuality = StudioPreviewRenderQuality(rawValue: newValue) else { return }
                previewRenderQualityRaw = newValue
                var preferences = store.preferences
                preferences.previewRenderQuality = newQuality
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
            if store.streamTransport == .endpointValidation { return "Stop Endpoint Check" }
            return "Stop Streaming"
        }
        if store.isStreamConnecting {
            if store.streamTransport == .preview { return "Cancel Preview" }
            if store.streamTransport == .endpointValidation { return "Cancel Endpoint Check" }
            return "Cancel Streaming"
        }
        if !store.destination.isPreviewSession, store.streamTransport == .endpointValidation {
            return "Check Endpoint"
        }
        return store.destination.isPreviewSession ? "Start Preview" : "Start Streaming"
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
            return "Check whether the configured endpoint is reachable"
        }
        return store.destination.isPreviewSession ? "Start local preview" : "Start streaming"
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
        if store.recordingState.isFailed {
            return store.recordingStatusDetail
        }
        if isStreamFailed {
            return store.streamStatusDetail
        }

        if !store.canStartStream, !store.canStopStream {
            if let startBlockedReason = store.streamStartBlockedReason {
                return startBlockedReason
            }
            if let validationError = store.destinationValidationError {
                return validationError
            }
        }

        if !store.canStartRecording, !store.canStopRecording,
           let startBlockedReason = store.recordingStartBlockedReason {
            return "Recording: \(startBlockedReason)"
        }

        return nil
    }

    private func recoverySymbol(for action: OperatorRecoveryAction) -> String {
        switch action {
        case .retryStream: "arrow.clockwise"
        case .waitForRecovery: "arrow.triangle.2.circlepath"
        case .checkDestination: "point.3.connected.trianglepath.dotted"
        case .reduceOutputCost: "speedometer"
        }
    }

    @ViewBuilder
    private func recoveryAction(for guidance: OperatorRecoveryGuidance) -> some View {
        switch guidance.action {
        case .retryStream:
            Button("Retry") {
                store.startStream()
            }
            .buttonStyle(.bordered)
            .disabled(!store.canStartStream)
            .help(store.streamStartBlockedReason ?? "Retry streaming")
        case .waitForRecovery:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(Text("Reconnect in progress"))
        case .checkDestination:
            Button("Destination") {
                selectedSettingsTabRaw = StudioSettingsTab.destination.rawValue
                openSettings()
            }
            .buttonStyle(.bordered)
            .help("Open destination setup")
        case .reduceOutputCost:
            Button("Efficiency") {
                performanceModeRaw = StudioPerformanceMode.efficiency.rawValue
                var preferences = store.preferences
                preferences.performanceMode = .efficiency
                store.updatePreferences(preferences)
            }
            .buttonStyle(.bordered)
            .disabled(store.preferences.performanceMode == .efficiency)
            .help("Use Efficiency performance mode")
        }
    }

    private func recoveryTint(for kind: OperatorRecoveryGuidanceKind) -> Color {
        switch kind {
        case .failedStart, .recoveryFailed: StudioPalette.live
        case .reconnecting, .backpressure: StudioPalette.warning
        }
    }
}
