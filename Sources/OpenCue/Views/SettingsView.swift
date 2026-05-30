import SwiftUI
import OpenCueCore

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

                if store.destination.mode == .rtmp {
                    TextField("Name", text: $store.destination.name)
                        .disabled(!store.canEditDestination)

                    SecureField("RTMP URL / stream key", text: $store.destination.rtmpURL)
                        .disabled(!store.canEditDestination)

                    Text(store.destination.safeDisplayDetail)
                        .font(.caption)
                        .foregroundStyle(destinationDetailTint)
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
}
