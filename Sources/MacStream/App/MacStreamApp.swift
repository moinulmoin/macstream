import AppKit
import SwiftUI
import MacStreamCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var prepareForTermination: (() async -> Void)?
    var prepareForSleep: (() async -> Void)?
    var resumeAfterWake: (() async -> Void)?
    var openStudioWindow: (() -> Void)?
    var isStudioWindowVisible = false

    private static let terminationTimeout: Duration = .seconds(15)

    private var terminationTask: Task<Void, Never>?
    private var terminationTimeoutTask: Task<Void, Never>?
    private var terminationAttemptID: UUID?
    private var sleepPreparationTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        workspaceNotifications.addObserver(
            self,
            selector: #selector(workspaceWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspaceNotifications.addObserver(
            self,
            selector: #selector(workspaceDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        Task { @MainActor [weak self] in
            self?.openStudioWindowIfNeeded()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openStudioWindowIfNeeded()
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let prepareForTermination else { return .terminateNow }
        guard terminationTask == nil else { return .terminateLater }

        let attemptID = UUID()
        terminationAttemptID = attemptID
        terminationTask = Task { [weak self] in
            if let sleepPreparationTask = self?.sleepPreparationTask {
                await sleepPreparationTask.value
            }
            await prepareForTermination()
            guard let self, self.terminationAttemptID == attemptID else { return }
            self.terminationTimeoutTask?.cancel()
            self.terminationTimeoutTask = nil
            self.terminationAttemptID = nil
            sender.reply(toApplicationShouldTerminate: true)
        }
        terminationTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.terminationTimeout)
            } catch {
                return
            }
            guard let self, self.terminationAttemptID == attemptID else { return }
            self.terminationAttemptID = nil
            self.terminationTask?.cancel()
            self.terminationTask = nil
            self.terminationTimeoutTask = nil
            sender.reply(toApplicationShouldTerminate: false)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        terminationTimeoutTask?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc
    private func workspaceWillSleep(_ notification: Notification) {
        guard sleepPreparationTask == nil, let prepareForSleep else { return }

        sleepPreparationTask = Task { [weak self] in
            await prepareForSleep()
            self?.sleepPreparationTask = nil
        }
    }

    @objc
    private func workspaceDidWake(_ notification: Notification) {
        guard terminationTask == nil, isStudioWindowVisible else { return }
        let pendingSleepPreparation = sleepPreparationTask
        Task { [weak self] in
            if let pendingSleepPreparation {
                await pendingSleepPreparation.value
            }
            guard let self,
                  self.terminationTask == nil,
                  self.isStudioWindowVisible
            else {
                return
            }
            await self.resumeAfterWake?()
        }
    }

    func refreshStudioWindowVisibility() -> Bool {
        let isVisible = NSApp.windows.contains { window in
            window.isVisible && isStudioWindow(window)
        }
        isStudioWindowVisible = isVisible
        return isVisible
    }

    private func openStudioWindowIfNeeded() {
        guard terminationTask == nil, !refreshStudioWindowVisibility() else { return }
        if presentExistingStudioWindow() {
            return
        }

        openStudioWindow?()
        DispatchQueue.main.async { [weak self] in
            self?.presentExistingStudioWindow()
        }
    }

    @discardableResult
    private func presentExistingStudioWindow() -> Bool {
        guard let window = NSApp.windows.first(where: isStudioWindow) else {
            return false
        }

        if window.frame.width < 2 || window.frame.height < 2 {
            window.setContentSize(NSSize(width: 1180, height: 760))
            window.center()
        }
        NSApp.unhideWithoutActivation()
        window.orderFront(nil)
        isStudioWindowVisible = window.isVisible
        return true
    }

    private func isStudioWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.hasPrefix("studio") == true
            || window.title == "MacStream"
    }
}

@main
struct MacStreamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
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
    @State private var store = StudioStore(
        mediaPipeline: SystemMediaPipeline(),
        intelligenceProvider: RuleBasedLocalIntelligenceProvider(),
        signalProvider: SystemSignalProvider(),
        performanceMonitor: MacSystemPerformanceMonitor()
    )
    @State private var updater = SparkleUpdater()
    @State private var didApplyLaunchSetupDefaults = false
    @State private var didApplyStartupConfiguration = false
    @State private var lastPersistedDestination: StreamDestination?
    @State private var destinationSaveTask: Task<Void, Never>?
    @State private var sourceConfigurationSaveTask: Task<Void, Never>?
    private static let persistenceDebounceDuration: Duration = .milliseconds(350)

    var body: some Scene {
        let _ = configureApplicationLifecycle()

        Window("MacStream", id: "studio") {
            studioWindowContent
        }
        .defaultSize(width: 1180, height: 760)
        .restorationBehavior(.disabled)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand(updater: updater)
            }
            CommandGroup(replacing: .newItem) {
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
            .onAppear {
                appDelegate.isStudioWindowVisible = true
                guard !didApplyStartupConfiguration else { return }
                didApplyStartupConfiguration = true
                applyStartupConfiguration()
            }
            .onDisappear {
                Task {
                    await handleStudioWindowDisappearance()
                }
            }

        return persistenceObservers(preferenceObservers(baseContent))
    }

    private func handleStudioWindowDisappearance() async {
        await Task.yield()
        guard !appDelegate.refreshStudioWindowVisibility() else { return }
        await store.shutdownForLifecycle()
    }

    private func configureApplicationLifecycle() {
        appDelegate.prepareForTermination = {
            await store.shutdownForLifecycle()
        }
        appDelegate.prepareForSleep = {
            await store.shutdownForLifecycle()
        }
        appDelegate.resumeAfterWake = {
            store.startSourceMonitoring()
            store.scanCaptureDevices()
        }
        appDelegate.openStudioWindow = {
            openWindow(id: "studio")
        }
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

    private func applySavedDestination() {
        let mode = StreamDestinationMode(rawValue: destinationModeRaw) ?? .preview
        // Startup intentionally leaves RTMP endpoints blank because Security.framework reads can block first-window rendering. Restoration is explicit in Settings.
        let rtmpURL = mode == .rtmp
            ? ""
            : "preview"
        let fallbackName = mode == .rtmp ? "RTMP Destination" : "Preview Session"
        let trimmedName = destinationName.trimmingCharacters(in: .whitespacesAndNewlines)

        let savedDestination = StreamDestination(
            mode: mode,
            name: trimmedName.isEmpty ? fallbackName : trimmedName,
            rtmpURL: rtmpURL
        )
        lastPersistedDestination = savedDestination
        store.applySavedDestination(savedDestination)
    }

    private func saveDestination(_ destination: StreamDestination) {
        guard destination != lastPersistedDestination else { return }

        let endpointChanged = lastPersistedDestination?.mode != destination.mode
            || lastPersistedDestination?.rtmpURL != destination.rtmpURL
        destinationModeRaw = destination.mode.rawValue
        destinationName = destination.name

        var didPersistEndpoint = true
        if endpointChanged, destination.isPersistableEndpoint {
            if !MacStreamDestinationKeychain.saveRTMPURL(destination.rtmpURL) {
                didPersistEndpoint = false
                store.reportPersistenceFailure("RTMP destination could not be saved to Keychain.")
            }
        } else if endpointChanged {
            if !MacStreamDestinationKeychain.deleteRTMPURL() {
                didPersistEndpoint = false
                store.reportPersistenceFailure("RTMP destination could not be removed from Keychain.")
            }
        }

        if didPersistEndpoint {
            lastPersistedDestination = destination
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
