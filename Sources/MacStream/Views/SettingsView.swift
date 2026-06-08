import SwiftUI
import MacStreamCore

struct SettingsView: View {
    @Bindable var store: StudioStore
    @AppStorage("directorCountdownSeconds") private var directorCountdownSeconds = 2.0
    @AppStorage("recordWhileStreaming") private var recordWhileStreaming = false
    @AppStorage("defaultSceneKind") private var defaultSceneKindRaw = SceneKind.brb.rawValue
    @AppStorage("setupPrompt") private var setupPrompt = StudioStore.defaultSetupPrompt

    var body: some View {
        Form {
            Section("Startup") {
                Picker("Startup scene", selection: $defaultSceneKindRaw) {
                    ForEach(SceneKind.allCases) { sceneKind in
                        Label(sceneKind.title, systemImage: sceneKind.symbolName)
                            .tag(sceneKind.rawValue)
                    }
                }
            }

            Section("Destination") {
                Picker("Mode", selection: destinationMode) {
                    ForEach(StreamDestinationMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbolName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!store.canEditDestination)

                presetPicker

                if store.destination.mode == .rtmp {
                    TextField("Name", text: $store.destination.name)
                        .disabled(!store.canEditDestination)

                    SecureField("RTMP URL / stream key", text: $store.destination.rtmpURL)
                        .disabled(!store.canEditDestination)

                    Text(store.destination.safeDisplayDetail)
                        .font(.caption)
                        .foregroundStyle(destinationDetailTint)

                    if let destinationKeyHint {
                        Label(destinationKeyHint, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Label(store.destination.safeDisplayDetail, systemImage: StreamDestinationMode.preview.symbolName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Setup Rules") {
                TextField("Stream description", text: setupPromptBinding, axis: .vertical)
                    .lineLimit(2...4)

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
                    Text(store.localIntelligenceStatus.availability.title)
                        .foregroundStyle(statusTint(store.localIntelligenceStatus.availability))
                }

                LabeledContent("Profile") {
                    Text(store.directorProfile.kind.title)
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
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 460)
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

    private var directorCountdownRange: ClosedRange<Double> {
        Double(StudioPreferences.minimumDirectorCountdownSeconds)...Double(StudioPreferences.maximumDirectorCountdownSeconds)
    }

    private var destinationMode: Binding<StreamDestinationMode> {
        Binding(
            get: { store.destination.mode },
            set: { store.setDestinationMode($0) }
        )
    }

    private var destinationDetailTint: Color {
        store.destination.isReadyToStart ? .secondary : .orange
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
