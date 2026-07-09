import AppKit
import SwiftUI
import MacStreamCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct MacStreamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("recordWhileStreaming") private var recordWhileStreaming = false
    @AppStorage("directorCountdownSeconds") private var directorCountdownSeconds = 2.0
    @AppStorage("performanceMode") private var performanceModeRaw = StudioPerformanceMode.balanced.rawValue
    @AppStorage("outputResolution") private var outputResolutionRaw = StreamOutputResolution.automatic.rawValue
    @AppStorage("outputFrameRate") private var outputFrameRateRaw = StreamFrameRate.automatic.rawValue
    @AppStorage("previewRenderQuality") private var previewRenderQualityRaw = StudioPreviewRenderQuality.automatic.rawValue
    @AppStorage("defaultSceneKind") private var defaultSceneKindRaw = SceneKind.brb.rawValue
    @AppStorage("setupPrompt") private var setupPrompt = StudioStore.defaultSetupPrompt
    @AppStorage("destinationMode") private var destinationModeRaw = StreamDestinationMode.preview.rawValue
    @AppStorage("destinationName") private var destinationName = "Preview Session"
    @AppStorage("sourceConfiguration") private var sourceConfigurationJSON = ""
    @AppStorage("screenCaptureTargetPreference") private var screenCaptureTargetPreferenceJSON = ""
    @AppStorage("cameraDeviceIDPreference") private var savedCameraDeviceID = ""
    @AppStorage("microphoneDeviceIDPreference") private var savedMicrophoneDeviceID = ""
    @AppStorage("cameraEnhancementSettings") private var cameraEnhancementSettingsJSON = ""
    @AppStorage("layoutSettings") private var layoutSettingsJSON = ""
    @AppStorage("localIntelligenceProviderKind") private var localIntelligenceProviderKindRaw = LocalIntelligenceProviderKind.rules.rawValue
    @AppStorage("openAICompatibleBaseURL") private var openAICompatibleBaseURL = OpenAICompatibleProviderConfiguration.defaultBaseURL.absoluteString
    @AppStorage("openAICompatibleModel") private var openAICompatibleModel = OpenAICompatibleProviderConfiguration.defaultModel
    @AppStorage("openAICompatibleTimeout") private var openAICompatibleTimeout = OpenAICompatibleProviderConfiguration.defaultTimeout
    @State private var store = StudioStore(
        mediaPipeline: SystemMediaPipeline(),
        intelligenceProvider: RuleBasedLocalIntelligenceProvider(),
        signalProvider: SystemSignalProvider(),
        performanceMonitor: MacSystemPerformanceMonitor()
    )
    @State private var updater = SparkleUpdater()
    @State private var didApplyLaunchSetupDefaults = false
    @State private var destinationSaveTask: Task<Void, Never>?
    @State private var sourceConfigurationSaveTask: Task<Void, Never>?
    private static let persistenceDebounceDuration: Duration = .milliseconds(350)

    var body: some Scene {
        Window("MacStream", id: "studio") {
            studioWindowContent
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand(updater: updater)
            }
            CommandGroup(after: .newItem) {
                Button(streamCommandTitle) {
                    if store.canStopStream {
                        store.stopStream()
                    } else {
                        store.startStream()
                    }
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(!store.canStartStream && !store.canStopStream)

                Button(recordingCommandTitle) {
                    if store.canStopRecording {
                        store.stopRecording()
                    } else {
                        store.startRecording()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!store.canStartRecording && !store.canStopRecording)

                Button("Mark Clip") {
                    store.markClip()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(!store.canMarkClip)

                Button("Export Clip Markers") {
                    store.exportClipMarkers()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!store.canExportClipMarkers)

                Button("Export Session Report") {
                    store.exportSessionReport()
                }
                .keyboardShortcut("e", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView(store: store, updater: updater)
                .onChange(of: store.destination) { _, newDestination in
                    scheduleDestinationSave(newDestination)
                }
                .onChange(of: store.sourceConfiguration) { _, newConfiguration in
                    scheduleSourceConfigurationSave(newConfiguration)
                }
                .onChange(of: store.screenCaptureTargetPreference) { _, newTarget in
                    saveScreenCaptureTargetPreference(newTarget)
                }
                .onChange(of: store.cameraDeviceIDPreference) { _, newID in
                    saveCameraDeviceIDPreference(newID)
                }
                .onChange(of: store.microphoneDeviceIDPreference) { _, newID in
                    saveMicrophoneDeviceIDPreference(newID)
                }
                .onChange(of: store.preferences.cameraEnhancements) { _, newSettings in
                    saveCameraEnhancementSettings(newSettings)
                }
                .onChange(of: store.preferences.layoutSettings) { _, newSettings in
                    saveLayoutSettings(newSettings)
                }
                .onDisappear {
                    flushPendingPersistence()
                }
        }
    }

    private var studioWindowContent: some View {
        let baseContent = ContentView(store: store)
            .frame(minWidth: 1180, minHeight: 760)
            .task {
                applyStartupConfiguration()
            }

        return persistenceObservers(preferenceObservers(baseContent))
    }

    private func preferenceObservers<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: recordWhileStreaming) { _, _ in syncPreferences() }
            .onChange(of: directorCountdownSeconds) { _, _ in syncPreferences() }
            .onChange(of: performanceModeRaw) { _, _ in syncPreferences() }
            .onChange(of: outputResolutionRaw) { _, _ in syncPreferences() }
            .onChange(of: outputFrameRateRaw) { _, _ in syncPreferences() }
            .onChange(of: previewRenderQualityRaw) { _, _ in syncPreferences() }
            .onChange(of: setupPrompt) { _, newValue in store.applySavedSetupPrompt(newValue) }
    }

    private func persistenceObservers<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: store.destination) { _, newDestination in scheduleDestinationSave(newDestination) }
            .onChange(of: store.sourceConfiguration) { _, newConfiguration in scheduleSourceConfigurationSave(newConfiguration) }
            .onChange(of: store.screenCaptureTargetPreference) { _, newTarget in saveScreenCaptureTargetPreference(newTarget) }
            .onChange(of: store.cameraDeviceIDPreference) { _, newID in saveCameraDeviceIDPreference(newID) }
            .onChange(of: store.microphoneDeviceIDPreference) { _, newID in saveMicrophoneDeviceIDPreference(newID) }
            .onChange(of: store.preferences.cameraEnhancements) { _, newSettings in saveCameraEnhancementSettings(newSettings) }
            .onChange(of: store.preferences.layoutSettings) { _, newSettings in saveLayoutSettings(newSettings) }
            .onChange(of: scenePhase) { _, newScenePhase in
                guard newScenePhase != .active else { return }
                flushPendingPersistence()
            }
            .onDisappear {
                flushPendingPersistence()
            }
    }

    private func applyStartupConfiguration() {
        applyLaunchSetupDefaultsIfNeeded()
        applySavedLocalIntelligenceProvider()
        applySavedDestination()
        applySavedSourceConfiguration()
        applySavedScreenCaptureTargetPreference()
        applySavedCameraDeviceIDPreference()
        applySavedMicrophoneDeviceIDPreference()
        syncPreferences()
        store.scanCaptureDevicesIfNeeded()
    }

    private func applyLaunchSetupDefaultsIfNeeded() {
        guard !didApplyLaunchSetupDefaults else { return }

        didApplyLaunchSetupDefaults = true
        store.applyLaunchSetupDefaults(
            defaultSceneKind: SceneKind(rawValue: defaultSceneKindRaw),
            setupPrompt: setupPrompt
        )
    }

    private func applySavedLocalIntelligenceProvider() {
        _ = store.setIntelligenceProvider(makeLocalIntelligenceProvider())
    }

    private func makeLocalIntelligenceProvider() -> any LocalIntelligenceProvider {
        let kind = LocalIntelligenceProviderKind(rawValue: localIntelligenceProviderKindRaw) ?? .rules
        switch kind {
        case .rules:
            return RuleBasedLocalIntelligenceProvider()
        case .mlx:
            return MLXLocalIntelligenceProvider()
        case .openAICompatible:
            return OpenAICompatibleLocalIntelligenceProvider(
                configuration: OpenAICompatibleProviderConfiguration(
                    baseURL: URL(string: openAICompatibleBaseURL) ?? OpenAICompatibleProviderConfiguration.defaultBaseURL,
                    model: openAICompatibleModel,
                    apiKey: MacStreamProviderKeychain.loadOpenAICompatibleAPIKey(),
                    timeout: openAICompatibleTimeout
                )
            )
        }
    }

    private func applySavedDestination() {
        let mode = StreamDestinationMode(rawValue: destinationModeRaw) ?? .preview
        let rtmpURL = MacStreamDestinationKeychain.loadRTMPURL() ?? (mode == .rtmp ? "" : "preview")
        let fallbackName = mode == .rtmp ? "RTMP Destination" : "Preview Session"
        let trimmedName = destinationName.trimmingCharacters(in: .whitespacesAndNewlines)

        store.applySavedDestination(
            StreamDestination(
                mode: mode,
                name: trimmedName.isEmpty ? fallbackName : trimmedName,
                rtmpURL: rtmpURL
            )
        )
    }

    private func saveDestination(_ destination: StreamDestination) {
        destinationModeRaw = destination.mode.rawValue
        destinationName = destination.name

        if destination.isPersistableEndpoint {
            if !MacStreamDestinationKeychain.saveRTMPURL(destination.rtmpURL) {
                store.reportPersistenceFailure("RTMP destination could not be saved to Keychain.")
            }
        } else {
            if !MacStreamDestinationKeychain.deleteRTMPURL() {
                store.reportPersistenceFailure("RTMP destination could not be removed from Keychain.")
            }
        }
    }

    private func scheduleDestinationSave(_ destination: StreamDestination) {
        destinationSaveTask?.cancel()
        destinationSaveTask = Task { @MainActor in
            try? await Task.sleep(for: Self.persistenceDebounceDuration)
            guard !Task.isCancelled else { return }

            saveDestination(destination)
            destinationSaveTask = nil
        }
    }

    private func applySavedSourceConfiguration() {
        guard let data = sourceConfigurationJSON.data(using: .utf8),
              let configuration = try? JSONDecoder().decode([StudioSourceConfiguration].self, from: data)
        else {
            return
        }

        store.applySavedSourceConfiguration(configuration)
    }

    private func saveSourceConfiguration(_ configuration: [StudioSourceConfiguration]) {
        guard let data = try? JSONEncoder().encode(configuration),
              let json = String(data: data, encoding: .utf8)
        else {
            return
        }

        sourceConfigurationJSON = json
    }

    private func scheduleSourceConfigurationSave(_ configuration: [StudioSourceConfiguration]) {
        sourceConfigurationSaveTask?.cancel()
        sourceConfigurationSaveTask = Task { @MainActor in
            try? await Task.sleep(for: Self.persistenceDebounceDuration)
            guard !Task.isCancelled else { return }

            saveSourceConfiguration(configuration)
            sourceConfigurationSaveTask = nil
        }
    }

    private func flushPendingPersistence() {
        let shouldSaveDestination = destinationSaveTask != nil
        let shouldSaveSourceConfiguration = sourceConfigurationSaveTask != nil

        destinationSaveTask?.cancel()
        sourceConfigurationSaveTask?.cancel()
        destinationSaveTask = nil
        sourceConfigurationSaveTask = nil

        if shouldSaveDestination {
            saveDestination(store.destination)
        }

        if shouldSaveSourceConfiguration {
            saveSourceConfiguration(store.sourceConfiguration)
        }
    }

    private func applySavedScreenCaptureTargetPreference() {
        guard let data = screenCaptureTargetPreferenceJSON.data(using: .utf8),
              let target = try? JSONDecoder().decode(ScreenCaptureTarget.self, from: data)
        else {
            return
        }

        store.applySavedScreenCaptureTargetPreference(target)
    }

    private func saveScreenCaptureTargetPreference(_ target: ScreenCaptureTarget?) {
        guard let target else {
            screenCaptureTargetPreferenceJSON = ""
            return
        }

        guard let data = try? JSONEncoder().encode(target),
              let json = String(data: data, encoding: .utf8)
        else {
            return
        }

        screenCaptureTargetPreferenceJSON = json
    }

    private func applySavedCameraDeviceIDPreference() {
        guard !savedCameraDeviceID.isEmpty else { return }
        store.applySavedCameraDeviceIDPreference(savedCameraDeviceID)
    }

    private func applySavedMicrophoneDeviceIDPreference() {
        guard !savedMicrophoneDeviceID.isEmpty else { return }
        store.applySavedMicrophoneDeviceIDPreference(savedMicrophoneDeviceID)
    }

    private func saveCameraDeviceIDPreference(_ id: String?) {
        savedCameraDeviceID = id ?? ""
    }

    private func saveMicrophoneDeviceIDPreference(_ id: String?) {
        savedMicrophoneDeviceID = id ?? ""
    }

    private func loadCameraEnhancementSettings() -> CameraEnhancementSettings {
        guard let data = cameraEnhancementSettingsJSON.data(using: .utf8),
              let settings = try? JSONDecoder().decode(CameraEnhancementSettings.self, from: data)
        else {
            return CameraEnhancementSettings()
        }

        return settings
    }

    private func saveCameraEnhancementSettings(_ settings: CameraEnhancementSettings) {
        guard let data = try? JSONEncoder().encode(settings),
              let json = String(data: data, encoding: .utf8)
        else {
            return
        }

        cameraEnhancementSettingsJSON = json
    }

    private func loadLayoutSettings() -> StudioLayoutSettings {
        guard let data = layoutSettingsJSON.data(using: .utf8),
              let settings = try? JSONDecoder().decode(StudioLayoutSettings.self, from: data)
        else {
            return StudioLayoutSettings()
        }

        return settings
    }

    private func saveLayoutSettings(_ settings: StudioLayoutSettings) {
        guard let data = try? JSONEncoder().encode(settings),
              let json = String(data: data, encoding: .utf8)
        else {
            return
        }

        layoutSettingsJSON = json
    }

    private func syncPreferences() {
        let normalizedCountdown = StudioPreferences.normalizedDirectorCountdownSeconds(Int(directorCountdownSeconds))
        if directorCountdownSeconds != Double(normalizedCountdown) {
            directorCountdownSeconds = Double(normalizedCountdown)
        }

        store.updatePreferences(
            StudioPreferences(
                recordWhileStreaming: recordWhileStreaming,
                directorCountdownSeconds: normalizedCountdown,
                performanceMode: StudioPerformanceMode(rawValue: performanceModeRaw) ?? .balanced,
                cameraEnhancements: loadCameraEnhancementSettings(),
                outputResolution: StreamOutputResolution(rawValue: outputResolutionRaw) ?? .automatic,
                outputFrameRate: StreamFrameRate(rawValue: outputFrameRateRaw) ?? .automatic,
                previewRenderQuality: StudioPreviewRenderQuality(rawValue: previewRenderQualityRaw) ?? .automatic,
                layoutSettings: loadLayoutSettings()
            )
        )
    }

    private var streamCommandTitle: String {
        if store.isLive {
            if store.streamTransport == .preview { return "Stop Preview" }
            if store.streamTransport == .endpointValidation { return "Stop Endpoint Check" }
            return "Stop Streaming"
        }
        if store.isStreamConnecting {
            if store.streamTransport == .preview { return "Cancel Preview Start" }
            if store.streamTransport == .endpointValidation { return "Cancel Endpoint Check" }
            return "Cancel Start Streaming"
        }
        if !store.destination.isPreviewSession, store.streamTransport == .endpointValidation {
            return "Check Endpoint"
        }
        return store.destination.isPreviewSession ? "Start Preview" : "Start Streaming"
    }

    private var recordingCommandTitle: String {
        if store.isRecordingStopping { return "Stopping Recording" }
        if store.recordingState == .recording { return "Stop Recording" }
        if store.isRecordingStarting { return "Cancel Recording Start" }
        return "Start Recording"
    }
}
