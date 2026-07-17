import SwiftUI
import AppKit
import MacStreamCore

enum StudioSettingsTab: String {
    static let storageKey = "MacStream.Settings.selectedTab"

    case general
    case destination
    case about
}

struct SettingsView: View {
    @Bindable var store: StudioStore
    var updater: SparkleUpdater
    @AppStorage("directorCountdownSeconds") private var directorCountdownSeconds = 2.0
    @AppStorage("recordWhileStreaming") private var recordWhileStreaming = false
    @AppStorage("performanceMode") private var performanceModeRaw = StudioPerformanceMode.balanced.rawValue
    @AppStorage("outputResolution") private var outputResolutionRaw = StreamOutputResolution.automatic.rawValue
    @AppStorage("outputFrameRate") private var outputFrameRateRaw = StreamFrameRate.automatic.rawValue
    @AppStorage("previewRenderQuality") private var previewRenderQualityRaw = StudioPreviewRenderQuality.automatic.rawValue
    @AppStorage("defaultSceneKind") private var defaultSceneKindRaw = SceneKind.brb.rawValue
    @AppStorage("setupPrompt") private var setupPrompt = StudioStore.defaultSetupPrompt
    @AppStorage(StudioSettingsTab.storageKey) private var selectedTabRaw = StudioSettingsTab.general.rawValue
    @AppStorage("localIntelligenceProviderKind") private var localIntelligenceProviderKindRaw = LocalIntelligenceProviderKind.rules.rawValue
    @AppStorage("openAICompatibleBaseURL") private var openAICompatibleBaseURL = OpenAICompatibleProviderConfiguration.defaultBaseURL.absoluteString
    @AppStorage("openAICompatibleModel") private var openAICompatibleModel = OpenAICompatibleProviderConfiguration.defaultModel
    @AppStorage("openAICompatibleTimeout") private var openAICompatibleTimeout = OpenAICompatibleProviderConfiguration.defaultTimeout
    @State private var openAICompatibleAPIKey = ""
    @State private var providerProbeTask: Task<Void, Never>?
    @State private var providerProbeMessage = "Not checked"
    @State private var providerApplyPending = false
    @State private var restoreEndpointTask: Task<Void, Never>?
    @State private var restoreEndpointRequestID = UUID()
    @State private var restoreEndpointMessage: String?

    var body: some View {
        TabView(selection: $selectedTabRaw) {
            generalTab
                .tag(StudioSettingsTab.general.rawValue)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            destinationTab
                .tag(StudioSettingsTab.destination.rawValue)
                .tabItem {
                    Label("Destination", systemImage: "dot.radiowaves.left.and.right")
                }

            aboutTab
                .tag(StudioSettingsTab.about.rawValue)
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 580)
        .frame(minHeight: 420)
        .onDisappear {
            providerProbeTask?.cancel()
            restoreEndpointTask?.cancel()
        }
        .onChange(of: store.destination) { oldDestination, newDestination in
            guard oldDestination.mode != newDestination.mode
                || oldDestination.rtmpURL != newDestination.rtmpURL
            else {
                return
            }
            cancelSavedEndpointRestore()
        }
        .onChange(of: store.selectedDestinationID) { _, _ in
            cancelSavedEndpointRestore()
        }
    }

    private var generalTab: some View {
        Form {
            Section("Startup") {
                Picker("Startup scene", selection: $defaultSceneKindRaw) {
                    ForEach(SceneKind.allCases) { sceneKind in
                        Label(sceneKind.title, systemImage: sceneKind.symbolName)
                            .tag(sceneKind.rawValue)
                    }
                }
            }

            Section("Stream Behavior") {
                Toggle("Record while streaming", isOn: recordWhileStreamingBinding)

                LabeledContent("Cue countdown") {
                    Stepper(
                        "\(displayedDirectorCountdownSeconds) seconds",
                        value: directorCountdownBinding,
                        in: directorCountdownRange,
                        step: 1
                    )
                }
            }

            Section("Output") {
                Picker("Performance", selection: performanceModeBinding) {
                    ForEach(StudioPerformanceMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }

                Picker("Resolution", selection: outputResolutionBinding) {
                    ForEach(StreamOutputResolution.allCases) { resolution in
                        Text(resolution.title).tag(resolution.rawValue)
                    }
                }
                .disabled(!store.canEditOutputCaptureSettings)
                .help(store.outputCaptureSettingsLockedReason ?? "Choose the encoded stream and recording resolution.")

                Picker("Frame rate", selection: outputFrameRateBinding) {
                    ForEach(StreamFrameRate.allCases) { frameRate in
                        Text(frameRate.title).tag(frameRate.rawValue)
                    }
                }
                .disabled(!store.canEditOutputCaptureSettings)
                .help(store.outputCaptureSettingsLockedReason ?? "Choose the encoded stream and recording frame rate.")

                Picker("Preview quality", selection: previewRenderQualityBinding) {
                    ForEach(StudioPreviewRenderQuality.allCases) { quality in
                        Text(quality.detailTitle).tag(quality.rawValue)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(StudioMetrics.lg)
    }

    private var destinationTab: some View {
        Form {
            Section("Destination") {
                Picker("Mode", selection: destinationMode) {
                    ForEach(StreamDestinationMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbolName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!store.canEditDestination)

                if store.destinationMode == .rtmp {
                    destinationList
                    selectedDestinationEditor
                } else {
                    Label(store.destination.safeDisplayDetail, systemImage: StreamDestinationMode.preview.symbolName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(StudioMetrics.lg)
    }

    private var destinationList: some View {
        VStack(alignment: .leading, spacing: StudioMetrics.sm) {
            HStack {
                Text("Targets")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    store.addDestination()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .controlSize(.small)
                .disabled(!store.canAddDestination)
                .help("Add up to \(StudioStore.maxStreamDestinations) destinations")
            }

            VStack(spacing: StudioMetrics.xs) {
                ForEach(store.destinations) { destination in
                    destinationListRow(destination)
                }
            }

            Text(store.destinationSummary)
                .font(.caption)
                .foregroundStyle(destinationDetailTint)

            if let validationError = store.destinationValidationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(StudioPalette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var selectedDestinationEditor: some View {
        VStack(alignment: .leading, spacing: StudioMetrics.sm) {
            Divider()

            if store.selectedDestination != nil {
                presetPicker

                TextField("Name", text: destinationName)
                    .disabled(!store.canEditDestination)

                TextField("Server URL", text: rtmpServerURL)
                    .textContentType(.URL)
                    .disabled(!store.canEditDestination)

                SecureField("Stream key", text: rtmpStreamKey)
                    .disabled(!store.canEditDestination)

                HStack(alignment: .center, spacing: StudioMetrics.sm) {
                    Button {
                        restoreSavedEndpoint()
                    } label: {
                        if restoreEndpointTask != nil {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Restoring…")
                            }
                        } else {
                            Label("Restore Saved Endpoint", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!store.canEditDestination || restoreEndpointTask != nil)

                    Text(store.destination.safeDisplayDetail)
                        .font(.caption)
                        .foregroundStyle(destinationDetailTint)
                        .lineLimit(1)
                }

                if let restoreEndpointMessage {
                    Text(restoreEndpointMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let destinationKeyHint {
                    Label(destinationKeyHint, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Add an RTMP target to edit it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func destinationListRow(_ destination: StreamDestination) -> some View {
        let isSelected = store.selectedDestinationID == destination.id || (store.selectedDestinationID == nil && store.destinations.first?.id == destination.id)
        let status = statusForDestination(destination)

        return HStack(alignment: .center, spacing: StudioMetrics.sm) {
            Toggle("", isOn: destinationEnabledBinding(destination.id))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(!store.canEditDestination)
                .help(destination.isEnabled ? "Disable destination" : "Enable destination")

            Button {
                store.selectDestination(id: destination.id)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: StudioMetrics.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(destination.name.isEmpty ? "RTMP Destination" : destination.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(destination.safeDisplayDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: StudioMetrics.sm)

                    Label(status.title, systemImage: status.symbolName)
                        .font(.caption)
                        .foregroundStyle(status.tint)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                store.removeDestination(id: destination.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(!store.canEditDestination)
            .help("Remove destination")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background {
            RoundedRectangle(cornerRadius: StudioMetrics.controlRadius, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: StudioMetrics.controlRadius, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func destinationEnabledBinding(_ id: StreamDestination.ID) -> Binding<Bool> {
        Binding(
            get: { store.destinations.first(where: { $0.id == id })?.isEnabled ?? false },
            set: { store.setDestinationEnabled(id: id, isEnabled: $0) }
        )
    }

    private func statusForDestination(_ destination: StreamDestination) -> (title: String, symbolName: String, tint: Color) {
        guard destination.isEnabled else {
            return ("Disabled", "circle.slash", .secondary)
        }

        if let status = store.destinationStatuses.first(where: { $0.id == destination.id }) {
            return statusPresentation(status)
        }

        if destination.isReadyToStart {
            return ("Ready", "checkmark.circle", .secondary)
        }

        return ("Needs setup", "exclamationmark.triangle", StudioPalette.warning)
    }

    private func statusPresentation(_ status: StreamDestinationStatus) -> (title: String, symbolName: String, tint: Color) {
        switch status.state {
        case .publishing:
            return ("Live", "checkmark.circle.fill", StudioPalette.success)
        case .connecting:
            return ("Connecting", "arrow.triangle.2.circlepath", StudioPalette.warning)
        case .degraded:
            return ("Degraded", "exclamationmark.triangle", StudioPalette.warning)
        case .reconnecting:
            return ("Degraded", "arrow.triangle.2.circlepath", StudioPalette.warning)
        case .failed:
            return ("Failed", "exclamationmark.triangle.fill", StudioPalette.live)
        case .idle:
            return ("Idle", "circle", .secondary)
        }
    }

    private var aiSetupTab: some View {
        Form {
            Section("Setup Rules") {
                TextField("Stream description", text: setupPromptBinding, axis: .vertical)
                    .lineLimit(2...4)

                Picker("Provider", selection: localIntelligenceProviderKind) {
                    ForEach(LocalIntelligenceProviderKind.allCases) { providerKind in
                        Text(providerKind.title).tag(providerKind)
                    }
                }

                if selectedLocalIntelligenceProviderKind == .openAICompatible {
                    TextField("Base URL", text: openAICompatibleBaseURLBinding)
                        .textContentType(.URL)
                    TextField("Model", text: openAICompatibleModelBinding)
                    SecureField("API key", text: openAICompatibleAPIKeyBinding)

                    LabeledContent("Timeout") {
                        Stepper(
                            "\(Int(clampedOpenAICompatibleTimeout)) seconds",
                            value: openAICompatibleTimeoutBinding,
                            in: openAICompatibleTimeoutRange,
                            step: 1
                        )
                    }

                    Button("Test connection") {
                        testOpenAICompatibleConnection()
                    }

                    Text(providerProbeMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    store.generateSetupPlan()
                } label: {
                    if store.isGeneratingSetupPlan {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Generating")
                        }
                    } else {
                        Label("Generate Rules", systemImage: "wand.and.stars")
                    }
                }
                .disabled(!store.canGenerateSetupPlan)
                .help(store.setupGenerationStatusDetail)

                LabeledContent("Local model") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(store.localIntelligenceStatus.availability.title)
                            .foregroundStyle(statusTint(store.localIntelligenceStatus.availability))
                        Text(store.localIntelligenceStatus.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Profile") {
                    Text(store.directorProfile.kind.title)
                }
            }
        }
        .formStyle(.grouped)
        .padding(StudioMetrics.lg)
    }

    private var aboutTab: some View {
        VStack(spacing: StudioMetrics.lg) {
            Group {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 64, height: 64)
                } else {
                    Image(systemName: "app.gift")
                        .font(.system(size: 48))
                        .foregroundStyle(StudioPalette.accent)
                        .frame(width: 64, height: 64)
                }
            }

            Text("MacStream")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)

            Text(settingsVersionLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            .buttonStyle(StudioPrimaryButtonStyle())
            .disabled(!updater.canCheckForUpdates)

            VStack(spacing: StudioMetrics.sm) {
                Link("View on GitHub", destination: URL(string: "https://github.com/moinulmoin/macstream")!)
                    .font(.subheadline)

                Link("Releases", destination: URL(string: "https://github.com/moinulmoin/macstream/releases")!)
                    .font(.subheadline)
            }
            .padding(.top, StudioMetrics.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(StudioMetrics.xl)
    }

    private var settingsVersionLine: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Version \(short) (\(build))"
    }

    private var displayedDirectorCountdownSeconds: Int {
        StudioPreferences.normalizedDirectorCountdownSeconds(Int(directorCountdownSeconds))
    }

    private var directorCountdownBinding: Binding<Double> {
        Binding(
            get: { Double(displayedDirectorCountdownSeconds) },
            set: { newValue in
                let normalizedSeconds = StudioPreferences.normalizedDirectorCountdownSeconds(Int(newValue))
                directorCountdownSeconds = Double(normalizedSeconds)
                var preferences = store.preferences
                preferences.directorCountdownSeconds = normalizedSeconds
                store.updatePreferences(preferences)
            }
        )
    }

    private var recordWhileStreamingBinding: Binding<Bool> {
        Binding(
            get: { recordWhileStreaming },
            set: { newValue in
                recordWhileStreaming = newValue
                var preferences = store.preferences
                preferences.recordWhileStreaming = newValue
                store.updatePreferences(preferences)
            }
        )
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

    private var directorCountdownRange: ClosedRange<Double> {
        Double(StudioPreferences.minimumDirectorCountdownSeconds)...Double(StudioPreferences.maximumDirectorCountdownSeconds)
    }

    private var destinationMode: Binding<StreamDestinationMode> {
        Binding(
            get: { store.destinationMode },
            set: { store.setDestinationMode($0) }
        )
    }

    private var destinationName: Binding<String> {
        Binding(
            get: { store.destination.name },
            set: { newValue in
                var nextDestination = store.destination
                nextDestination.name = newValue
                store.destination = nextDestination
            }
        )
    }

    private var rtmpServerURL: Binding<String> {
        Binding(
            get: { store.destination.rtmpServerURL },
            set: { store.setRTMPServerURL($0) }
        )
    }

    private var rtmpStreamKey: Binding<String> {
        Binding(
            get: { store.destination.rtmpStreamKey },
            set: { store.setRTMPStreamKey($0) }
        )
    }

    private func restoreSavedEndpoint() {
        restoreEndpointTask?.cancel()

        guard let destinationID = store.selectedDestination?.id else {
            restoreEndpointMessage = "Select a destination first"
            return
        }
        let requestedMode = store.destination.mode
        let requestedEndpoint = store.destination.rtmpURL
        let requestID = UUID()
        restoreEndpointRequestID = requestID
        restoreEndpointMessage = "Restoring…"

        let loadTask = Task.detached(priority: .userInitiated) {
            MacStreamDestinationKeychain.loadRTMPStreamKey(for: destinationID, allowUserInteraction: true)
        }
        restoreEndpointTask = Task { @MainActor in
            let savedStreamKey = await loadTask.value
            guard !Task.isCancelled,
                  requestID == restoreEndpointRequestID
            else {
                return
            }
            guard store.destination.mode == requestedMode,
                  store.destination.rtmpURL == requestedEndpoint
            else {
                restoreEndpointTask = nil
                restoreEndpointMessage = "Restore cancelled"
                return
            }

            restoreEndpointTask = nil
            guard let savedStreamKey, !savedStreamKey.isEmpty else {
                restoreEndpointMessage = "No saved stream key found"
                return
            }

            store.setRTMPStreamKey(savedStreamKey)
            restoreEndpointMessage = "Saved stream key restored"
        }
    }

    private func cancelSavedEndpointRestore() {
        guard restoreEndpointTask != nil else { return }
        restoreEndpointTask?.cancel()
        restoreEndpointTask = nil
        restoreEndpointMessage = "Restore cancelled"
    }

    private var destinationDetailTint: Color {
        store.destinationValidationError == nil ? .secondary : .orange
    }

    private var setupPromptBinding: Binding<String> {
        Binding(
            get: { setupPrompt },
            set: { newValue in
                let boundedPrompt = StudioStore.boundedSetupPrompt(newValue)
                setupPrompt = boundedPrompt
                store.applySavedSetupPrompt(boundedPrompt)
            }
        )
    }

    private var selectedLocalIntelligenceProviderKind: LocalIntelligenceProviderKind {
        LocalIntelligenceProviderKind(rawValue: localIntelligenceProviderKindRaw) ?? .rules
    }

    private var localIntelligenceProviderKind: Binding<LocalIntelligenceProviderKind> {
        Binding(
            get: { selectedLocalIntelligenceProviderKind },
            set: { newValue in
                localIntelligenceProviderKindRaw = newValue.rawValue
                providerProbeMessage = newValue == .openAICompatible ? "Not checked" : "Rules active"
                applySelectedIntelligenceProvider()
            }
        )
    }

    private var openAICompatibleBaseURLBinding: Binding<String> {
        Binding(
            get: { openAICompatibleBaseURL },
            set: { newValue in
                openAICompatibleBaseURL = newValue
                providerProbeMessage = "Not checked"
                applySelectedIntelligenceProvider()
            }
        )
    }

    private var openAICompatibleModelBinding: Binding<String> {
        Binding(
            get: { openAICompatibleModel },
            set: { newValue in
                openAICompatibleModel = newValue
                providerProbeMessage = "Not checked"
                applySelectedIntelligenceProvider()
            }
        )
    }

    private var openAICompatibleAPIKeyBinding: Binding<String> {
        Binding(
            get: { openAICompatibleAPIKey },
            set: { newValue in
                openAICompatibleAPIKey = newValue
                let saved = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? MacStreamProviderKeychain.deleteOpenAICompatibleAPIKey()
                    : MacStreamProviderKeychain.saveOpenAICompatibleAPIKey(newValue)
                if !saved {
                    store.reportPersistenceFailure("OpenAI-compatible API key could not be saved to Keychain.")
                }
                providerProbeMessage = "Not checked"
                applySelectedIntelligenceProvider()
            }
        )
    }

    private var openAICompatibleTimeoutBinding: Binding<Double> {
        Binding(
            get: { clampedOpenAICompatibleTimeout },
            set: { newValue in
                openAICompatibleTimeout = min(max(newValue, openAICompatibleTimeoutRange.lowerBound), openAICompatibleTimeoutRange.upperBound)
                providerProbeMessage = "Not checked"
                applySelectedIntelligenceProvider()
            }
        )
    }

    private var openAICompatibleTimeoutRange: ClosedRange<Double> { 5...120 }

    private var clampedOpenAICompatibleTimeout: Double {
        min(max(openAICompatibleTimeout, openAICompatibleTimeoutRange.lowerBound), openAICompatibleTimeoutRange.upperBound)
    }

    private func applySelectedIntelligenceProvider() {
        providerProbeTask?.cancel()
        providerProbeTask = nil
        providerApplyPending = !store.setIntelligenceProvider(makeLocalIntelligenceProviderFromSettings())
    }

    private func applyPendingIntelligenceProviderIfNeeded() {
        guard providerApplyPending else { return }
        providerApplyPending = !store.setIntelligenceProvider(makeLocalIntelligenceProviderFromSettings())
    }

    private var providerReapplyTrigger: String {
        [
            store.isGeneratingSetupPlan.description,
            store.isStreamConnecting.description,
            store.isLive.description,
            store.isRecordingStarting.description,
            store.isRecordingStopping.description,
            String(describing: store.recordingState)
        ].joined(separator: ":")
    }

    private func makeLocalIntelligenceProviderFromSettings() -> any LocalIntelligenceProvider {
        switch selectedLocalIntelligenceProviderKind {
        case .rules:
            return RuleBasedLocalIntelligenceProvider()
        case .mlx:
            return MLXLocalIntelligenceProvider()
        case .openAICompatible:
            return makeOpenAICompatibleProviderFromSettings()
        }
    }

    private func makeOpenAICompatibleProviderFromSettings() -> OpenAICompatibleLocalIntelligenceProvider {
        OpenAICompatibleLocalIntelligenceProvider(
            configuration: OpenAICompatibleProviderConfiguration(
                baseURL: URL(string: openAICompatibleBaseURL) ?? OpenAICompatibleProviderConfiguration.defaultBaseURL,
                model: openAICompatibleModel,
                apiKey: openAICompatibleAPIKey,
                timeout: clampedOpenAICompatibleTimeout
            )
        )
    }

    private func testOpenAICompatibleConnection() {
        providerProbeTask?.cancel()
        providerProbeMessage = "Checking..."
        let provider = makeOpenAICompatibleProviderFromSettings()
        let signature = openAICompatibleProviderSettingsSignature
        providerProbeTask = Task { @MainActor in
            let status = await provider.probeCapabilities()
            guard !Task.isCancelled, signature == openAICompatibleProviderSettingsSignature else { return }
            providerProbeMessage = status.availability == .available ? "Reachable" : status.detail
            providerApplyPending = !store.setIntelligenceProvider(provider.replacingProbedStatus(status))
            providerProbeTask = nil
        }
    }

    private var openAICompatibleProviderSettingsSignature: String {
        [
            openAICompatibleBaseURL,
            openAICompatibleModel,
            openAICompatibleAPIKey,
            clampedOpenAICompatibleTimeout.description
        ].joined(separator: "\u{1F}")
    }

    private func statusTint(_ availability: LocalIntelligenceAvailability) -> Color {
        switch availability {
        case .available: .green
        case .fallback: .orange
        case .unavailable: .red
        }
    }

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick connect")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(StreamPlatformPreset.allCases) { preset in
                    DestinationPresetChip(
                        preset: preset,
                        tint: presetTint(preset),
                        isSelected: selectedPreset == preset,
                        isEnabled: store.canEditDestination
                    ) {
                        store.applyDestinationPreset(preset)
                    }
                }
            }
        }
    }

    private var selectedPreset: StreamPlatformPreset? {
        if let match = store.matchingDestinationPreset { return match }
        return store.destination.mode == .rtmp ? .custom : nil
    }

    private var destinationKeyHint: String? {
        if let preset = store.matchingDestinationPreset { return preset.keyHint }
        return store.destination.mode == .rtmp ? StreamPlatformPreset.custom.keyHint : nil
    }

    private func presetTint(_ preset: StreamPlatformPreset) -> Color {
        switch preset {
        case .twitch: Color(red: 0.57, green: 0.27, blue: 1.0)
        case .youtube: Color(red: 0.90, green: 0.16, blue: 0.16)
        case .facebook: Color(red: 0.10, green: 0.47, blue: 0.95)
        case .x: Color(white: 0.62)
        case .kick: Color(red: 0.33, green: 0.82, blue: 0.30)
        case .custom: StudioPalette.accent
        }
    }
}

private struct DestinationPresetChip: View {
    let preset: StreamPlatformPreset
    let tint: Color
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: preset.symbolName)
                    .font(.caption)
                Text(preset.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.primary.opacity(hovering ? 0.10 : 0.05)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? Color.white.opacity(0.25) : tint.opacity(0.35), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .help(preset.keyHint)
        .accessibilityLabel(Text("\(preset.title) destination preset"))
    }
}
