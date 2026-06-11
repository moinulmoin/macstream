import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import Network
import Testing
@testable import MacStreamCore

@Test
func packageMetadataDefinesRequiredCapturePrivacyKeys() throws {
    let infoPlistURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Resources/Info.plist")
    let packageScriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("script/package_macos_app.sh")
    let infoPlist = try String(contentsOf: infoPlistURL, encoding: .utf8)
    let packageScript = try String(contentsOf: packageScriptURL, encoding: .utf8)

    #expect(infoPlist.contains("NSCameraUsageDescription"))
    #expect(infoPlist.contains("NSMicrophoneUsageDescription"))
    #expect(infoPlist.contains("NSAudioCaptureUsageDescription"))
    #expect(infoPlist.contains("CFBundleShortVersionString"))
    #expect(infoPlist.contains("CFBundleVersion"))
    #expect(infoPlist.contains("CFBundleIconFile"))
    #expect(packageScript.contains("Resources/Info.plist"))
    #expect(packageScript.contains("Resources/AppIcon/MacStream.icns"))
    #expect(packageScript.contains("cp \"$APP_ICON\" \"$APP_RESOURCES/MacStream.icns\""))
}

@Test
func packagingScriptsSignAppBundleWithStableIdentifier() throws {
    let runScriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("script/build_and_run.sh")
    let packageScriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("script/package_macos_app.sh")
    let runScript = try String(contentsOf: runScriptURL, encoding: .utf8)
    let packageScript = try String(contentsOf: packageScriptURL, encoding: .utf8)

    #expect(runScript.contains("BUNDLE_ID=\"com.ideaplexa.macstream\""))
    #expect(!runScript.contains("BUNDLE_ID=\"com.macstream.app\""))
    #expect(runScript.contains("Developer ID Application: Ideaplexa LLC (53P98M92V7)"))
    #expect(runScript.contains("MAC_STREAM_CODESIGN_IDENTITY"))
    #expect(runScript.contains("MAC_STREAM_CODESIGN_TIMESTAMP=\"${MAC_STREAM_CODESIGN_TIMESTAMP:-none}\""))
    #expect(runScript.contains("\"$ROOT_DIR/script/package_macos_app.sh\""))
    #expect(packageScript.contains("BUNDLE_ID=\"${MAC_STREAM_BUNDLE_ID:-com.ideaplexa.macstream}\""))
    #expect(packageScript.contains("MAC_STREAM_CODESIGN_IDENTITY"))
    #expect(packageScript.contains("--identifier \"$BUNDLE_ID\""))
    #expect(packageScript.contains("--options runtime --entitlements \"$ENTITLEMENTS\""))
    #expect(packageScript.contains("--timestamp --sign \"$SIGN_IDENTITY\""))
    #expect(packageScript.contains("--timestamp=none --sign -"))
    #expect(packageScript.contains("--requirements \"=designated => identifier \\\"$BUNDLE_ID\\\"\""))
    #expect(packageScript.contains("/usr/bin/codesign --verify --strict --verbose=2 \"$APP_BUNDLE\""))
    #expect(packageScript.contains("xattr -cr \"$APP_BUNDLE\""))
    #expect(packageScript.contains("expected code signature identifier $BUNDLE_ID"))
    #expect(packageScript.contains("expected stable designated requirement"))
}

@Test
func screenCapturePermissionHintExplainsRestartRequirement() {
    let display = CaptureDeviceInfo(
        id: "display-7",
        kind: .display,
        name: "Studio Display",
        detail: "3024x1964",
        permission: .notDetermined
    )
    let window = CaptureDeviceInfo(
        id: "window-42",
        kind: .window,
        name: "Slides",
        detail: "Keynote",
        permission: .denied
    )
    let camera = CaptureDeviceInfo(
        id: "camera-1",
        kind: .camera,
        name: "FaceTime Camera",
        permission: .notDetermined
    )
    let grantedDisplay = CaptureDeviceInfo(
        id: "display-8",
        kind: .display,
        name: "External Display",
        permission: .granted
    )

    #expect(display.permissionRecoveryHint == "Enable Screen Recording in System Settings. If it is already on, quit and reopen MacStream.")
    #expect(window.permissionRecoveryHint == "Enable Screen Recording in System Settings. If it is already on, quit and reopen MacStream.")
    #expect(camera.permissionRecoveryHint == nil)
    #expect(grantedDisplay.permissionRecoveryHint == nil)

    let report = CapturePreflightReport(devices: [camera, grantedDisplay])
    let screenBlockedReport = CapturePreflightReport(devices: [camera, grantedDisplay, display])

    #expect(!report.requiresRelaunchToRefreshPermissionState)
    #expect(screenBlockedReport.requiresRelaunchToRefreshPermissionState)
    #expect(report.isScreenCapturePermissionGranted)
    #expect(screenBlockedReport.isScreenCapturePermissionGranted)
    #expect(!CapturePreflightReport(devices: [camera]).isScreenCapturePermissionGranted)
}


@Test
func capturePermissionAttentionGroupsDeviceInstancesByPermissionKind() {
    let devices = [
        CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "iPhone Camera", permission: .notDetermined),
        CaptureDeviceInfo(id: "camera-2", kind: .camera, name: "MacBook Camera", permission: .notDetermined),
        CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "iPhone Mic", permission: .notDetermined),
        CaptureDeviceInfo(id: "microphone-2", kind: .microphone, name: "USB Mic", permission: .notDetermined),
        CaptureDeviceInfo(id: "display-1", kind: .display, name: "Main Display", permission: .notDetermined),
        CaptureDeviceInfo(id: "window-1", kind: .window, name: "Slides", permission: .notDetermined)
    ]
    let report = CapturePreflightReport(devices: devices)

    #expect(report.permissionAttentionKindCount == 3)
    #expect(CapturePreflightReport.permissionAttentionSummary(for: devices) == "3 capture permissions need attention.")
}
@Test
func screenCaptureScanDoesNotLoadShareableContentBeforePermissionIsVisible() async {
    let listing = CountingScreenCaptureContentListing()
    let provider = SystemCaptureDeviceProvider(
        screenCaptureAccessProvider: { false },
        screenContentListing: listing
    )

    let report = await provider.scan()
    let screenDevice = report.devices.first { $0.id == "screen-permission" }

    #expect(await listing.deviceLoadCount() == 0)
    #expect(screenDevice?.kind == .display)
    #expect(screenDevice?.permission == .notDetermined)
    #expect(screenDevice?.detail == "Screen Recording permission is not visible to this launch.")
    #expect(screenDevice?.permissionRecoveryHint == "Enable Screen Recording in System Settings. If it is already on, quit and reopen MacStream.")
    #expect(report.screenCaptureTargets.isEmpty)
}

@Test
func capturePreflightViewOffersRelaunchForRestartScopedPermissions() throws {
    let viewURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStream/Views/CapturePreflightView.swift")
    let relauncherURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStream/Support/MacStreamRelauncher.swift")
    let viewSource = try String(contentsOf: viewURL, encoding: .utf8)
    let relauncherSource = try String(contentsOf: relauncherURL, encoding: .utf8)

    #expect(viewSource.contains("requiresRelaunchForRequiredCapturePermission"))
    #expect(viewSource.contains("!store.shouldShowSetupChecklist"))
    #expect(viewSource.contains("Label(\"Reopen MacStream\""))
    #expect(viewSource.contains("MacStreamRelauncher.relaunch()"))
    #expect(relauncherSource.contains("/usr/bin/open"))
    #expect(relauncherSource.contains("NSApplication.shared.terminate(nil)"))
}

@Test
func studioKeepsFrequentControlsInBottomDeck() throws {
    let appURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStream/App/MacStreamApp.swift")
    let contentURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStream/Views/ContentView.swift")
    let studioURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStream/Views/StudioView.swift")
    let controlURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStream/Views/StudioControlPanelView.swift")
    let directorURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStream/Views/DirectorPanelView.swift")
    let streamHealthURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStream/Views/StreamHealthView.swift")
    let capturePreflightURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStream/Views/CapturePreflightView.swift")
    let settingsURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStream/Views/SettingsView.swift")
    let checklistURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStream/Views/SetupChecklistView.swift")
    let destinationURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStream/Views/DestinationView.swift")
    let sourceRackURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStream/Views/SourceRackView.swift")
    let storeURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStreamCore/Stores/StudioStore.swift")
    let appSource = try String(contentsOf: appURL, encoding: .utf8)
    let contentSource = try String(contentsOf: contentURL, encoding: .utf8)
    let studioSource = try String(contentsOf: studioURL, encoding: .utf8)
    let controlSource = try String(contentsOf: controlURL, encoding: .utf8)
    let directorSource = try String(contentsOf: directorURL, encoding: .utf8)
    let streamHealthSource = try String(contentsOf: streamHealthURL, encoding: .utf8)
    let capturePreflightSource = try String(contentsOf: capturePreflightURL, encoding: .utf8)
    let settingsSource = try String(contentsOf: settingsURL, encoding: .utf8)
    let checklistSource = try String(contentsOf: checklistURL, encoding: .utf8)
    let destinationSource = try String(contentsOf: destinationURL, encoding: .utf8)
    let sourceRackSource = try String(contentsOf: sourceRackURL, encoding: .utf8)
    let storeSource = try String(contentsOf: storeURL, encoding: .utf8)

    let controlIndex = try #require(studioSource.range(of: "StudioControlPanelView(store: store)")?.lowerBound)
    let previewCanvasIndex = try #require(studioSource.range(of: "PreviewCanvasView(")?.lowerBound)
    let inspectorIndex = try #require(studioSource.range(of: "private struct InspectorView")?.lowerBound)
    let checklistIndex = try #require(studioSource.range(of: "SetupChecklistView(store: store)")?.lowerBound)
    let destinationIndex = try #require(studioSource.range(of: "DestinationView(store: store)")?.lowerBound)
    let previewColumnIndex = try #require(studioSource.range(of: "private struct PreviewColumnView")?.lowerBound)
    let studioRootSource = String(studioSource[..<previewColumnIndex])
    let settingsDestinationIndex = try #require(settingsSource.range(of: "Section(\"Destination\")")?.lowerBound)
    let settingsDestinationModeIndex = try #require(settingsSource.range(of: "Picker(\"Mode\", selection: destinationMode)")?.lowerBound)
    let settingsRTMPDestinationIndex = try #require(settingsSource.range(of: "if store.destination.mode == .rtmp {")?.lowerBound)
    let destinationNameIndex = try #require(settingsSource.range(of: "TextField(\"Name\"")?.lowerBound)
    let destinationSecureIndex = try #require(settingsSource.range(of: "SecureField(\"RTMP URL / stream key\"")?.lowerBound)

    #expect(previewColumnIndex < previewCanvasIndex)
    #expect(previewCanvasIndex < controlIndex)
    #expect(controlIndex < inspectorIndex)
    #expect(controlIndex < destinationIndex)
    #expect(controlIndex < checklistIndex)
    #expect(checklistIndex < destinationIndex)
    #expect(settingsDestinationIndex < settingsDestinationModeIndex)
    #expect(settingsDestinationModeIndex < settingsRTMPDestinationIndex)
    #expect(settingsRTMPDestinationIndex < destinationNameIndex)
    #expect(destinationNameIndex < destinationSecureIndex)
    #expect(studioSource.contains("@SceneStorage(\"MacStream.StudioView.isInspectorCollapsed\")"))
    #expect(studioSource.contains("InspectorRailView(store: store)"))
    #expect(studioSource.contains(".frame(width: 52)"))
    #expect(studioSource.contains(".frame(width: 372)"))
    #expect(studioSource.contains("|| hasStreamFailure"))
    #expect(studioSource.contains("&& !hasStreamFailure"))
    #expect(studioSource.contains("|| store.recordingState.isFailed"))
    #expect(studioSource.contains(".toolbar {"))
    #expect(studioSource.contains("ToolbarItem(placement: .primaryAction)"))
    #expect(studioSource.contains("isInspectorCollapsed.toggle()"))
    #expect(studioSource.contains(".animation(.snappy(duration: 0.18), value: isInspectorCollapsed)"))
    #expect(studioSource.contains("VStack(spacing: 14)"))
    #expect(studioSource.contains("InspectorHeaderView(store: store)"))
    #expect(studioSource.contains("SessionStatusStripView(store: store)"))
    #expect(studioSource.contains("ScrollViewReader { scrollProxy in"))
    #expect(studioSource.contains(".id(InspectorPanelID.detailTop)"))
    #expect(studioSource.contains(".onChange(of: store.shouldShowSetupChecklist)"))
    #expect(studioSource.contains("scrollProxy.scrollTo(InspectorPanelID.detailTop, anchor: .top)"))
    #expect(studioSource.contains("private enum InspectorPanelID: Hashable"))
    #expect(studioSource.contains("PreviewColumnView(store: store)"))
    #expect(studioSource.contains("DirectorPanelView(store: store)"))
    #expect(studioSource.contains("LazyVStack(alignment: .leading, spacing: 14)"))
    #expect(studioSource.contains("StudioControlPanelView(store: store)"))
    #expect(!studioSource.contains("StudioNavigationPanelView"))
    #expect(!contentSource.contains("NavigationSplitView"))
    #expect(!contentSource.contains("SidebarView(store: store)"))
    #expect(!studioRootSource.contains("store.latestSignals"))
    #expect(!studioRootSource.contains("store.effectivePerformanceMode.previewCaptureConfiguration"))
    #expect(!studioRootSource.contains("store.captureReport"))
    #expect(studioSource.contains("if store.shouldShowSetupChecklist"))
    #expect(studioSource.contains("setupDetailPanels"))
    #expect(studioSource.contains("operatingPanels"))
    #expect(studioSource.contains("switch store.nextSetupChecklistItem?.id"))
    #expect(studioSource.contains("case .capture:"))
    #expect(studioSource.contains("case .destination:"))
    #expect(studioSource.contains("case .sources:"))
    #expect(studioSource.contains("case .scene, nil:"))
    #expect(!studioSource.contains("SetupAssistantView"))
    #expect(studioSource.contains("private struct InspectorRailView"))
    #expect(studioSource.contains("private struct InspectorHeaderView"))
    #expect(studioSource.contains(".help(isInspectorCollapsed ? \"Show sidebar\" : \"Hide sidebar\")"))
    #expect(!contentSource.contains(".toolbar"))
    #expect(controlSource.contains("ViewThatFits(in: .horizontal)"))
    #expect(controlSource.contains("private var horizontalControls"))
    #expect(controlSource.contains("private var wrappedControls"))
    #expect(!controlSource.contains("OperatorDeckSection"))
    #expect(controlSource.contains("Picker(\"Scene\", selection: sceneSelectionBinding)"))
    #expect(controlSource.contains("sceneDeckTitle(for: scene)"))
    #expect(controlSource.contains("private var sceneSelectionBinding: Binding<StudioScene.ID>"))
    #expect(controlSource.contains("ForEach(store.scenes)"))
    #expect(controlSource.contains("store.sceneSelectionBlockedReason(for: scene)"))
    #expect(controlSource.contains("store.canSelectScene(scene)"))
    #expect(controlSource.contains("store.selectScene(scene)"))
    #expect(controlSource.contains(".disabled(!store.canSelectScene(scene))"))
    #expect(controlSource.contains(".help(store.sceneSelectionBlockedReason(for: scene) ?? scene.subtitle)"))
    #expect(controlSource.contains("Picker(\"Director Mode\", selection: $store.directorMode)"))
    #expect(controlSource.contains("@AppStorage(\"performanceMode\")"))
    #expect(controlSource.contains("Picker(\"Performance\", selection: performanceModeBinding)"))
    #expect(controlSource.contains("ForEach(StudioPerformanceMode.allCases)"))
    #expect(controlSource.contains("Menu {"))
    #expect(controlSource.contains("performanceMenuTitle"))
    #expect(controlSource.contains("store.effectivePerformanceMode.title"))
    #expect(controlSource.contains("private var performanceModeBinding: Binding<String>"))
    #expect(controlSource.contains("performanceModeRaw = newValue"))
    #expect(controlSource.contains("store.updatePreferences(preferences)"))
    #expect(!controlSource.contains("var onCollapse"))
    #expect(!controlSource.contains("onCollapse()"))
    #expect(!controlSource.contains(".help(\"Hide controls\")"))
    #expect(controlSource.contains("store.startStream()"))
    #expect(controlSource.contains("store.stopStream()"))
    #expect(controlSource.contains("store.startRecording()"))
    #expect(controlSource.contains("store.stopRecording()"))
    #expect(!controlSource.contains("store.scanCaptureDevices()"))
    #expect(!controlSource.contains("store.captureReadiness.title"))
    #expect(!controlSource.contains("store.captureReadiness.detail"))
    #expect(!controlSource.contains("store.sourceSetupDetail"))
    #expect(controlSource.contains(".lineLimit(2)"))
    #expect(controlSource.contains(".fixedSize(horizontal: false, vertical: true)"))
    #expect(controlSource.contains("store.streamStartBlockedReason"))
    #expect(controlSource.contains("store.recordingStartBlockedReason"))
    #expect(controlSource.contains("primaryActionBlockerDetail"))
    #expect(controlSource.contains("exclamationmark.triangle.fill"))
    #expect(!controlSource.contains("MacStreamRelauncher.relaunch()"))
    #expect(!controlSource.contains("Label(\"Reopen MacStream\""))
    #expect(controlSource.contains("if store.recordingState == .recording { return \"Stop Rec\" }"))
    #expect(studioSource.contains("if store.shouldShowSetupChecklist { return \"checklist.checked\" }"))
    #expect(controlSource.contains("return \"Check Endpoint\""))
    #expect(controlSource.contains("return \"Stop Check\""))
    #expect(controlSource.contains("return \"Cancel Check\""))
    #expect(controlSource.contains("return \"Stop Rec\""))
    #expect(controlSource.contains("return \"Cancel Rec\""))
    #expect(controlSource.contains(".minimumScaleFactor(0.78)"))
    #expect(controlSource.contains("Validate RTMP endpoint reachability"))
    #expect(appSource.contains("return \"Check RTMP Endpoint\""))
    #expect(appSource.contains("return \"Stop Endpoint Check\""))
    #expect(appSource.contains("return \"Cancel Endpoint Check\""))
    #expect(appSource.contains("Window(\"MacStream\", id: \"studio\")"))
    #expect(appSource.contains("intelligenceProvider: RuleBasedLocalIntelligenceProvider()"))
    #expect(!appSource.contains("WindowGroup"))
    #expect(appSource.contains("@AppStorage(\"defaultSceneKind\")"))
    #expect(appSource.contains("@AppStorage(\"setupPrompt\")"))
    #expect(appSource.contains("@AppStorage(\"destinationMode\")"))
    #expect(appSource.contains("@AppStorage(\"destinationName\")"))
    #expect(appSource.contains("@AppStorage(\"sourceConfiguration\")"))
    #expect(appSource.contains("@AppStorage(\"screenCaptureTargetPreference\")"))
    #expect(appSource.contains("@Environment(\\.scenePhase)"))
    #expect(appSource.contains("applyLaunchSetupDefaultsIfNeeded()"))
    #expect(appSource.contains("applySavedDestination()"))
    #expect(appSource.contains("applySavedSourceConfiguration()"))
    #expect(appSource.contains("applySavedScreenCaptureTargetPreference()"))
    #expect(appSource.contains("store.applyLaunchSetupDefaults("))
    #expect(appSource.contains("store.applySavedSetupPrompt(newValue)"))
    #expect(appSource.contains("scheduleDestinationSave(newDestination)"))
    #expect(appSource.contains("scheduleSourceConfigurationSave(newConfiguration)"))
    #expect(appSource.contains("saveScreenCaptureTargetPreference(newTarget)"))
    #expect(appSource.contains("destinationSaveTask?.cancel()"))
    #expect(appSource.contains("sourceConfigurationSaveTask?.cancel()"))
    #expect(appSource.contains("flushPendingPersistence()"))
    #expect(appSource.contains(".onDisappear"))
    #expect(appSource.contains("guard newScenePhase != .active else { return }"))
    #expect(appSource.contains("destinationSaveTask = nil"))
    #expect(appSource.contains("sourceConfigurationSaveTask = nil"))
    #expect(appSource.contains("persistenceDebounceDuration: Duration = .milliseconds(350)"))
    #expect(appSource.contains("try? await Task.sleep(for: Self.persistenceDebounceDuration)"))
    #expect(appSource.contains("MacStreamDestinationKeychain.loadRTMPURL()"))
    #expect(appSource.contains("store.reportPersistenceFailure"))
    #expect(appSource.contains("SettingsView(store: store)"))
    #expect(directorSource.contains("private var compactDirectorPanel"))
    #expect(directorSource.contains("private func expandedDirectorPanel(for recommendation: DirectorRecommendation)"))
    #expect(directorSource.contains("Label(\"No cue pending\", systemImage: \"checkmark.circle.fill\")"))
    #expect(directorSource.contains("private var directorActionButtons"))
    #expect(directorSource.contains("store.canApplyRecommendation"))
    #expect(directorSource.contains("store.recommendationActionBlockedReason"))
    #expect(streamHealthSource.contains("Label(healthTitle, systemImage: transportSymbol)"))
    #expect(streamHealthSource.contains("case .preview:"))
    #expect(streamHealthSource.contains("\"Preview\""))
    #expect(capturePreflightSource.contains("store.scanCaptureDevices()"))
    #expect(capturePreflightSource.contains(".disabled(!store.canScanCaptureDevices)"))
    #expect(capturePreflightSource.contains("store.captureScanBlockedReason ?? \"Check capture permissions\""))
    #expect(capturePreflightSource.contains("requiresRelaunchForRequiredCapturePermission"))
    #expect(capturePreflightSource.contains("!store.shouldShowSetupChecklist"))
    #expect(capturePreflightSource.contains("Label(\"Reopen MacStream\""))
    #expect(!capturePreflightSource.contains("showDeviceDetails"))
    #expect(capturePreflightSource.contains("CapturePermissionRow.rows"))
    #expect(capturePreflightSource.contains("permissionRows(rows)"))
    #expect(!capturePreflightSource.contains("attentionDevices"))
    #expect(!capturePreflightSource.contains("deviceRows(for: attentionDevices)"))
    #expect(!capturePreflightSource.contains("DisclosureGroup"))
    #expect(!capturePreflightSource.contains("Device details"))
    #expect(!capturePreflightSource.contains("Picker(\"Screen target\""))
    #expect(settingsSource.contains("Section(\"Startup\")"))
    #expect(settingsSource.contains("@AppStorage(\"defaultSceneKind\")"))
    #expect(settingsSource.contains("Picker(\"Startup scene\""))
    #expect(settingsSource.contains("Section(\"Destination\")"))
    #expect(settingsSource.contains("Picker(\"Mode\", selection: destinationMode)"))
    #expect(settingsSource.contains("TextField(\"Name\", text: $store.destination.name)"))
    #expect(settingsSource.contains("SecureField(\"RTMP URL / stream key\""))
    #expect(settingsSource.contains("private var destinationMode: Binding<StreamDestinationMode>"))
    #expect(settingsSource.contains("Section(\"Setup Rules\")"))
    #expect(settingsSource.contains("@AppStorage(\"setupPrompt\")"))
    #expect(settingsSource.contains("TextField(\"Stream description\""))
    #expect(settingsSource.contains("store.generateSetupPlan()"))
    #expect(settingsSource.contains("Section(\"Stream Behavior\")"))
    #expect(settingsSource.contains("setupPromptBinding"))
    #expect(settingsSource.contains("recordWhileStreamingBinding"))
    #expect(settingsSource.contains("preferences.recordWhileStreaming = newValue"))
    #expect(settingsSource.contains("preferences.directorCountdownSeconds = normalizedSeconds"))
    #expect(!settingsSource.contains("Picker(\"Performance\""))
    #expect(!settingsSource.contains("@AppStorage(\"performanceMode\")"))
    #expect(storeSource.contains("public func applySavedDestination(_ savedDestination: StreamDestination)"))
    #expect(storeSource.contains("public var sourceConfiguration: [StudioSourceConfiguration]"))
    #expect(storeSource.contains("public func applySavedSourceConfiguration(_ savedConfiguration: [StudioSourceConfiguration])"))
    #expect(storeSource.contains("public private(set) var screenCaptureTargetPreference: ScreenCaptureTarget?"))
    #expect(storeSource.contains("public func applySavedScreenCaptureTargetPreference(_ target: ScreenCaptureTarget?)"))
    #expect(destinationSource.contains("Label(store.destination.safeDisplayDetail, systemImage: store.destination.mode.symbolName)"))
    #expect(destinationSource.contains("SettingsLink"))
    #expect(destinationSource.contains("Label(\"Configure\", systemImage: \"gearshape\")"))
    #expect(destinationSource.contains("destinationDetailTint"))
    #expect(!destinationSource.contains("TextField(\"Name\", text: $store.destination.name)"))
    #expect(!destinationSource.contains("SecureField(\"RTMP URL / stream key\""))
    #expect(storeSource.contains("public var canScanCaptureDevices"))
    #expect(storeSource.contains("captureScanBlockedReason == nil"))
    #expect(storeSource.contains("Stop preview, stream, or recording before checking capture devices."))
    #expect(storeSource.contains("!isStreamStopping"))
    #expect(storeSource.contains("!isRecordingStopping"))
    #expect(!destinationSource.contains("store.startRecording()"))
    #expect(!destinationSource.contains("store.stopRecording()"))
    #expect(!destinationSource.contains("recordingActionTitle"))
    #expect(destinationSource.contains("Last Recording"))
    #expect(checklistSource.contains("Preflight"))
    #expect(checklistSource.contains("ProgressView(value: store.setupProgressFraction)"))
    #expect(checklistSource.contains("store.nextSetupChecklistItem"))
    #expect(checklistSource.contains("SetupChecklistRow"))
    #expect(checklistSource.contains("borderedProminent"))
    #expect(checklistSource.contains("store.shouldShowSetupChecklist"))
    #expect(checklistSource.contains("store.setupChecklistItems"))
    #expect(checklistSource.contains("store.selectRecommendedStartingScene()"))
    #expect(checklistSource.contains("store.scanCaptureDevices()"))
    #expect(checklistSource.contains("MacStreamRelauncher.relaunch()"))
    #expect(checklistSource.contains("store.setDestinationMode(.preview)"))
    #expect(checklistSource.contains("store.enableRecommendedSources()"))
    #expect(checklistSource.contains("Fix Needed Sources"))
    #expect(checklistSource.contains("store.missingRequiredCapturePermissionKinds"))
    #expect(checklistSource.contains("store.promptableRequiredCapturePermissionKinds"))
    #expect(checklistSource.contains("store.blockedRequiredCapturePermissionKinds"))
    #expect(checklistSource.contains("store.missingRequiredCaptureDeviceKinds"))
    #expect(checklistSource.contains("CapturePermissionActions.requestAccess"))
    #expect(checklistSource.contains("CapturePermissionActions.openSettings(for: blockedKind)"))
    #expect(checklistSource.contains("CapturePermissionActions.openSettings(for: .display)"))
    #expect(!controlSource.contains("store.setupRole(for: source.kind)"))
    #expect(!controlSource.contains("SourceStatusRow("))
    #expect(sourceRackSource.contains(".disabled(!store.canToggleSource(source))"))
    #expect(sourceRackSource.contains(".disabled(!store.canAdjustSourceLevel(source))"))
    #expect(sourceRackSource.contains("@SceneStorage(\"MacStream.SourceRackView.showMoreSources\")"))
    #expect(sourceRackSource.contains("sourceRows(for: primarySources)"))
    #expect(sourceRackSource.contains("DisclosureGroup(isExpanded: $showMoreSources)"))
    #expect(sourceRackSource.contains("Label(\"More sources\", systemImage: \"ellipsis.circle\")"))
    #expect(sourceRackSource.contains("store.setupRole(for: source.kind)"))
    #expect(sourceRackSource.contains("case .required, .recommended:"))
    #expect(sourceRackSource.contains("case .optional, .unused:"))
    #expect(sourceRackSource.contains("sourceToggleHelp(for: source)"))
    #expect(sourceRackSource.contains("sourceLevelHelp(for: source)"))
    #expect(sourceRackSource.contains("Switch scenes or stop capture before turning off a required source"))
    #expect(sourceRackSource.contains("Switch scenes or stop capture before adjusting a required source"))
    #expect(sourceRackSource.contains("refreshDevicesButton"))
    #expect(sourceRackSource.contains("store.scanCaptureDevices()"))
    #expect(sourceRackSource.contains("private func deviceSelector(for kind: SourceKind)"))
    #expect(sourceRackSource.contains("store.availableCameraDevices"))
    #expect(sourceRackSource.contains("store.availableMicrophoneDevices"))
    #expect(sourceRackSource.contains("store.availableScreenCaptureTargets"))
    #expect(sourceRackSource.contains("store.selectCameraDevice(id: $0)"))
    #expect(sourceRackSource.contains("store.selectMicrophoneDevice(id: $0)"))
    #expect(sourceRackSource.contains("store.selectScreenCaptureTarget(target)"))
    #expect(sourceRackSource.contains("store.canSelectInputDevice"))
}

@Test
func screenPreviewDoesNotRequestScreenRecordingPermissionPassively() throws {
    let previewURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStream/NativePreview/ScreenCapturePreviewView.swift")
    let canvasURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStream/Views/PreviewCanvasView.swift")
    let studioURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStream/Views/StudioView.swift")
    let previewSource = try String(contentsOf: previewURL, encoding: .utf8)
    let canvasSource = try String(contentsOf: canvasURL, encoding: .utf8)
    let studioSource = try String(contentsOf: studioURL, encoding: .utf8)

    #expect(!previewSource.contains("CGRequestScreenCaptureAccess"))
    #expect(previewSource.contains("CGPreflightScreenCaptureAccess()"))
    #expect(previewSource.contains("configuration.queueDepth = previewConfiguration.queueDepth"))
    #expect(canvasSource.contains("isScreenCaptureReady"))
    #expect(canvasSource.contains("Screen Capture Not Ready"))
    #expect(studioSource.contains("isScreenCaptureReady: store.captureReport.isScreenCapturePermissionGranted"))
}

@Test
func signalSamplingDoesNotRequestScreenRecordingPermissionPassively() throws {
    let signalURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStreamCore/Services/SignalProvider.swift")
    let signalSource = try String(contentsOf: signalURL, encoding: .utf8)

    #expect(!signalSource.contains("CGRequestScreenCaptureAccess"))
    #expect(signalSource.contains("CGPreflightScreenCaptureAccess()"))
    #expect(signalSource.contains("stateQueue.async"))
    #expect(signalSource.contains("applyMonitorsForCurrentState(configuration:"))
    #expect(signalSource.contains("shouldContinueStartingEngine()"))
}

@Test
func cameraPreviewDoesNotRequestCameraPermissionPassively() throws {
    let previewURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStream/NativePreview/CameraPreviewView.swift")
    let canvasURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStream/Views/PreviewCanvasView.swift")
    let studioURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStream/Views/StudioView.swift")
    let captureURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStream/Views/CapturePreflightView.swift")
    let permissionActionsURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStream/Support/CapturePermissionActions.swift")
    let previewSource = try String(contentsOf: previewURL, encoding: .utf8)
    let canvasSource = try String(contentsOf: canvasURL, encoding: .utf8)
    let studioSource = try String(contentsOf: studioURL, encoding: .utf8)
    let captureSource = try String(contentsOf: captureURL, encoding: .utf8)
    let permissionActionsSource = try String(contentsOf: permissionActionsURL, encoding: .utf8)

    #expect(!previewSource.contains("requestAccess"))
    #expect(previewSource.contains("authorizationStatus(for: .video)"))
    #expect(canvasSource.contains("isCameraCaptureReady"))
    #expect(canvasSource.contains("Camera Capture Not Ready"))
    #expect(studioSource.contains("isCameraCaptureReady: store.captureReport.hasGrantedPermission(for: .camera)"))
    #expect(captureSource.contains("CapturePermissionRow.rows"))
    #expect(captureSource.contains("CapturePermissionActions.requestAccess(for: row.requestKind, store: store)"))
    #expect(!captureSource.contains("CapturePermissionActions.requestAccess(for: device.kind, store: store)"))
    #expect(permissionActionsSource.contains("mediaType = .video"))
    #expect(permissionActionsSource.contains("mediaType = .audio"))
    #expect(permissionActionsSource.contains("AVCaptureDevice.requestAccess(for: mediaType)"))
}

@Test
func cameraEnhancementControlsStayWithCameraSourceAndPreviewOnly() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let modelsSource = try String(contentsOf: root.appendingPathComponent("Sources/MacStreamCore/Models/StudioModels.swift"), encoding: .utf8)
    let storeSource = try String(contentsOf: root.appendingPathComponent("Sources/MacStreamCore/Stores/StudioStore.swift"), encoding: .utf8)
    let appSource = try String(contentsOf: root.appendingPathComponent("Sources/MacStream/App/MacStreamApp.swift"), encoding: .utf8)
    let previewSource = try String(contentsOf: root.appendingPathComponent("Sources/MacStream/NativePreview/CameraPreviewView.swift"), encoding: .utf8)
    let canvasSource = try String(contentsOf: root.appendingPathComponent("Sources/MacStream/Views/PreviewCanvasView.swift"), encoding: .utf8)
    let studioSource = try String(contentsOf: root.appendingPathComponent("Sources/MacStream/Views/StudioView.swift"), encoding: .utf8)
    let sourceRackSource = try String(contentsOf: root.appendingPathComponent("Sources/MacStream/Views/SourceRackView.swift"), encoding: .utf8)

    #expect(modelsSource.contains("public struct CameraEnhancementSettings"))
    #expect(modelsSource.contains("public enum CameraPreviewRotation"))
    #expect(modelsSource.contains("cameraEnhancements: CameraEnhancementSettings = CameraEnhancementSettings()"))
    #expect(storeSource.contains("public func updateCameraEnhancements"))
    #expect(appSource.contains("@AppStorage(\"cameraEnhancementSettings\")"))
    #expect(appSource.contains("loadCameraEnhancementSettings()"))
    #expect(appSource.contains("saveCameraEnhancementSettings(newSettings)"))
    #expect(previewSource.contains("var cameraEnhancements = CameraEnhancementSettings()"))
    #expect(previewSource.contains("CIFilter(name: \"CIColorControls\")"))
    #expect(previewSource.contains("device.exposureMode = .continuousAutoExposure"))
    #expect(previewSource.contains("device.focusMode = .continuousAutoFocus"))
    #expect(previewSource.contains("device.whiteBalanceMode = .continuousAutoWhiteBalance"))
    #expect(previewSource.contains("previewLayer.setAffineTransform(transform)"))
    #expect(canvasSource.contains("cameraEnhancements: cameraEnhancements"))
    #expect(studioSource.contains("cameraEnhancements: store.preferences.cameraEnhancements"))
    #expect(sourceRackSource.contains("CameraEnhancementControls("))
    #expect(sourceRackSource.contains("Toggle(\"Mirror\""))
    #expect(sourceRackSource.contains("Toggle(\"Auto Light\""))
    #expect(sourceRackSource.contains("Picker(\"Rotation\""))
}

@Test
func technicalRisksSeparateSmoothMicFromVirtualMicrophoneReleasePath() throws {
    let docsURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("docs/technical-risks.md")
    let docs = try String(contentsOf: docsURL, encoding: .utf8)

    #expect(docs.contains("JoyCast-style mic polish"))
    #expect(docs.contains("selectable virtual microphone"))
    #expect(docs.contains("MacStream's MVP should first process microphone audio only inside its own recording and RTMP paths."))
    #expect(docs.contains("`AVAudioEngine` or Audio Unit graph"))
    #expect(docs.contains("before exposing a main-window Smooth Mic toggle"))
}

@Test
func packageManifestKeepsHeavyAIAndRTMPDependenciesOptIn() throws {
    let manifestURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Package.swift")
    let manifest = try String(contentsOf: manifestURL, encoding: .utf8)

    #expect(manifest.contains("MAC_STREAM_ENABLE_HAISHINKIT"))
    #expect(manifest.contains("MAC_STREAM_ENABLE_MLX"))
    #expect(manifest.contains("HaishinKit.swift"))
    #expect(manifest.contains("mlx-swift-lm"))
    #expect(manifest.contains("MLXLLM"))
    #expect(manifest.contains("MLXLMCommon"))
    #expect(manifest.contains("MLXHuggingFace"))
}

@Test
func releaseAutomationDefinesSignedNotarizedMacPipeline() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let ciURL = root.appendingPathComponent(".github/workflows/ci.yml")
    let releaseURL = root.appendingPathComponent(".github/workflows/release.yml")
    let packageScriptURL = root.appendingPathComponent("script/package_macos_app.sh")
    let entitlementsURL = root.appendingPathComponent("Resources/Entitlements/MacStream.Release.entitlements")
    let infoPlistURL = root.appendingPathComponent("Resources/Info.plist")
    let sourceIconURL = root.appendingPathComponent("Resources/AppIcon/MacStream-AppIcon-Source.png")
    let iconURL = root.appendingPathComponent("Resources/AppIcon/MacStream.icns")
    let iconReadmeURL = root.appendingPathComponent("Resources/AppIcon/README.md")
    let docsURL = root.appendingPathComponent("docs/releasing.md")
    let ci = try String(contentsOf: ciURL, encoding: .utf8)
    let release = try String(contentsOf: releaseURL, encoding: .utf8)
    let packageScript = try String(contentsOf: packageScriptURL, encoding: .utf8)
    let entitlements = try String(contentsOf: entitlementsURL, encoding: .utf8)
    let infoPlist = try String(contentsOf: infoPlistURL, encoding: .utf8)
    let iconReadme = try String(contentsOf: iconReadmeURL, encoding: .utf8)
    let docs = try String(contentsOf: docsURL, encoding: .utf8)

    #expect(FileManager.default.fileExists(atPath: sourceIconURL.path))
    #expect(FileManager.default.fileExists(atPath: iconURL.path))
    #expect(iconReadme.contains("MacStream-AppIcon-Source.png"))
    #expect(ci.contains("runs-on: macos-26"))
    #expect(ci.contains("FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: \"true\""))
    #expect(ci.contains("swift test"))
    #expect(ci.contains("swift build -c release --arch arm64"))
    #expect(ci.contains("MAC_STREAM_ENABLE_HAISHINKIT=1 swift build -c release --arch arm64"))
    #expect(ci.contains("MAC_STREAM_ENABLE_MLX=1 swift build -c release --arch arm64"))
    #expect(ci.contains("MAC_STREAM_REQUIRE_HARDENED_RUNTIME: \"1\""))
    #expect(ci.contains("actions/checkout@v6"))
    #expect(ci.contains("actions/upload-artifact@v7"))
    #expect(release.contains("runs-on: macos-26"))
    #expect(release.contains("FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: \"true\""))
    #expect(release.contains("actions/checkout@v6"))
    #expect(release.contains("actions/upload-artifact@v7"))
    #expect(release.contains("MAC_STREAM_MACOS_CERTIFICATE_P12_BASE64"))
    #expect(release.contains("MAC_STREAM_MACOS_CERTIFICATE_PASSWORD"))
    #expect(release.contains("MAC_STREAM_CODESIGN_IDENTITY"))
    #expect(release.contains("MAC_STREAM_APPLE_ID"))
    #expect(release.contains("MAC_STREAM_APPLE_TEAM_ID"))
    #expect(release.contains("MAC_STREAM_APP_SPECIFIC_PASSWORD"))
    #expect(release.contains("security import \"$certificate_path\""))
    #expect(release.contains("MAC_STREAM_REQUIRE_DEVELOPER_ID: \"1\""))
    #expect(release.contains("MAC_STREAM_REQUIRE_HARDENED_RUNTIME: \"1\""))
    #expect(release.contains("xcrun notarytool submit"))
    #expect(release.contains("xcrun stapler staple"))
    #expect(release.contains("spctl -a -vv --type execute"))
    #expect(release.contains("shasum -a 256"))
    #expect(release.contains("gh release create"))
    #expect(packageScript.contains("--options runtime --entitlements \"$ENTITLEMENTS\""))
    #expect(packageScript.contains("Authority=Developer ID Application:"))
    #expect(infoPlist.contains("CFBundleIconFile"))
    #expect(infoPlist.contains("LSApplicationCategoryType"))
    #expect(entitlements.contains("com.apple.security.device.camera"))
    #expect(entitlements.contains("com.apple.security.device.audio-input"))
    #expect(docs.contains("MacStream does not ship Sparkle or another in-app updater yet."))
}

@Test
func keychainPersistenceReportsFailuresToApp() throws {
    let keychainURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStream/Support/MacStreamDestinationKeychain.swift")
    let appURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStream/App/MacStreamApp.swift")
    let keychainSource = try String(contentsOf: keychainURL, encoding: .utf8)
    let appSource = try String(contentsOf: appURL, encoding: .utf8)

    #expect(keychainSource.contains("static func saveRTMPURL(_ value: String) -> Bool"))
    #expect(keychainSource.contains("static func deleteRTMPURL() -> Bool"))
    #expect(keychainSource.contains("return SecItemAdd(item as CFDictionary, nil) == errSecSuccess"))
    #expect(appSource.contains("if !MacStreamDestinationKeychain.saveRTMPURL(destination.rtmpURL)"))
    #expect(appSource.contains("if !MacStreamDestinationKeychain.deleteRTMPURL()"))
    #expect(appSource.contains("store.reportPersistenceFailure"))
}

@Test
func studioStoreKeepsRuntimeStateReadOnlyOutsideStore() throws {
    let storeURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStreamCore/Stores/StudioStore.swift")
    let source = try String(contentsOf: storeURL, encoding: .utf8)
    let readOnlyRuntimeState = [
        "streamState",
        "streamTransport",
        "recordingState",
        "lastRecordingURL",
        "health",
        "systemPressure",
        "latestSignals",
        "recommendation",
        "events",
        "clipMarkers",
        "latestClipExportURL",
        "latestSessionReportURL",
        "setupSummary",
        "isGeneratingSetupPlan",
        "isStreamStopping",
        "isRecordingStopping",
        "localIntelligenceStatus",
        "directorProfile",
        "preferences",
        "effectivePerformanceMode",
        "captureReport",
        "isScanningCapture",
        "hasRunInitialCaptureScan",
        "selectedCameraDeviceID",
        "cameraDeviceIDPreference",
        "selectedMicrophoneDeviceID",
        "microphoneDeviceIDPreference"
    ]

    for property in readOnlyRuntimeState {
        #expect(source.contains("public private(set) var \(property)"))
    }
}

@Test
func speakingOverQuietScreenCuesFace() {
    var engine = DirectorEngine()
    let snapshot = SignalSnapshot(
        isSpeaking: true,
        speechLevel: 0.72,
        screenMotion: 0.08,
        hasFace: true,
        activeApplication: "Notes"
    )

    let recommendation = engine.evaluate(snapshot: snapshot, currentScene: .screenAndFace, mode: .suggest)

    #expect(recommendation?.target == .face)
}

@Test
func activeScreenWithoutSpeechCuesScreenOnly() {
    var engine = DirectorEngine()
    let snapshot = SignalSnapshot(
        isSpeaking: false,
        speechLevel: 0.05,
        screenMotion: 0.7,
        hasFace: true,
        activeApplication: "Xcode"
    )

    let recommendation = engine.evaluate(snapshot: snapshot, currentScene: .face, mode: .suggest)

    #expect(recommendation?.target == .screenOnly)
}

@Test
func codingProfileKeepsSpeakingOverCodeInScreenAndFace() {
    var engine = DirectorEngine(profile: .coding)
    let snapshot = SignalSnapshot(
        isSpeaking: true,
        speechLevel: 0.68,
        screenMotion: 0.1,
        hasFace: true,
        activeApplication: "Xcode"
    )

    let recommendation = engine.evaluate(snapshot: snapshot, currentScene: .face, mode: .suggest)

    #expect(recommendation?.target == .screenAndFace)
}

@Test
func teachingProfileDefaultsBackToFace() {
    var engine = DirectorEngine(profile: .teaching)
    let snapshot = SignalSnapshot(
        isSpeaking: false,
        speechLevel: 0.04,
        screenMotion: 0.12,
        hasFace: true,
        activeApplication: "Keynote",
        idleSeconds: 5
    )

    let recommendation = engine.evaluate(snapshot: snapshot, currentScene: .screenOnly, mode: .suggest)

    #expect(recommendation?.target == .face)
}

@Test
func mutedMicWarningDoesNotForceSceneChange() {
    var engine = DirectorEngine()
    let snapshot = SignalSnapshot(
        isSpeaking: true,
        speechLevel: 0.8,
        screenMotion: 0.4,
        hasFace: true,
        activeApplication: "Xcode",
        isMicMuted: true
    )

    let recommendation = engine.evaluate(snapshot: snapshot, currentScene: .screenAndFace, mode: .suggest)

    #expect(recommendation?.target == .screenAndFace)
    #expect(recommendation?.urgency == .immediate)
}

@Test
func heldDirectorCueIsSuppressedUntilHoldExpires() {
    var engine = DirectorEngine()
    let now = Date()
    let snapshot = SignalSnapshot(
        timestamp: now,
        isSpeaking: true,
        speechLevel: 0.72,
        screenMotion: 0.08,
        hasFace: true,
        activeApplication: "Notes"
    )

    let recommendation = engine.evaluate(snapshot: snapshot, currentScene: .screenAndFace, mode: .suggest)

    #expect(recommendation?.target == .face)

    engine.markCueHeld(recommendation!, at: now, duration: 5)

    let heldSnapshot = SignalSnapshot(
        timestamp: now.addingTimeInterval(2),
        isSpeaking: true,
        speechLevel: 0.72,
        screenMotion: 0.08,
        hasFace: true,
        activeApplication: "Notes"
    )

    #expect(engine.evaluate(snapshot: heldSnapshot, currentScene: .screenAndFace, mode: .suggest) == nil)

    let expiredSnapshot = SignalSnapshot(
        timestamp: now.addingTimeInterval(6),
        isSpeaking: true,
        speechLevel: 0.72,
        screenMotion: 0.08,
        hasFace: true,
        activeApplication: "Notes"
    )

    #expect(engine.evaluate(snapshot: expiredSnapshot, currentScene: .screenAndFace, mode: .suggest)?.target == .face)
}

@Test
func safetyCueBypassesHeldDirectorCue() {
    var engine = DirectorEngine()
    let now = Date()
    let recommendation = DirectorRecommendation(
        target: .face,
        confidence: 0.78,
        reason: "You are talking and the screen is quiet."
    )
    engine.markCueHeld(recommendation, at: now, duration: 30)

    let safetySnapshot = SignalSnapshot(
        timestamp: now.addingTimeInterval(2),
        isSpeaking: false,
        speechLevel: 0.04,
        screenMotion: 0.1,
        hasFace: true,
        activeApplication: "Keynote",
        isScreenFrozen: true
    )

    let safetyCue = engine.evaluate(snapshot: safetySnapshot, currentScene: .screenOnly, mode: .suggest)

    #expect(safetyCue?.target == .face)
    #expect(safetyCue?.urgency == .immediate)
}

@Test
func rtmpDestinationSplitsConnectionAndStreamName() throws {
    let destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_123"
    )

    #expect(destination.mode == .rtmp)

    let target = try destination.rtmpPublishTarget()

    #expect(target.connectionURL == "rtmps://live.example.com/app")
    #expect(target.streamName == "sk_live_123")
}

@Test
func rtmpDestinationPreservesStreamNameQueryTokens() throws {
    let destination = StreamDestination(
        name: "Token RTMP",
        rtmpURL: "rtmps://live.example.com/app/sk_live_123?token=abc123&expires=60"
    )

    let target = try destination.rtmpPublishTarget()

    #expect(target.connectionURL == "rtmps://live.example.com/app")
    #expect(target.streamName == "sk_live_123?token=abc123&expires=60")
    #expect(destination.safeDisplayDetail == "rtmps://live.example.com/app/****")
}

@Test
func defaultDestinationUsesPreviewSession() {
    let destination = StreamDestination()

    #expect(destination.isPreviewSession)
    #expect(destination.mode == .preview)
    #expect(destination.streamTransport(using: .endpointValidation) == .preview)
    #expect(destination.safeDisplayDetail == "Local preview session")
    #expect(throws: MediaPipelineError.self) {
        try destination.rtmpPublishTarget()
    }
}

@Test
func explicitRTMPDestinationDoesNotFallBackToPreviewForBlankURL() {
    let destination = StreamDestination(mode: .rtmp, name: "Twitch", rtmpURL: "")

    #expect(!destination.isPreviewSession)
    #expect(destination.mode == .rtmp)
    #expect(destination.safeDisplayDetail == "Invalid RTMP endpoint")
    #expect(!destination.isReadyToStart)
    #expect(destination.validationError == "Enter a valid RTMP or RTMPS URL.")
    #expect(throws: MediaPipelineError.self) {
        try destination.rtmpPublishTarget()
    }
}

@Test
func rtmpDestinationRedactsStreamKeyForDisplay() {
    let destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )

    #expect(!destination.isPreviewSession)
    #expect(destination.isReadyToStart)
    #expect(destination.validationError == nil)
    #expect(destination.safeDisplayDetail == "rtmps://live.example.com/app/****")
    #expect(!destination.safeDisplayDetail.contains("sk_live_secret"))
}

@Test
func rtmpDestinationRejectsMissingStreamKey() {
    let destination = StreamDestination(
        name: "Bad RTMP",
        rtmpURL: "rtmp://live.example.com/app"
    )

    #expect(throws: MediaPipelineError.self) {
        try destination.rtmpPublishTarget()
    }
}

@Test
func streamStateUsesEndpointValidationCopy() {
    #expect(StreamState.connecting.detail == "Validating RTMP endpoint")
    #expect(StreamState.live.detail == "Endpoint reachable")
}

@Test
func failedStreamStateIsNotLive() {
    #expect(!StreamState.failed("Bad endpoint").isLive)
    #expect(StreamState.failed("Bad endpoint").title == "Failed")
    #expect(StreamState.failed("Bad endpoint").detail == "Bad endpoint")
}

@Test
func recordingStateExposesFailureDetail() {
    let state = RecordingState.failed("Disk full")

    #expect(state.title == "Failed")
    #expect(state.detail == "Disk full")
    #expect(state.isFailed)
    #expect(!RecordingState.recording.isFailed)
}

@Test
func mediaPipelinesReportStreamTransport() {
    #expect(PreviewMediaPipeline().streamTransport == .preview)
    #if MAC_STREAM_HAS_HAISHINKIT
    #expect(SystemMediaPipeline().streamTransport == .rtmpPublish)
    #else
    #expect(SystemMediaPipeline().streamTransport == .endpointValidation)
    #endif
}

@Test
func systemMediaPipelineSkipsZeroLevelAudioSamples() {
    var configuration = MediaPipelineConfiguration()

    #expect(SystemMediaPipeline.shouldProcessSystemAudioSample(configuration: configuration))
    #expect(SystemMediaPipeline.shouldProcessMicrophoneAudioSample(configuration: configuration))
    #expect(SystemMediaPipeline.shouldProcessMicrophoneOutputSample(isActiveOutput: true, configuration: configuration))
    #expect(!SystemMediaPipeline.shouldProcessMicrophoneOutputSample(isActiveOutput: false, configuration: configuration))

    configuration.systemAudioLevel = 0
    #expect(!SystemMediaPipeline.shouldProcessSystemAudioSample(configuration: configuration))
    #expect(SystemMediaPipeline.shouldProcessMicrophoneAudioSample(configuration: configuration))
    #expect(SystemMediaPipeline.shouldProcessMicrophoneOutputSample(isActiveOutput: true, configuration: configuration))

    configuration.microphoneLevel = 0
    #expect(!SystemMediaPipeline.shouldProcessSystemAudioSample(configuration: configuration))
    #expect(!SystemMediaPipeline.shouldProcessMicrophoneAudioSample(configuration: configuration))
    #expect(!SystemMediaPipeline.shouldProcessMicrophoneOutputSample(isActiveOutput: true, configuration: configuration))
}

@Test
func systemMediaPipelinePublishesOnlyFromPublishingCaptureOutputs() {
    #expect(SystemMediaPipeline.shouldPublishStreamSample(isPublishingStream: true, hasPublisher: true))
    #expect(!SystemMediaPipeline.shouldPublishStreamSample(isPublishingStream: false, hasPublisher: true))
    #expect(!SystemMediaPipeline.shouldPublishStreamSample(isPublishingStream: true, hasPublisher: false))
    #expect(!SystemMediaPipeline.shouldPublishStreamSample(isPublishingStream: false, hasPublisher: false))

    #expect(SystemMediaPipeline.shouldPublishMicrophoneOutputSample(isPublishingOutput: true, hasPublisher: true))
    #expect(!SystemMediaPipeline.shouldPublishMicrophoneOutputSample(isPublishingOutput: false, hasPublisher: true))
    #expect(!SystemMediaPipeline.shouldPublishMicrophoneOutputSample(isPublishingOutput: true, hasPublisher: false))
    #expect(!SystemMediaPipeline.shouldPublishMicrophoneOutputSample(isPublishingOutput: false, hasPublisher: false))

    #expect(SystemMediaPipeline.shouldPublishCompositedVideoSample(sceneKind: .screenAndFace))
    #expect(!SystemMediaPipeline.shouldPublishCompositedVideoSample(sceneKind: .screenOnly))
    #expect(!SystemMediaPipeline.shouldPublishCompositedVideoSample(sceneKind: .face))
    #expect(!SystemMediaPipeline.shouldPublishCompositedVideoSample(sceneKind: .brb))
}

@Test
func microphonePermissionGrantStartsOnlyWhenSamplingIsStillRequested() {
    #expect(MicrophonePermissionStartPolicy.shouldStartEngine(isStartRequested: true, isPermissionGranted: true))
    #expect(!MicrophonePermissionStartPolicy.shouldStartEngine(isStartRequested: false, isPermissionGranted: true))
    #expect(!MicrophonePermissionStartPolicy.shouldStartEngine(isStartRequested: true, isPermissionGranted: false))
    #expect(!MicrophonePermissionStartPolicy.shouldStartEngine(isStartRequested: false, isPermissionGranted: false))
}

@Test
func screenMotionFrameSamplingGateDropsBurstFrames() {
    #expect(ScreenMotionFrameSamplingGate.shouldSample(now: 10, lastSampleTime: nil, interval: 0.25))
    #expect(!ScreenMotionFrameSamplingGate.shouldSample(now: 10.10, lastSampleTime: 10, interval: 0.25))
    #expect(ScreenMotionFrameSamplingGate.shouldSample(now: 10.25, lastSampleTime: 10, interval: 0.25))
    #expect(ScreenMotionFrameSamplingGate.shouldSample(now: 10.50, lastSampleTime: 10, interval: 0.25))
}

@Test
func screenMotionLumaSamplingUsesSmallFixedGrid() {
    #expect(ScreenMotionLumaSamplingGrid.columns == 16)
    #expect(ScreenMotionLumaSamplingGrid.rows == 9)
    #expect(ScreenMotionLumaSamplingGrid.capacity == 144)
}

@Test
func systemMediaPipelineCancelsRecordingWriterThatNeverStarted() {
    #expect(SystemMediaPipeline.shouldCancelWriterOnStop(status: .unknown))
    #expect(!SystemMediaPipeline.shouldCancelWriterOnStop(status: .writing))
    #expect(!SystemMediaPipeline.shouldCancelWriterOnStop(status: .completed))
    #expect(!SystemMediaPipeline.shouldCancelWriterOnStop(status: .failed))
    #expect(!SystemMediaPipeline.shouldCancelWriterOnStop(status: .cancelled))
}

@Test
func systemMediaPipelineBuildsUpdatedStreamConfigurationFromCaptureGeometry() {
    let geometry = MediaCaptureGeometry(sourceWidth: 3_024, sourceHeight: 1_964, maxVideoWidth: 1_920)
    let balanced = SystemMediaPipeline.streamConfiguration(
        geometry: geometry,
        mediaConfiguration: MediaPipelineConfiguration(maxVideoWidth: 1_920, framesPerSecond: 30, queueDepth: 5)
    )

    #expect(balanced.width == 1_920)
    #expect(balanced.height == 1_246)
    #expect(balanced.minimumFrameInterval == CMTime(value: 1, timescale: 30))
    #expect(balanced.queueDepth == 5)
    #expect(balanced.capturesAudio)

    let efficiency = SystemMediaPipeline.streamConfiguration(
        geometry: geometry,
        mediaConfiguration: MediaPipelineConfiguration(maxVideoWidth: 1_280, framesPerSecond: 24, queueDepth: 3, capturesSystemAudio: false)
    )

    #expect(efficiency.width == 1_280)
    #expect(efficiency.height == 830)
    #expect(efficiency.minimumFrameInterval == CMTime(value: 1, timescale: 24))
    #expect(efficiency.queueDepth == 3)
    #expect(!efficiency.capturesAudio)
}

@Test
func systemMediaPipelineSkipsStreamReconfigurationForLevelOnlyChanges() {
    let baseline = MediaPipelineConfiguration(
        maxVideoWidth: 1_920,
        framesPerSecond: 30,
        videoBitrate: 8_000_000,
        queueDepth: 5,
        capturesSystemAudio: true,
        capturesMicrophone: true,
        systemAudioLevel: 1,
        microphoneLevel: 1
    )
    let levelOnly = MediaPipelineConfiguration(
        maxVideoWidth: 1_920,
        framesPerSecond: 30,
        videoBitrate: 8_000_000,
        queueDepth: 5,
        capturesSystemAudio: true,
        capturesMicrophone: true,
        systemAudioLevel: 0.4,
        microphoneLevel: 0.3
    )
    let microphoneCaptureOnly = MediaPipelineConfiguration(
        maxVideoWidth: 1_920,
        framesPerSecond: 30,
        videoBitrate: 8_000_000,
        queueDepth: 5,
        capturesSystemAudio: true,
        capturesMicrophone: false,
        systemAudioLevel: 1,
        microphoneLevel: 0
    )

    #expect(!SystemMediaPipeline.shouldUpdateActiveStreamConfiguration(from: baseline, to: levelOnly))
    #expect(!SystemMediaPipeline.shouldUpdateActiveStreamConfiguration(from: baseline, to: microphoneCaptureOnly))
}

@Test
func systemMediaPipelineUpdatesStreamConfigurationForCaptureCostChanges() {
    let baseline = MediaPipelineConfiguration(
        maxVideoWidth: 1_920,
        framesPerSecond: 30,
        queueDepth: 5,
        capturesSystemAudio: true
    )
    let lowerVideoCost = MediaPipelineConfiguration(
        maxVideoWidth: 1_280,
        framesPerSecond: 24,
        queueDepth: 3,
        capturesSystemAudio: true
    )
    let withoutSystemAudio = MediaPipelineConfiguration(
        maxVideoWidth: 1_920,
        framesPerSecond: 30,
        queueDepth: 5,
        capturesSystemAudio: false
    )
    let targetChanged = MediaPipelineConfiguration(
        maxVideoWidth: 1_920,
        framesPerSecond: 30,
        queueDepth: 5,
        capturesSystemAudio: true,
        screenCaptureTarget: ScreenCaptureTarget(id: "window-42", kind: .window, name: "Slides", detail: "Keynote")
    )
    let sceneChanged = MediaPipelineConfiguration(
        maxVideoWidth: 1_920,
        framesPerSecond: 30,
        queueDepth: 5,
        sceneKind: .screenAndFace,
        capturesSystemAudio: true
    )

    #expect(SystemMediaPipeline.shouldUpdateActiveStreamConfiguration(from: baseline, to: lowerVideoCost))
    #expect(SystemMediaPipeline.shouldUpdateActiveStreamConfiguration(from: baseline, to: withoutSystemAudio))
    #expect(SystemMediaPipeline.shouldUpdateActiveStreamConfiguration(from: baseline, to: targetChanged))
    #expect(SystemMediaPipeline.shouldUpdateActiveStreamConfiguration(from: baseline, to: sceneChanged))
}

@Test
func systemMediaPipelineAvoidsDoubleCountingCaptureFPSWhenPublishingAndRecordingOverlap() {
    #expect(SystemMediaPipeline.shouldRecordVideoSampleForHealth(
        isScreenOutput: true,
        isPublishingStream: true,
        hasDedicatedPublishingStream: true
    ))
    #expect(!SystemMediaPipeline.shouldRecordVideoSampleForHealth(
        isScreenOutput: true,
        isPublishingStream: false,
        hasDedicatedPublishingStream: true
    ))
    #expect(SystemMediaPipeline.shouldRecordVideoSampleForHealth(
        isScreenOutput: true,
        isPublishingStream: false,
        hasDedicatedPublishingStream: false
    ))
    #expect(!SystemMediaPipeline.shouldRecordVideoSampleForHealth(
        isScreenOutput: false,
        isPublishingStream: true,
        hasDedicatedPublishingStream: true
    ))
}

@Test
func systemMediaPipelineIgnoresStaleRecordingStreamSamples() {
    #expect(SystemMediaPipeline.shouldProcessRecordingStreamSample(isRecordingStream: true, hasWriter: true))
    #expect(!SystemMediaPipeline.shouldProcessRecordingStreamSample(isRecordingStream: false, hasWriter: true))
    #expect(!SystemMediaPipeline.shouldProcessRecordingStreamSample(isRecordingStream: true, hasWriter: false))
    #expect(!SystemMediaPipeline.shouldProcessRecordingStreamSample(isRecordingStream: false, hasWriter: false))
}

@Test
func rtmpAppendBackpressureGateRejectsWorkWhenPublishQueueIsFull() {
    let gate = RTMPAppendBackpressureGate(maxPendingAppends: 2)

    #expect(gate.tryBeginAppend())
    #expect(gate.tryBeginAppend())
    #expect(!gate.tryBeginAppend())

    gate.finishAppend()

    #expect(gate.tryBeginAppend())
}

@Test
func rtmpConnectionCancellationBoxResumesPendingConnectionAttempt() async {
    let cancellation = RTMPConnectionCancellationBox()
    let connection = NWConnection(host: "127.0.0.1", port: 9, using: .tcp)
    var didThrowCancellation = false

    do {
        try await withCheckedThrowingContinuation { continuation in
            let continuationBox = ConnectionContinuationBox(continuation)
            #expect(cancellation.install(connection: connection, continuation: continuationBox))
            cancellation.cancel()
        }
    } catch is CancellationError {
        didThrowCancellation = true
    } catch {
        didThrowCancellation = false
    }

    #expect(didThrowCancellation)
}

@Test
func systemMediaPipelineClosesConnectedPublisherWhenStartIsCancelledBeforeRegistration() async {
    let publisher = DelayedSuccessfulRTMPPublisher()
    let pipeline = SystemMediaPipeline { _ in publisher }
    let destination = StreamDestination(
        name: "Test RTMP",
        rtmpURL: "rtmp://127.0.0.1/live/stream"
    )

    let task = Task {
        try await pipeline.startStream(destination: destination)
    }

    await publisher.waitUntilConnectStarted()
    task.cancel()
    await publisher.finishConnect()

    do {
        try await task.value
    } catch is CancellationError {
    } catch {
        Issue.record("Expected CancellationError, got \(error)")
    }

    #expect(await publisher.closeCount == 1)
}

@Test
func systemMediaPipelineOnlyCapturesPublishMediaForFullRTMPTransport() {
    let pipeline = SystemMediaPipeline()

    #if MAC_STREAM_HAS_HAISHINKIT
    #expect(SystemMediaPipeline.capturesMediaForStreamTransport)
    #expect(pipeline.requiresScreenCaptureVideoForStream)
    #expect(pipeline.supportedSceneKindsForStream == [.screenOnly, .screenAndFace])
    #else
    #expect(!SystemMediaPipeline.capturesMediaForStreamTransport)
    #expect(!pipeline.requiresScreenCaptureVideoForStream)
    #expect(pipeline.supportedSceneKindsForStream == Set(SceneKind.allCases))
    #endif
    #expect(pipeline.requiresScreenCaptureVideoForRecording)
    #expect(pipeline.supportedSceneKindsForRecording == [.screenOnly, .screenAndFace])
}

@Test
func systemMediaPipelineSharesMicrophoneCaptureWhenStreamingAndRecordingOverlap() {
    #expect(SystemMediaPipeline.sharesMicrophoneCaptureBetweenStreamAndRecording)
}

@Test
func systemMediaPipelineStartsPreviewSessionWithoutEndpoint() async throws {
    let pipeline = SystemMediaPipeline()

    try await pipeline.startStream(destination: StreamDestination())
    await pipeline.stopStream()
}

@Test
@MainActor
func studioStoreStartsOnNonCapturingScene() {
    let store = StudioStore()

    #expect(store.selectedSceneKind == .brb)
}

@Test
@MainActor
func sceneSelectionUsesStoreActionPath() {
    let store = StudioStore()
    let faceScene = store.scenes.first { $0.kind == .face }!

    store.selectScene(faceScene)

    #expect(store.selectedSceneID == faceScene.id)
    #expect(store.selectedSceneKind == .face)
    #expect(store.recommendation == nil)
    #expect(store.events[0].title == "Scene changed")
    #expect(store.events[0].detail == "Face")
}

@Test
@MainActor
func selectingCurrentSceneIsNoOp() {
    let store = StudioStore()
    let currentScene = store.selectedScene
    let eventCount = store.events.count

    store.selectScene(currentScene)

    #expect(store.selectedSceneID == currentScene.id)
    #expect(store.events.count == eventCount)
    #expect(store.events[0].title == "Director armed")
}

@Test
@MainActor
func selectingUnknownSceneIsNoOp() {
    let store = StudioStore()
    let selectedSceneID = store.selectedSceneID
    let selectedSceneKind = store.selectedSceneKind
    let eventCount = store.events.count

    store.selectScene(StudioScene(kind: .face, title: "External", subtitle: "Not owned by this store"))

    #expect(store.selectedSceneID == selectedSceneID)
    #expect(store.selectedSceneKind == selectedSceneKind)
    #expect(store.events.count == eventCount)
}

@Test
func performanceModeControlsDisplayPreviewCaptureCost() {
    #expect(StudioPerformanceMode.efficiency.previewCaptureConfiguration == PreviewCaptureConfiguration(maxDisplayWidth: 960, framesPerSecond: 8, queueDepth: 1))
    #expect(StudioPerformanceMode.balanced.previewCaptureConfiguration == PreviewCaptureConfiguration(maxDisplayWidth: 1_280, framesPerSecond: 12, queueDepth: 2))
    #expect(StudioPerformanceMode.responsive.previewCaptureConfiguration == PreviewCaptureConfiguration(maxDisplayWidth: 1_920, framesPerSecond: 15, queueDepth: 3))
}

@Test
func previewCaptureConfigurationClampsValues() {
    #expect(PreviewCaptureConfiguration(maxDisplayWidth: 100, framesPerSecond: 1, queueDepth: 0) == PreviewCaptureConfiguration(maxDisplayWidth: 640, framesPerSecond: 5, queueDepth: 1))
    #expect(PreviewCaptureConfiguration(maxDisplayWidth: 4_000, framesPerSecond: 90, queueDepth: 12) == PreviewCaptureConfiguration(maxDisplayWidth: 1_920, framesPerSecond: 30, queueDepth: 4))
}

@Test
@MainActor
func studioStoreUsesInjectedSignalProvider() {
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: true,
            speechLevel: 0.76,
            screenMotion: 0.08,
            hasFace: true,
            activeApplication: "Notes"
        )
    )
    let store = StudioStore(signalProvider: provider)

    store.advanceDirector()

    #expect(store.latestSignals.speechLevel == 0.76)
    #expect(store.recommendation?.target == .face)
}

@Test
@MainActor
func studioStoreSamplesSystemPressureDuringDirectorTick() {
    let pressure = SystemPressureSnapshot(
        thermalPressure: .fair,
        memoryUsedMB: 512,
        physicalMemoryMB: 16_384
    )
    let store = StudioStore(performanceMonitor: FixedSystemPerformanceMonitor(snapshot: pressure))

    store.advanceDirector()

    #expect(store.systemPressure == pressure)
}

@Test
func systemPressureUsesMemoryFootprintForEfficiency() {
    let nominal = SystemPressureSnapshot(memoryUsedMB: 512, physicalMemoryMB: 16_384)
    let largeFootprint = SystemPressureSnapshot(memoryUsedMB: 2_048, physicalMemoryMB: 16_384)
    let highShare = SystemPressureSnapshot(memoryUsedMB: 1_024, physicalMemoryMB: 4_096)

    #expect(nominal.memoryUsagePercent == 3)
    #expect(!nominal.isMemoryConstrained)
    #expect(!nominal.shouldPreferEfficiency)
    #expect(nominal.efficiencyPressureDetail == nil)
    #expect(largeFootprint.isMemoryConstrained)
    #expect(largeFootprint.shouldPreferEfficiency)
    #expect(largeFootprint.efficiencyPressureDetail == "MacStream is using 2048 MB; Efficiency mode is safer.")
    #expect(highShare.memoryUsagePercent == 25)
    #expect(highShare.isMemoryConstrained)
    #expect(highShare.efficiencyPressureDetail == "MacStream is using 1024 MB; Efficiency mode is safer.")
}

@Test
@MainActor
func studioStoreWarnsAboutPerformancePressureWhenLive() async {
    let pressure = SystemPressureSnapshot(
        thermalPressure: .serious,
        memoryUsedMB: 900,
        physicalMemoryMB: 16_384
    )
    let store = StudioStore(
        mediaPipeline: SpyMediaPipeline(),
        performanceMonitor: FixedSystemPerformanceMonitor(snapshot: pressure)
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.advanceDirector()

    #expect(store.events.contains { $0.title == "Performance pressure" })
}

@Test
@MainActor
func studioStoreWarnsAboutMemoryPressureWhenLive() async {
    let pressure = SystemPressureSnapshot(
        thermalPressure: .nominal,
        memoryUsedMB: 2_048,
        physicalMemoryMB: 16_384
    )
    let store = StudioStore(
        mediaPipeline: SpyMediaPipeline(),
        performanceMonitor: FixedSystemPerformanceMonitor(snapshot: pressure)
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.advanceDirector()

    #expect(store.events.contains {
        $0.title == "Performance pressure" && $0.detail == "MacStream is using 2048 MB; Efficiency mode is safer."
    })
}

@Test
@MainActor
func studioStoreAppliesCountdownPreferenceToCue() {
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: true,
            speechLevel: 0.7,
            screenMotion: 0.08,
            hasFace: true,
            activeApplication: "Notes"
        )
    )
    let store = StudioStore(
        signalProvider: provider,
        preferences: StudioPreferences(directorCountdownSeconds: 5)
    )

    store.advanceDirector()

    #expect(store.recommendation?.delaySeconds == 5)
}

@Test
func studioPreferencesClampCountdownSeconds() throws {
    #expect(StudioPreferences(directorCountdownSeconds: -4).directorCountdownSeconds == 1)
    #expect(StudioPreferences(directorCountdownSeconds: 40).directorCountdownSeconds == 5)

    var preferences = StudioPreferences()
    preferences.directorCountdownSeconds = 0

    #expect(preferences.directorCountdownSeconds == 1)

    let legacyPreferences = """
    {
      "recordWhileStreaming": true,
      "directorCountdownSeconds": 99,
      "performanceMode": "responsive"
    }
    """
    let decoded = try JSONDecoder().decode(StudioPreferences.self, from: Data(legacyPreferences.utf8))

    #expect(decoded.recordWhileStreaming)
    #expect(decoded.directorCountdownSeconds == 5)
    #expect(decoded.performanceMode == .responsive)
    #expect(decoded.cameraEnhancements == CameraEnhancementSettings())
}

@Test
func cameraEnhancementSettingsNormalizeAndPersist() throws {
    let settings = CameraEnhancementSettings(
        mirrorsPreview: false,
        rotation: .degrees90,
        usesAutoLight: true,
        autoLightAmount: 1.7
    )
    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(CameraEnhancementSettings.self, from: encoded)

    #expect(settings.autoLightAmount == 1)
    #expect(decoded == settings)
    #expect(CameraPreviewRotation.degrees90.isSideways)
    #expect(CameraPreviewRotation.degrees270.isSideways)
    #expect(!CameraPreviewRotation.degrees0.isSideways)
}

@Test
@MainActor
func autoDirectorWaitsForCueCountdownBeforeSwitching() async {
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: true,
            speechLevel: 0.7,
            screenMotion: 0.08,
            hasFace: true,
            activeApplication: "Notes"
        )
    )
    let store = StudioStore(
        signalProvider: provider,
        preferences: StudioPreferences(directorCountdownSeconds: 1)
    )
    store.directorMode = .auto
    let startingScene = store.selectedSceneKind

    store.advanceDirector()

    #expect(store.selectedSceneKind == startingScene)
    #expect(store.recommendation?.target == .face)
    #expect(store.autoCueRemainingSeconds == 1)

    try? await Task.sleep(for: .milliseconds(1_200))

    #expect(store.selectedSceneKind == .face)
    #expect(store.recommendation == nil)
    #expect(store.autoCueRemainingSeconds == nil)
}

@Test
@MainActor
func holdingCueCancelsPendingAutoSwitch() async {
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: true,
            speechLevel: 0.7,
            screenMotion: 0.08,
            hasFace: true,
            activeApplication: "Notes"
        )
    )
    let store = StudioStore(
        signalProvider: provider,
        preferences: StudioPreferences(directorCountdownSeconds: 1)
    )
    store.directorMode = .auto
    let startingScene = store.selectedSceneKind

    store.advanceDirector()
    store.dismissRecommendation()

    #expect(store.autoCueRemainingSeconds == nil)
    #expect(store.recommendation == nil)

    try? await Task.sleep(for: .milliseconds(1_200))

    #expect(store.selectedSceneKind == startingScene)
    #expect(store.autoCueRemainingSeconds == nil)
}

@Test
@MainActor
func dismissingMissingRecommendationIsNoOp() {
    let store = StudioStore()
    let eventCount = store.events.count

    store.dismissRecommendation()

    #expect(store.recommendation == nil)
    #expect(store.autoCueRemainingSeconds == nil)
    #expect(store.events.count == eventCount)
    #expect(store.events[0].title == "Director armed")
}

@Test
@MainActor
func autoDirectorAppliesImmediateSafetyCueWithoutCountdown() {
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: false,
            speechLevel: 0.04,
            screenMotion: 0.1,
            hasFace: true,
            activeApplication: "Keynote",
            isScreenFrozen: true
        )
    )
    let store = StudioStore(signalProvider: provider)
    store.directorMode = .auto

    store.advanceDirector()

    #expect(store.selectedSceneKind == .face)
    #expect(store.recommendation == nil)
    #expect(store.autoCueRemainingSeconds == nil)
}

@Test
@MainActor
func studioStoreAppliesPerformanceModeToSignalProvider() {
    let provider = ConfigurableSignalProvider()
    let store = StudioStore(
        signalProvider: provider,
        preferences: StudioPreferences(performanceMode: .efficiency)
    )

    #expect(provider.lastConfiguration == StudioPerformanceMode.efficiency.signalSamplingConfiguration)

    store.updatePreferences(StudioPreferences(performanceMode: .responsive))

    #expect(provider.lastConfiguration == StudioPerformanceMode.responsive.signalSamplingConfiguration)
}

@Test
@MainActor
func pausedDirectorModeDoesNotStartSignalLoopWhenStreamStarts() async {
    let provider = ConfigurableSignalProvider()
    let store = StudioStore(
        mediaPipeline: ConfigurableMediaPipeline(),
        signalProvider: provider
    )

    store.directorMode = .paused
    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.isLive)
    #expect(provider.startCount == 0)
    #expect(provider.stopCount == 0)
    #expect(store.recommendation == nil)
}

@Test
@MainActor
func offlineDirectorLoopStartDoesNotStartSignalSampling() {
    let provider = ConfigurableSignalProvider()
    let store = StudioStore(signalProvider: provider)
    let updateCount = provider.updateCount

    store.startDirectorLoop()

    #expect(!store.isLive)
    #expect(provider.updateCount == updateCount)
    #expect(provider.startCount == 0)
    #expect(provider.stopCount == 0)
    #expect(store.autoCueRemainingSeconds == nil)
}

@Test
@MainActor
func directorLoopRestartsWhenLeavingPausedModeWhileLive() async {
    let provider = ConfigurableSignalProvider()
    let store = StudioStore(
        mediaPipeline: ConfigurableMediaPipeline(),
        signalProvider: provider
    )

    store.directorMode = .paused
    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    store.directorMode = .suggest

    #expect(provider.startCount == 1)

    store.directorMode = .paused

    #expect(provider.stopCount == 1)
}

@Test
@MainActor
func redundantDirectorModeWritesDoNotRestartSignalLoop() async {
    let provider = ConfigurableSignalProvider()
    let store = StudioStore(
        mediaPipeline: ConfigurableMediaPipeline(),
        signalProvider: provider
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(provider.startCount == 1)

    store.directorMode = .suggest

    #expect(provider.startCount == 1)
    #expect(provider.stopCount == 0)

    store.directorMode = .paused

    #expect(provider.stopCount == 1)

    store.directorMode = .paused

    #expect(provider.stopCount == 1)
}

@Test
@MainActor
func directorSamplesImmediatelyWhenStreamStarts() async {
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: true,
            speechLevel: 0.76,
            screenMotion: 0.08,
            hasFace: true,
            activeApplication: "Notes"
        )
    )
    let store = StudioStore(
        mediaPipeline: ConfigurableMediaPipeline(),
        signalProvider: provider
    )

    store.startStream()
    for _ in 0..<10 {
        if store.recommendation != nil { break }
        await Task.yield()
    }

    #expect(store.streamState == .live)
    #expect(store.recommendation?.target == .face)
}

@Test
@MainActor
func studioStoreSkipsRedundantPerformanceConfigurationUpdates() {
    let pipeline = ConfigurableMediaPipeline()
    let provider = ConfigurableSignalProvider()
    let store = StudioStore(
        mediaPipeline: pipeline,
        signalProvider: provider,
        preferences: StudioPreferences(performanceMode: .balanced)
    )

    #expect(pipeline.updateCount == 1)
    #expect(provider.updateCount == 1)

    store.updatePreferences(StudioPreferences(performanceMode: .balanced))

    #expect(pipeline.updateCount == 1)
    #expect(provider.updateCount == 1)

    store.updatePreferences(StudioPreferences(performanceMode: .responsive))

    #expect(pipeline.updateCount == 2)
    #expect(provider.updateCount == 2)

    store.updatePreferences(StudioPreferences(performanceMode: .responsive))

    #expect(pipeline.updateCount == 2)
    #expect(provider.updateCount == 2)
}

@Test
@MainActor
func studioStoreReportsSourceEnabledState() {
    let store = StudioStore()
    let camera = store.sources.first { $0.kind == .camera }!

    #expect(store.isSourceEnabled(.camera))

    store.toggleSource(camera)

    #expect(!store.isSourceEnabled(.camera))
}

@Test
@MainActor
func savedSourceConfigurationRestoresSourceState() {
    let store = StudioStore()

    store.applySavedSourceConfiguration([
        StudioSourceConfiguration(kind: .camera, isEnabled: false, level: 0.2),
        StudioSourceConfiguration(kind: .screen, isEnabled: true, level: 0.43),
        StudioSourceConfiguration(kind: .microphone, isEnabled: false, level: -1),
        StudioSourceConfiguration(kind: .systemAudio, isEnabled: true, level: 2)
    ])

    #expect(!store.isSourceEnabled(.camera))
    #expect(store.sourceLevel(.camera) == 1)
    #expect(store.isSourceEnabled(.screen))
    #expect(store.sourceLevel(.screen) == 0.43)
    #expect(!store.isSourceEnabled(.microphone))
    #expect(store.sourceLevel(.microphone) == 0)
    #expect(store.isSourceEnabled(.systemAudio))
    #expect(store.sourceLevel(.systemAudio) == 1)
    #expect(store.sourceConfiguration.contains(StudioSourceConfiguration(kind: .systemAudio, isEnabled: true, level: 1)))
}

@Test
@MainActor
func activeCaptureKeepsSelectedSceneRequiredSourcesEnabled() async throws {
    let pipeline = ConfigurableMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)
    let screenScene = try #require(store.scenes.first { $0.kind == .screenOnly })
    let screen = try #require(store.sources.first { $0.kind == .screen })
    let microphone = try #require(store.sources.first { $0.kind == .microphone })

    store.selectScene(screenScene)
    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.isLive)
    #expect(!store.canToggleSource(screen))
    #expect(!store.canAdjustSourceLevel(screen))

    let eventCount = store.events.count
    let pipelineUpdateCount = pipeline.updateCount
    store.toggleSource(screen)
    store.updateLevel(for: screen, level: 0)

    #expect(store.isSourceEnabled(.screen))
    #expect(store.sourceLevel(.screen) == 1)
    #expect(store.events.count == eventCount)
    #expect(pipeline.updateCount == pipelineUpdateCount)

    #expect(store.canToggleSource(microphone))
    #expect(store.canAdjustSourceLevel(microphone))
    store.toggleSource(microphone)

    #expect(!store.isSourceEnabled(.microphone))
    #expect(pipeline.updateCount == pipelineUpdateCount + 1)
}

@Test
@MainActor
func activeRealCaptureRejectsUnsupportedSceneSwitches() async throws {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted),
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(
        mediaPipeline: ScreenVideoGatedMediaPipeline(streamTransport: .rtmpPublish),
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report)
    )
    let screenScene = try #require(store.scenes.first { $0.kind == .screenOnly })
    let screenAndFaceScene = try #require(store.scenes.first { $0.kind == .screenAndFace })
    let faceScene = try #require(store.scenes.first { $0.kind == .face })
    let brbScene = try #require(store.scenes.first { $0.kind == .brb })

    store.destination = StreamDestination(name: "RTMP", rtmpURL: "rtmp://127.0.0.1/live/stream")
    store.selectScene(screenScene)
    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.canStartStream)

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.isLive)
    #expect(!store.canSelectScene(faceScene))
    #expect(!store.canSelectScene(screenAndFaceScene))
    #expect(!store.canSelectScene(brbScene))
    #expect(store.sceneSelectionBlockedReason(for: faceScene) == "Stop real capture before choosing Face.")
    #expect(store.sceneSelectionBlockedReason(for: screenAndFaceScene) == "Stop real capture before choosing Screen + Face.")
    #expect(store.sceneSelectionBlockedReason(for: brbScene) == "Stop real capture before choosing BRB.")

    let eventCount = store.events.count
    store.selectScene(faceScene)

    #expect(store.selectedSceneKind == .screenOnly)
    #expect(store.events.count == eventCount)

    store.selectScene(screenAndFaceScene)

    #expect(store.selectedSceneKind == .screenOnly)
}

@Test
@MainActor
func activeRealCaptureAllowsSupportedComposedSceneSwitches() async throws {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted),
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let pipeline = ComposedScreenVideoMediaPipeline(streamTransport: .rtmpPublish)
    let store = StudioStore(
        mediaPipeline: pipeline,
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report)
    )
    let screenScene = try #require(store.scenes.first { $0.kind == .screenOnly })
    let screenAndFaceScene = try #require(store.scenes.first { $0.kind == .screenAndFace })
    let faceScene = try #require(store.scenes.first { $0.kind == .face })

    store.destination = StreamDestination(name: "RTMP", rtmpURL: "rtmp://127.0.0.1/live/stream")
    store.selectScene(screenScene)
    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))
    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.isLive)
    #expect(store.canSelectScene(screenAndFaceScene))
    #expect(!store.canSelectScene(faceScene))
    #expect(store.sceneSelectionBlockedReason(for: screenAndFaceScene) == nil)

    store.selectScene(screenAndFaceScene)

    #expect(store.selectedSceneKind == .screenAndFace)
    #expect(pipeline.lastConfiguration?.sceneKind == .screenAndFace)
}

@Test
@MainActor
func activeRecordingRejectsUnsupportedSceneSwitches() async throws {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted),
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(
        mediaPipeline: ScreenVideoGatedMediaPipeline(streamTransport: .rtmpPublish),
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report)
    )
    let screenScene = try #require(store.scenes.first { $0.kind == .screenOnly })
    let faceScene = try #require(store.scenes.first { $0.kind == .face })

    store.selectScene(screenScene)
    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.canStartRecording)

    store.startRecording()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.recordingState == .recording)
    #expect(!store.canSelectScene(faceScene))
    #expect(store.sceneSelectionBlockedReason(for: faceScene) == "Stop recording before choosing Face.")

    let eventCount = store.events.count
    store.selectScene(faceScene)

    #expect(store.selectedSceneKind == .screenOnly)
    #expect(store.events.count == eventCount)
}

@Test
@MainActor
func activeRealCaptureSuppressesUnavailableDirectorSceneCue() async throws {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted),
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: true,
            speechLevel: 0.72,
            screenMotion: 0.08,
            hasFace: true,
            activeApplication: "Notes"
        )
    )
    let store = StudioStore(
        mediaPipeline: ScreenVideoGatedMediaPipeline(streamTransport: .rtmpPublish),
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report),
        signalProvider: provider
    )
    let screenScene = try #require(store.scenes.first { $0.kind == .screenOnly })

    store.destination = StreamDestination(name: "RTMP", rtmpURL: "rtmp://127.0.0.1/live/stream")
    store.selectScene(screenScene)
    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))
    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    store.advanceDirector()

    #expect(store.isLive)
    #expect(store.selectedSceneKind == .screenOnly)
    #expect(store.recommendation == nil)
    #expect(store.autoCueRemainingSeconds == nil)
    #expect(!store.events.contains { $0.title == "Cue Face" })
}

@Test
@MainActor
func activeRealCaptureRetargetsUnavailableImmediateCueToStreamWarning() async throws {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted),
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: false,
            speechLevel: 0.04,
            screenMotion: 0.1,
            hasFace: true,
            activeApplication: "Keynote",
            isScreenFrozen: true
        )
    )
    let store = StudioStore(
        mediaPipeline: ScreenVideoGatedMediaPipeline(streamTransport: .rtmpPublish),
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report),
        signalProvider: provider
    )
    let screenScene = try #require(store.scenes.first { $0.kind == .screenOnly })

    store.destination = StreamDestination(name: "RTMP", rtmpURL: "rtmp://127.0.0.1/live/stream")
    store.selectScene(screenScene)
    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))
    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    store.advanceDirector()

    #expect(store.isLive)
    #expect(store.selectedSceneKind == .screenOnly)
    #expect(store.recommendation?.target == .screenOnly)
    #expect(store.recommendation?.urgency == .immediate)
    #expect(store.recommendation?.reason.contains("Stop real capture before choosing Face.") == true)
    #expect(!store.canApplyRecommendation)
    #expect(store.autoCueRemainingSeconds == nil)
    #expect(store.events.contains { $0.title == "Check stream" })
}

@Test
@MainActor
func defaultSourcesKeepSystemAudioOptIn() {
    let store = StudioStore()

    #expect(store.isSourceEnabled(.camera))
    #expect(store.isSourceEnabled(.screen))
    #expect(store.isSourceEnabled(.microphone))
    #expect(!store.isSourceEnabled(.systemAudio))
    #expect(store.sourceSetupTitle == "3/4 on")
    #expect(store.sourceLevel(.systemAudio) == 0.72)
}

@Test
func sourceLevelSupportMatchesCurrentCaptureControls() {
    #expect(!SourceKind.camera.supportsLevelControl)
    #expect(SourceKind.screen.supportsLevelControl)
    #expect(SourceKind.microphone.supportsLevelControl)
    #expect(SourceKind.systemAudio.supportsLevelControl)
}

@Test
@MainActor
func studioStoreAppliesSourceTogglesToSignalSamplingConfiguration() {
    let provider = ConfigurableSignalProvider()
    let store = StudioStore(signalProvider: provider)
    let microphone = store.sources.first { $0.kind == .microphone }!
    let screen = store.sources.first { $0.kind == .screen }!

    #expect(provider.lastConfiguration == SignalSamplingConfiguration(screenMotionFramesPerSecond: 4))

    store.toggleSource(screen)

    #expect(provider.lastConfiguration == SignalSamplingConfiguration(
        screenMotionFramesPerSecond: 4,
        isMicrophoneEnabled: true,
        isScreenMotionEnabled: false
    ))

    store.toggleSource(microphone)

    #expect(provider.lastConfiguration == SignalSamplingConfiguration(
        screenMotionFramesPerSecond: 4,
        isMicrophoneEnabled: false,
        isScreenMotionEnabled: false
    ))
}

@Test
@MainActor
func sourceTogglesPreservePerformanceSamplingRate() {
    let provider = ConfigurableSignalProvider()
    let store = StudioStore(
        signalProvider: provider,
        preferences: StudioPreferences(performanceMode: .responsive)
    )
    let screen = store.sources.first { $0.kind == .screen }!

    store.toggleSource(screen)

    #expect(provider.lastConfiguration == SignalSamplingConfiguration(
        screenMotionFramesPerSecond: 8,
        isMicrophoneEnabled: true,
        isScreenMotionEnabled: false
    ))
}

@Test
@MainActor
func zeroScreenLevelDisablesScreenMotionSampling() {
    let provider = ConfigurableSignalProvider()
    let store = StudioStore(signalProvider: provider)
    let screen = store.sources.first { $0.kind == .screen }!

    store.updateLevel(for: screen, level: 0)

    #expect(provider.lastConfiguration == SignalSamplingConfiguration(
        screenMotionFramesPerSecond: 4,
        isMicrophoneEnabled: true,
        isScreenMotionEnabled: false
    ))

    store.updateLevel(for: screen, level: 0.5)

    #expect(provider.lastConfiguration == SignalSamplingConfiguration(
        screenMotionFramesPerSecond: 4,
        isMicrophoneEnabled: true,
        isScreenMotionEnabled: true
    ))
}

@Test
@MainActor
func studioStoreAppliesPerformanceModeToMediaPipeline() async {
    let pipeline = ConfigurableMediaPipeline()
    let store = StudioStore(
        mediaPipeline: pipeline,
        preferences: StudioPreferences(performanceMode: .efficiency)
    )

    #expect(pipeline.lastConfiguration == expectedMediaConfiguration(.efficiency))

    store.updatePreferences(StudioPreferences(performanceMode: .responsive))
    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(pipeline.lastConfiguration == expectedMediaConfiguration(.responsive))
    #expect(pipeline.configurationAtStartStream == expectedMediaConfiguration(.responsive))
    #expect(store.health.captureFPS == StudioPerformanceMode.responsive.mediaConfiguration.framesPerSecond)
}

@Test
@MainActor
func studioStorePrefersMediaPipelineHealthSnapshotWhenAvailable() async {
    let pipeline = ConfigurableMediaPipeline()
    pipeline.currentHealth = StreamHealth(
        bitrateKbps: 3_200,
        droppedFrames: 7,
        captureFPS: 48,
        audioLevel: 0.12,
        roundTripMs: 16
    )
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: true,
            speechLevel: 0.74,
            screenMotion: 0.92,
            hasFace: true,
            activeApplication: "Xcode",
            isScreenFrozen: true
        )
    )
    let store = StudioStore(mediaPipeline: pipeline, signalProvider: provider)

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.advanceDirector()

    #expect(store.health.bitrateKbps == 3_200)
    #expect(store.health.droppedFrames == 7)
    #expect(store.health.captureFPS == 48)
    #expect(store.health.audioLevel == 0.74)
    #expect(store.health.roundTripMs == 16)
}

@Test
@MainActor
func studioStoreAppliesAudioSourceTogglesToMediaPipelineConfiguration() {
    let pipeline = ConfigurableMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)
    let microphone = store.sources.first { $0.kind == .microphone }!
    let systemAudio = store.sources.first { $0.kind == .systemAudio }!

    #expect(pipeline.lastConfiguration?.capturesMicrophone == true)
    #expect(pipeline.lastConfiguration?.capturesSystemAudio == false)

    store.toggleSource(systemAudio)

    #expect(pipeline.lastConfiguration?.capturesMicrophone == true)
    #expect(pipeline.lastConfiguration?.capturesSystemAudio == true)

    store.toggleSource(microphone)

    #expect(pipeline.lastConfiguration?.capturesMicrophone == false)
    #expect(pipeline.lastConfiguration?.capturesSystemAudio == true)

    store.toggleSource(systemAudio)

    #expect(pipeline.lastConfiguration?.capturesMicrophone == false)
    #expect(pipeline.lastConfiguration?.capturesSystemAudio == false)
}

@Test
@MainActor
func sourceLevelsUpdateMediaPipelineAudioConfiguration() {
    let pipeline = ConfigurableMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)
    let microphone = store.sources.first { $0.kind == .microphone }!
    let systemAudio = store.sources.first { $0.kind == .systemAudio }!

    #expect(pipeline.lastConfiguration?.microphoneLevel == 1)
    #expect(pipeline.lastConfiguration?.systemAudioLevel == 0.72)
    #expect(pipeline.lastConfiguration?.capturesSystemAudio == false)

    store.toggleSource(systemAudio)

    store.updateLevel(for: microphone, level: 0.35)
    store.updateLevel(for: systemAudio, level: 0.4)

    #expect(pipeline.lastConfiguration?.capturesMicrophone == true)
    #expect(pipeline.lastConfiguration?.capturesSystemAudio == true)
    #expect(pipeline.lastConfiguration?.microphoneLevel == 0.35)
    #expect(pipeline.lastConfiguration?.systemAudioLevel == 0.4)

    store.updateLevel(for: microphone, level: 0)
    store.updateLevel(for: systemAudio, level: 0)

    #expect(pipeline.lastConfiguration?.capturesMicrophone == false)
    #expect(pipeline.lastConfiguration?.capturesSystemAudio == false)
    #expect(pipeline.lastConfiguration?.microphoneLevel == 0)
    #expect(pipeline.lastConfiguration?.systemAudioLevel == 0)
}

@Test
@MainActor
func sourceLevelUpdatesSkipRedundantClampedValues() {
    let pipeline = ConfigurableMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)
    let microphone = store.sources.first { $0.kind == .microphone }!

    #expect(store.sourceLevel(.microphone) == 1)
    #expect(pipeline.updateCount == 1)

    store.updateLevel(for: microphone, level: 2)

    #expect(store.sourceLevel(.microphone) == 1)
    #expect(pipeline.updateCount == 1)

    store.updateLevel(for: microphone, level: 0.35)

    #expect(store.sourceLevel(.microphone) == 0.35)
    #expect(pipeline.updateCount == 2)

    store.updateLevel(for: microphone, level: 0.35)

    #expect(pipeline.updateCount == 2)
}

@Test
@MainActor
func sourceLevelUpdatesQuantizeSliderNoise() throws {
    let pipeline = ConfigurableMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)
    let microphone = store.sources.first { $0.kind == .microphone }!
    let sourceRackURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/MacStream/Views/SourceRackView.swift")
    let sourceRack = try String(contentsOf: sourceRackURL, encoding: .utf8)

    store.updateLevel(for: microphone, level: 0.354)

    #expect(store.sourceLevel(.microphone) == 0.35)
    #expect(pipeline.updateCount == 2)

    store.updateLevel(for: microphone, level: 0.351)

    #expect(store.sourceLevel(.microphone) == 0.35)
    #expect(pipeline.updateCount == 2)

    store.updateLevel(for: microphone, level: 0.356)

    #expect(store.sourceLevel(.microphone) == 0.36)
    #expect(pipeline.updateCount == 3)
    #expect(sourceRack.contains("step: 0.01"))
}

@Test
@MainActor
func cameraLevelUpdatesAreIgnored() {
    let pipeline = ConfigurableMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)
    let camera = store.sources.first { $0.kind == .camera }!

    #expect(store.sourceLevel(.camera) == 1)
    #expect(pipeline.updateCount == 1)

    store.updateLevel(for: camera, level: 0)

    #expect(store.sourceLevel(.camera) == 1)
    #expect(pipeline.updateCount == 1)
}

@Test
@MainActor
func sourceLevelUpdatesUseStoredSourceCapabilities() {
    let pipeline = ConfigurableMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)
    let camera = store.sources.first { $0.kind == .camera }!
    let forgedMicrophone = StudioSource(
        id: camera.id,
        kind: .microphone,
        title: "Forged Mic",
        level: 0.2
    )

    store.updateLevel(for: forgedMicrophone, level: 0)

    #expect(store.sourceLevel(.camera) == 1)
    #expect(pipeline.updateCount == 1)
}

@Test
@MainActor
func sourceTogglesPreserveMediaPerformanceProfile() {
    let pipeline = ConfigurableMediaPipeline()
    let store = StudioStore(
        mediaPipeline: pipeline,
        preferences: StudioPreferences(performanceMode: .efficiency)
    )
    let systemAudio = store.sources.first { $0.kind == .systemAudio }!

    store.toggleSource(systemAudio)

    var expected = StudioPerformanceMode.efficiency.mediaConfiguration
    expected.sceneKind = .brb
    expected.systemAudioLevel = 0.72
    expected.capturesSystemAudio = true
    #expect(pipeline.lastConfiguration == expected)
}

@Test
@MainActor
func selectedSceneUpdatesMediaPipelineConfiguration() throws {
    let pipeline = ConfigurableMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)
    let screenAndFaceScene = try #require(store.scenes.first { $0.kind == .screenAndFace })

    store.selectScene(screenAndFaceScene)

    #expect(pipeline.lastConfiguration?.sceneKind == .screenAndFace)
}

@Test
@MainActor
func applyingDirectorRecommendationUpdatesMediaPipelineScene() throws {
    let pipeline = ConfigurableMediaPipeline()
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: false,
            speechLevel: 0.04,
            screenMotion: 0.1,
            hasFace: true,
            activeApplication: "Keynote",
            isScreenFrozen: true
        )
    )
    let store = StudioStore(mediaPipeline: pipeline, signalProvider: provider)

    #expect(store.selectedSceneKind == .brb)
    #expect(pipeline.lastConfiguration?.sceneKind == .brb)

    store.advanceDirector()
    #expect(store.recommendation?.target == .face)

    store.applyRecommendation()

    #expect(store.selectedSceneKind == .face)
    #expect(pipeline.lastConfiguration?.sceneKind == .face)
}

@Test
@MainActor
func cameraEnhancementsUpdateMediaPipelineConfiguration() {
    let pipeline = ConfigurableMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)
    let enhancements = CameraEnhancementSettings(
        mirrorsPreview: false,
        rotation: .degrees90,
        usesAutoLight: true,
        autoLightAmount: 0.68
    )

    store.updateCameraEnhancements(enhancements)

    #expect(pipeline.lastConfiguration?.cameraEnhancements == enhancements)
}

@Test
@MainActor
func captureScanSelectsFirstDisplayTargetAndConfiguresCapture() async {
    let pipeline = ConfigurableMediaPipeline()
    let signalProvider = ConfigurableSignalProvider()
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "window-42", kind: .window, name: "Slides", detail: "Keynote", permission: .granted),
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report),
        signalProvider: signalProvider
    )

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    let displayTarget = ScreenCaptureTarget(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964")
    #expect(store.selectedScreenCaptureTarget == displayTarget)
    #expect(pipeline.lastConfiguration?.screenCaptureTarget == displayTarget)
    #expect(signalProvider.lastConfiguration?.screenCaptureTarget == displayTarget)
}

@Test
@MainActor
func savedScreenCaptureTargetPreferenceRestoresAfterScan() async {
    let pipeline = ConfigurableMediaPipeline()
    let signalProvider = ConfigurableSignalProvider()
    let windowTarget = ScreenCaptureTarget(id: "window-42", kind: .window, name: "Slides", detail: "Keynote")
    let displayTarget = ScreenCaptureTarget(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964")
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: windowTarget.id, kind: .window, name: windowTarget.name, detail: windowTarget.detail, permission: .granted),
            CaptureDeviceInfo(id: displayTarget.id, kind: .display, name: displayTarget.name, detail: displayTarget.detail, permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report),
        signalProvider: signalProvider
    )

    store.applySavedScreenCaptureTargetPreference(windowTarget)
    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.selectedScreenCaptureTarget == windowTarget)
    #expect(store.screenCaptureTargetPreference == windowTarget)
    #expect(pipeline.lastConfiguration?.screenCaptureTarget == windowTarget)
    #expect(signalProvider.lastConfiguration?.screenCaptureTarget == windowTarget)
}

@Test
@MainActor
func missingScreenCapturePreferenceFallsBackWithoutClearingPreference() async {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(captureDeviceProvider: FixedCaptureDeviceProvider(report: report))
    let missingWindow = ScreenCaptureTarget(id: "window-42", kind: .window, name: "Slides", detail: "Keynote")

    store.applySavedScreenCaptureTargetPreference(missingWindow)
    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.selectedScreenCaptureTarget == ScreenCaptureTarget(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964"))
    #expect(store.screenCaptureTargetPreference == missingWindow)
}

@Test
@MainActor
func captureRescanRefreshesSelectedScreenTargetMetadata() async {
    let pipeline = ConfigurableMediaPipeline()
    let signalProvider = ConfigurableSignalProvider()
    let provider = SequencedCaptureDeviceProvider(reports: [
        CapturePreflightReport(
            devices: [
                CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted)
            ],
            summary: "Initial display ready."
        ),
        CapturePreflightReport(
            devices: [
                CaptureDeviceInfo(id: "display-7", kind: .display, name: "Main Display", detail: "2560x1440", permission: .granted)
            ],
            summary: "Updated display ready."
        )
    ])
    let store = StudioStore(
        mediaPipeline: pipeline,
        captureDeviceProvider: provider,
        signalProvider: signalProvider
    )

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.selectedScreenCaptureTarget?.title == "Studio Display - 3024x1964")

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    let refreshedTarget = ScreenCaptureTarget(id: "display-7", kind: .display, name: "Main Display", detail: "2560x1440")
    #expect(store.selectedScreenCaptureTarget == refreshedTarget)
    #expect(pipeline.lastConfiguration?.screenCaptureTarget == refreshedTarget)
    #expect(signalProvider.lastConfiguration?.screenCaptureTarget == refreshedTarget)
}

@Test
@MainActor
func selectingCurrentScreenCaptureTargetIsNoOp() async {
    let pipeline = ConfigurableMediaPipeline()
    let signalProvider = ConfigurableSignalProvider()
    let displayTarget = ScreenCaptureTarget(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964")
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: displayTarget.id, kind: .display, name: displayTarget.name, detail: displayTarget.detail, permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report),
        signalProvider: signalProvider
    )

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))
    let mediaUpdateCount = pipeline.updateCount
    let signalUpdateCount = signalProvider.updateCount
    let eventCount = store.events.count

    store.selectScreenCaptureTarget(displayTarget)

    #expect(store.selectedScreenCaptureTarget == displayTarget)
    #expect(pipeline.updateCount == mediaUpdateCount)
    #expect(signalProvider.updateCount == signalUpdateCount)
    #expect(store.events.count == eventCount)
}

@Test
@MainActor
func captureReadinessIgnoresDisabledOptionalSources() async throws {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted),
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .denied),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .denied)
        ],
        summary: "2 source permissions need attention."
    )
    let store = StudioStore(captureDeviceProvider: FixedCaptureDeviceProvider(report: report))
    store.selectRecommendedStartingScene()

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.captureReadiness.state == .needsAccess)
    #expect(store.captureReadiness.detail == "Camera and Microphone need access.")
    #expect(store.missingRequiredCapturePermissionKinds == [.camera, .microphone])

    let camera = try #require(store.sources.first { $0.kind == .camera })
    let microphone = try #require(store.sources.first { $0.kind == .microphone })
    store.toggleSource(camera)
    store.toggleSource(microphone)

    #expect(store.captureReadiness.state == .ready)
    #expect(store.captureReadiness.title == "Ready")
    #expect(store.captureReadiness.detail == "Required capture sources are ready.")
    #expect(store.missingRequiredCapturePermissionKinds.isEmpty)
}

@Test
@MainActor
func capturePermissionStateSeparatesPromptableBlockedAndMissingDevices() async {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted),
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .denied),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .notDetermined)
        ],
        summary: "2 source permissions need attention."
    )
    let store = StudioStore(captureDeviceProvider: FixedCaptureDeviceProvider(report: report))
    store.selectRecommendedStartingScene()

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.missingRequiredCapturePermissionKinds == [.camera, .microphone])
    #expect(store.promptableRequiredCapturePermissionKinds == [.microphone])
    #expect(store.blockedRequiredCapturePermissionKinds == [.camera])
    #expect(store.missingRequiredCaptureDeviceKinds.isEmpty)
}

@Test
@MainActor
func capturePermissionStateSurfacesMissingRequiredHardware() async {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .notDetermined)
        ],
        summary: "1 source permission needs attention."
    )
    let store = StudioStore(captureDeviceProvider: FixedCaptureDeviceProvider(report: report))
    store.selectRecommendedStartingScene()

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.missingRequiredCapturePermissionKinds == [.camera, .microphone])
    #expect(store.promptableRequiredCapturePermissionKinds == [.microphone])
    #expect(store.blockedRequiredCapturePermissionKinds.isEmpty)
    #expect(store.missingRequiredCaptureDeviceKinds == [.camera])
}

@Test
@MainActor
func captureReadinessTreatsScreenRecordingAsRestartScoped() async {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "screen-permission", kind: .display, name: "Screen Capture", detail: "Screen Recording permission is not visible to this launch.", permission: .notDetermined),
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted)
        ],
        summary: "1 source permission needs attention."
    )
    let store = StudioStore(captureDeviceProvider: FixedCaptureDeviceProvider(report: report))
    store.selectRecommendedStartingScene()

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.availableScreenCaptureTargets.isEmpty)
    #expect(store.selectedScreenCaptureTarget == nil)
    #expect(store.captureReadiness.state == .needsRelaunch)
    #expect(store.captureReadiness.title == "Screen access")
    #expect(store.captureReadiness.detail == "Grant Screen Recording, then reopen MacStream.")
    #expect(store.missingRequiredCapturePermissionKinds == [.display])
}

@Test
@MainActor
func captureReadinessFollowsSelectedSceneRequirements() async throws {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "screen-permission", kind: .display, name: "Screen Capture", detail: "Screen Recording permission is not visible to this launch.", permission: .notDetermined),
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted)
        ],
        summary: "1 source permission needs attention."
    )
    let store = StudioStore(captureDeviceProvider: FixedCaptureDeviceProvider(report: report))
    let faceScene = try #require(store.scenes.first { $0.kind == .face })
    let screenScene = try #require(store.scenes.first { $0.kind == .screenOnly })

    store.selectScene(faceScene)
    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.captureReadiness.state == .ready)
    #expect(store.missingRequiredCapturePermissionKinds.isEmpty)
    #expect(!store.requiresRelaunchForRequiredCapturePermission)

    store.selectScene(screenScene)

    #expect(store.captureReadiness.state == .needsRelaunch)
    #expect(store.captureReadiness.detail == "Grant Screen Recording, then reopen MacStream.")
    #expect(store.missingRequiredCapturePermissionKinds == [.display])
    #expect(store.requiresRelaunchForRequiredCapturePermission)
}

@Test
@MainActor
func captureReadinessIgnoresCameraWhenScreenOnlySelected() async throws {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted),
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .denied),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted)
        ],
        summary: "1 source permission needs attention."
    )
    let store = StudioStore(captureDeviceProvider: FixedCaptureDeviceProvider(report: report))
    let screenScene = try #require(store.scenes.first { $0.kind == .screenOnly })
    let screenAndFaceScene = try #require(store.scenes.first { $0.kind == .screenAndFace })

    store.selectScene(screenScene)
    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.captureReadiness.state == .ready)
    #expect(store.missingRequiredCapturePermissionKinds.isEmpty)

    store.selectScene(screenAndFaceScene)

    #expect(store.captureReadiness.state == .needsAccess)
    #expect(store.captureReadiness.detail == "Camera needs access.")
    #expect(store.missingRequiredCapturePermissionKinds == [.camera])
}

@Test
@MainActor
func setupChecklistGuidesFirstRunAndDisappearsWhenReady() async throws {
    let displayTarget = ScreenCaptureTarget(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964")
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: displayTarget.id, kind: .display, name: displayTarget.name, detail: displayTarget.detail, permission: .granted),
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(captureDeviceProvider: FixedCaptureDeviceProvider(report: report))

    #expect(store.shouldShowSetupChecklist)
    #expect(store.setupChecklistItems.count == 4)
    #expect(store.setupChecklistItems.filter { !$0.isComplete }.map(\.id) == [.scene, .capture])
    #expect(store.completedSetupItemCount == 2)
    #expect(store.totalSetupItemCount == 4)
    #expect(store.setupProgressFraction == 0.5)
    #expect(store.nextSetupChecklistItem?.id == .scene)
    #expect(store.setupChecklistItems.first { $0.id == .scene }?.detail == "Choose Face, Screen + Face, or Screen.")
    #expect(store.setupChecklistItems.first { $0.id == .destination }?.detail == "Preview session ready.")

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.shouldShowSetupChecklist)
    #expect(store.setupChecklistItems.filter { !$0.isComplete }.map(\.id) == [.scene])
    #expect(store.completedSetupItemCount == 3)
    #expect(store.setupProgressFraction == 0.75)
    #expect(store.nextSetupChecklistItem?.id == .scene)

    let screenAndFaceScene = try #require(store.scenes.first { $0.kind == .screenAndFace })
    store.selectScene(screenAndFaceScene)

    #expect(!store.shouldShowSetupChecklist)
    #expect(store.setupChecklistItems.allSatisfy { $0.isComplete })
    #expect(store.completedSetupItemCount == 4)
    #expect(store.setupProgressFraction == 1)
    #expect(store.nextSetupChecklistItem == nil)
}

@Test
@MainActor
func setupChecklistSurfacesDestinationAndSourceSetup() throws {
    let store = StudioStore()
    store.setDestinationMode(.rtmp)

    for source in store.sources {
        if source.isEnabled {
            store.toggleSource(source)
        }
    }

    let incompleteItems = store.setupChecklistItems.filter { !$0.isComplete }
    #expect(store.shouldShowSetupChecklist)
    #expect(incompleteItems.map(\.id) == [.scene, .capture, .destination, .sources])
    #expect(store.setupChecklistItems.first { $0.id == .destination }?.detail == "Enter a valid RTMP or RTMPS URL.")
    #expect(store.setupChecklistItems.first { $0.id == .sources }?.detail == "Enable at least one source.")
}

@Test
@MainActor
func setupChecklistRequiresSourcesForSelectedScene() async throws {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted),
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(captureDeviceProvider: FixedCaptureDeviceProvider(report: report))
    let screenScene = try #require(store.scenes.first { $0.kind == .screenOnly })
    let screenSource = try #require(store.sources.first { $0.kind == .screen })

    store.selectScene(screenScene)
    store.toggleSource(screenSource)
    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.isSourceSetupReady == false)
    #expect(store.sourceSetupTitle == "0/1 ready")
    #expect(store.sourceSetupDetail == "Enable Screen for Screen.")
    #expect(store.setupRole(for: .screen) == .required)
    #expect(store.setupRole(for: .microphone) == .recommended)
    #expect(store.setupRole(for: .camera) == .unused)
    #expect(store.setupRole(for: .systemAudio) == .optional)
    #expect(store.setupChecklistItems.filter { !$0.isComplete }.map(\.id) == [.sources])
    #expect(store.setupChecklistItems.first { $0.id == .sources }?.detail == "Enable Screen for Screen.")
}

@Test
@MainActor
func setupChecklistActionsApplyRecommendedCoreDefaults() throws {
    let store = StudioStore()
    store.setDestinationMode(.rtmp)

    for source in store.sources where source.isEnabled {
        store.toggleSource(source)
    }

    #expect(store.selectedSceneKind == .brb)
    #expect(store.setupChecklistItems.filter { !$0.isComplete }.map(\.id) == [.scene, .capture, .destination, .sources])

    store.selectRecommendedStartingScene()
    #expect(store.selectedSceneKind == .screenAndFace)
    #expect(store.setupChecklistItems.filter { !$0.isComplete }.map(\.id) == [.capture, .destination, .sources])

    store.setDestinationMode(.preview)
    #expect(store.destination.isPreviewSession)
    #expect(store.setupChecklistItems.filter { !$0.isComplete }.map(\.id) == [.capture, .sources])

    store.enableRecommendedSources()
    #expect(store.isSourceEnabled(.screen))
    #expect(store.isSourceEnabled(.camera))
    #expect(store.isSourceEnabled(.microphone))
    #expect(!store.isSourceEnabled(.systemAudio))
    #expect(store.setupChecklistItems.filter { !$0.isComplete }.map(\.id) == [.capture])
}

@Test
@MainActor
func setupChecklistEnablesOnlyNeededSourcesForSelectedScene() throws {
    let store = StudioStore()
    let screenScene = try #require(store.scenes.first { $0.kind == .screenOnly })

    store.selectScene(screenScene)

    for source in store.sources where source.isEnabled {
        store.toggleSource(source)
    }

    store.enableRecommendedSources()

    #expect(store.isSourceEnabled(.screen))
    #expect(store.isSourceEnabled(.microphone))
    #expect(!store.isSourceEnabled(.camera))
    #expect(!store.isSourceEnabled(.systemAudio))
    #expect(store.isSourceSetupReady)
    #expect(store.events[0].title == "Sources ready")
    #expect(store.events[0].detail == "Needed sources ready for Screen.")
}

@Test
@MainActor
func setupChecklistRaisesMutedNeededSources() throws {
    let pipeline = ConfigurableMediaPipeline()
    let signalProvider = ConfigurableSignalProvider()
    let store = StudioStore(mediaPipeline: pipeline, signalProvider: signalProvider)
    let screenScene = try #require(store.scenes.first { $0.kind == .screenOnly })
    let screen = try #require(store.sources.first { $0.kind == .screen })

    store.selectScene(screenScene)
    store.updateLevel(for: screen, level: 0)

    #expect(store.sourceLevel(.screen) == 0)
    #expect(!store.isSourceSetupReady)
    #expect(store.sourceSetupTitle == "0/1 ready")
    #expect(store.sourceSetupDetail == "Enable or raise Screen for Screen.")

    store.enableRecommendedSources()

    #expect(store.isSourceEnabled(.screen))
    #expect(store.sourceLevel(.screen) == 1)
    #expect(store.isSourceEnabled(.microphone))
    #expect(store.isSourceSetupReady)
    #expect(store.sourceSetupDetail.contains("Main Display"))
    #expect(store.events[0].title == "Sources ready")
    #expect(store.events[0].detail == "Needed sources ready for Screen.")
    #expect(signalProvider.lastConfiguration?.isScreenMotionEnabled == true)
    #expect(pipeline.lastConfiguration?.capturesMicrophone == true)
}

@Test
@MainActor
func captureStartRequiresReadinessForSystemLikePipelines() async {
    let readyReport = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted),
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(
        mediaPipeline: ReadinessGatedMediaPipeline(),
        captureDeviceProvider: FixedCaptureDeviceProvider(report: readyReport)
    )

    store.selectRecommendedStartingScene()

    #expect(!store.canStartStream)
    #expect(!store.canStartRecording)
    #expect(store.startBlockedReason == "Check capture permissions before starting.")
    #expect(store.captureStartBlockedReason == "Check capture permissions before starting.")

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.captureReadiness.state == .ready)
    #expect(store.startBlockedReason == nil)
    #expect(store.captureStartBlockedReason == nil)
    #expect(store.canStartStream)
    #expect(store.canStartRecording)
}

@Test
@MainActor
func realCaptureStartRequiresLiveSceneBeforeCaptureSetup() async {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted),
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(
        mediaPipeline: ReadinessGatedMediaPipeline(),
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report)
    )

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.selectedSceneKind == .brb)
    #expect(store.captureReadiness.state == .ready)
    #expect(store.captureStartBlockedReason == nil)
    #expect(store.startBlockedReason == "Choose Face, Screen + Face, or Screen before starting.")
    #expect(!store.canStartStream)
    #expect(!store.canStartRecording)

    store.selectRecommendedStartingScene()

    #expect(store.startBlockedReason == nil)
    #expect(store.canStartStream)
    #expect(store.canStartRecording)
}

@Test
@MainActor
func captureStartExplainsMissingSourcesBeforeStarting() {
    let store = StudioStore(mediaPipeline: ReadinessGatedMediaPipeline())

    store.selectRecommendedStartingScene()

    for source in store.sources where source.isEnabled {
        store.toggleSource(source)
    }

    #expect(!store.canStartStream)
    #expect(!store.canStartRecording)
    #expect(store.startBlockedReason == "Enable Screen and Camera for Screen + Face before starting.")
    #expect(store.captureStartBlockedReason == "Enable Screen and Camera for Screen + Face before starting.")
}

@Test
@MainActor
func zeroRequiredSourceLevelBlocksCaptureStart() async throws {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(
        mediaPipeline: ReadinessGatedMediaPipeline(),
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report)
    )
    let screenScene = try #require(store.scenes.first { $0.kind == .screenOnly })
    let screen = try #require(store.sources.first { $0.kind == .screen })

    store.selectScene(screenScene)
    store.updateLevel(for: screen, level: 0)
    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.sourceLevel(.screen) == 0)
    #expect(store.isSourceSetupReady == false)
    #expect(store.sourceSetupTitle == "0/1 ready")
    #expect(store.sourceSetupDetail == "Enable or raise Screen for Screen.")
    #expect(store.setupChecklistItems.first { $0.id == .sources }?.detail == "Enable or raise Screen for Screen.")
    #expect(!store.canStartStream)
    #expect(store.startBlockedReason == "Enable or raise Screen for Screen before starting.")

    store.updateLevel(for: screen, level: 0.5)

    #expect(store.canStartStream)
}

@Test
@MainActor
func captureStartRequiresSelectedSceneSourcesForSystemLikePipelines() async throws {
    let readyReport = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted),
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(
        mediaPipeline: ReadinessGatedMediaPipeline(),
        captureDeviceProvider: FixedCaptureDeviceProvider(report: readyReport)
    )
    let faceScene = try #require(store.scenes.first { $0.kind == .face })
    let cameraSource = try #require(store.sources.first { $0.kind == .camera })

    store.selectScene(faceScene)
    store.toggleSource(cameraSource)
    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.captureReadiness.state == .ready)
    #expect(!store.canStartStream)
    #expect(!store.canStartRecording)
    #expect(store.startBlockedReason == "Enable Camera for Face before starting.")
    #expect(store.captureStartBlockedReason == "Enable Camera for Face before starting.")

    store.toggleSource(cameraSource)

    #expect(store.canStartStream)
    #expect(store.canStartRecording)
    #expect(store.startBlockedReason == nil)
    #expect(store.captureStartBlockedReason == nil)
}

@Test
@MainActor
func realCaptureVideoStartRequiresScreenSceneWhenPipelineUsesScreenCaptureKit() async throws {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "screen-permission", kind: .display, name: "Screen Capture", detail: "Screen Recording permission is not visible to this launch.", permission: .notDetermined),
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted)
        ],
        summary: "1 source permission needs attention."
    )
    let pipeline = ScreenVideoGatedMediaPipeline(streamTransport: .rtmpPublish)
    let store = StudioStore(
        mediaPipeline: pipeline,
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report)
    )
    let faceScene = try #require(store.scenes.first { $0.kind == .face })

    store.selectScene(faceScene)
    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.captureReadiness.state == .ready)
    #expect(store.streamStartBlockedReason == nil)
    #expect(store.recordingStartBlockedReason == "Choose Screen or Screen + Face before starting a local recording.")
    #expect(store.canStartStream)
    #expect(!store.canStartRecording)

    store.destination = StreamDestination(name: "RTMP", rtmpURL: "rtmp://127.0.0.1/live/stream")

    #expect(!store.canStartStream)
    #expect(store.streamStartBlockedReason == "Choose Screen or Screen + Face before starting real capture.")
    #expect(store.startBlockedReason == "Choose Screen or Screen + Face before starting real capture.")
}

@Test
@MainActor
func realMediaPipelineAllowsScreenAndFaceRecordingAndRTMPStreamingWhenPublishCompositionExists() async throws {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted),
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let pipeline = ComposedScreenVideoMediaPipeline(streamTransport: .rtmpPublish)
    let store = StudioStore(
        mediaPipeline: pipeline,
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report)
    )
    let screenAndFaceScene = try #require(store.scenes.first { $0.kind == .screenAndFace })

    store.selectScene(screenAndFaceScene)
    store.destination = StreamDestination(name: "RTMP", rtmpURL: "rtmp://127.0.0.1/live/stream")
    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.captureReadiness.state == .ready)
    #expect(store.canStartStream)
    #expect(store.canStartRecording)
    #expect(store.streamStartBlockedReason == nil)
    #expect(store.recordingStartBlockedReason == nil)

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.streamState == .live)
    #expect(pipeline.startCount == 1)
    #expect(pipeline.configurationAtStartStream?.sceneKind == .screenAndFace)
}

@Test
@MainActor
func previewPipelinesCanStartWithoutCapturePreflight() {
    let store = StudioStore(mediaPipeline: PreviewMediaPipeline())

    #expect(store.captureReadiness.state == .unchecked)
    #expect(store.startBlockedReason == nil)
    #expect(store.captureStartBlockedReason == nil)
    #expect(store.canStartStream)
    #expect(store.canStartRecording)
}

@Test
@MainActor
func captureScanSuppressesDuplicateScansWhileInFlight() async {
    let provider = DelayedCountingCaptureDeviceProvider(
        report: CapturePreflightReport(
            devices: [
                CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted)
            ],
            summary: "Capture sources are ready."
        )
    )
    let store = StudioStore(captureDeviceProvider: provider)

    store.scanCaptureDevices()
    store.scanCaptureDevices()

    #expect(store.isScanningCapture)

    try? await Task.sleep(for: .milliseconds(80))

    #expect(await provider.scanCount() == 1)
    #expect(!store.isScanningCapture)
    #expect(store.hasRunInitialCaptureScan)
    #expect(store.captureReport.summary == "Capture sources are ready.")
}

@Test
@MainActor
func duplicateCompletedCaptureScansDoNotRepublishReport() async {
    let pipeline = ConfigurableMediaPipeline()
    let signalProvider = ConfigurableSignalProvider()
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report),
        signalProvider: signalProvider
    )

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    let eventCount = store.events.count
    let mediaUpdateCount = pipeline.updateCount
    let signalUpdateCount = signalProvider.updateCount

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.captureReport == report)
    #expect(store.events.count == eventCount)
    #expect(store.events.filter { $0.title == "Capture scan" }.count == 1)
    #expect(pipeline.updateCount == mediaUpdateCount)
    #expect(signalProvider.updateCount == signalUpdateCount)
}

@Test
@MainActor
func activeStreamSkipsCaptureRescan() async {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let provider = SequencedCaptureDeviceProvider(reports: [
        report,
        CapturePreflightReport(
            devices: [
                CaptureDeviceInfo(id: "display-8", kind: .display, name: "External Display", detail: "1920x1080", permission: .granted)
            ],
            summary: "External display ready."
        )
    ])
    let store = StudioStore(
        mediaPipeline: SpyMediaPipeline(),
        captureDeviceProvider: provider
    )

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.isLive)
    #expect(!store.canScanCaptureDevices)
    #expect(store.captureScanBlockedReason == "Stop preview, stream, or recording before checking capture devices.")

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.captureReport == report)
    #expect(await provider.scanCount() == 1)
}

@Test
@MainActor
func selectingScreenCaptureTargetUpdatesMediaAndSignals() async {
    let pipeline = ConfigurableMediaPipeline()
    let signalProvider = ConfigurableSignalProvider()
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted),
            CaptureDeviceInfo(id: "window-42", kind: .window, name: "Slides", detail: "Keynote", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report),
        signalProvider: signalProvider
    )

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))
    let windowTarget = ScreenCaptureTarget(id: "window-42", kind: .window, name: "Slides", detail: "Keynote")
    store.selectScreenCaptureTarget(windowTarget)

    #expect(store.selectedScreenCaptureTarget == windowTarget)
    #expect(pipeline.lastConfiguration?.screenCaptureTarget == windowTarget)
    #expect(signalProvider.lastConfiguration?.screenCaptureTarget == windowTarget)
    #expect(store.events.contains { $0.title == "Screen target" && $0.detail == "Slides - Keynote" })
}

@Test
@MainActor
func availableInputDevicesListOnlyGrantedDevices() async {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "camera-front", kind: .camera, name: "Front Camera", permission: .granted),
            CaptureDeviceInfo(id: "camera-ext", kind: .camera, name: "External Camera", permission: .denied),
            CaptureDeviceInfo(id: "microphone-built", kind: .microphone, name: "Built-in Mic", permission: .granted),
            CaptureDeviceInfo(id: "microphone-usb", kind: .microphone, name: "USB Mic", permission: .notDetermined),
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(captureDeviceProvider: FixedCaptureDeviceProvider(report: report))

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.availableCameraDevices.map(\.id) == ["camera-front"])
    #expect(store.availableMicrophoneDevices.map(\.id) == ["microphone-built"])
}

@Test
@MainActor
func captureScanSelectsFirstInputDevicesAndConfiguresPipeline() async {
    let pipeline = ConfigurableMediaPipeline()
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "camera-front", kind: .camera, name: "Front Camera", permission: .granted),
            CaptureDeviceInfo(id: "camera-ext", kind: .camera, name: "External Camera", permission: .granted),
            CaptureDeviceInfo(id: "microphone-built", kind: .microphone, name: "Built-in Mic", permission: .granted),
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report)
    )

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.selectedCameraDeviceID == "camera-front")
    #expect(store.selectedMicrophoneDeviceID == "microphone-built")
    #expect(pipeline.lastConfiguration?.cameraDeviceID == "camera-front")
    #expect(pipeline.lastConfiguration?.microphoneDeviceID == "microphone-built")
}

@Test
@MainActor
func selectingCameraDeviceUpdatesMediaConfiguration() async {
    let pipeline = ConfigurableMediaPipeline()
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "camera-front", kind: .camera, name: "Front Camera", permission: .granted),
            CaptureDeviceInfo(id: "camera-ext", kind: .camera, name: "External Camera", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report)
    )

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))
    store.selectCameraDevice(id: "camera-ext")

    #expect(store.selectedCameraDeviceID == "camera-ext")
    #expect(pipeline.lastConfiguration?.cameraDeviceID == "camera-ext")
    #expect(store.events.contains { $0.title == "Camera device" && $0.detail == "External Camera" })
}

@Test
@MainActor
func selectingMicrophoneDeviceUpdatesMediaConfiguration() async {
    let pipeline = ConfigurableMediaPipeline()
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "microphone-built", kind: .microphone, name: "Built-in Mic", permission: .granted),
            CaptureDeviceInfo(id: "microphone-usb", kind: .microphone, name: "USB Mic", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report)
    )

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))
    store.selectMicrophoneDevice(id: "microphone-usb")

    #expect(store.selectedMicrophoneDeviceID == "microphone-usb")
    #expect(pipeline.lastConfiguration?.microphoneDeviceID == "microphone-usb")
    #expect(store.events.contains { $0.title == "Mic device" && $0.detail == "USB Mic" })
}

@Test
@MainActor
func savedCameraDevicePreferenceRestoresAfterScan() async {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "camera-front", kind: .camera, name: "Front Camera", permission: .granted),
            CaptureDeviceInfo(id: "camera-ext", kind: .camera, name: "External Camera", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(captureDeviceProvider: FixedCaptureDeviceProvider(report: report))

    store.applySavedCameraDeviceIDPreference("camera-ext")
    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.selectedCameraDeviceID == "camera-ext")
}

@Test
@MainActor
func missingCameraDevicePreferenceFallsBackToFirstAvailable() async {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "camera-front", kind: .camera, name: "Front Camera", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(captureDeviceProvider: FixedCaptureDeviceProvider(report: report))

    store.applySavedCameraDeviceIDPreference("camera-missing")
    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.selectedCameraDeviceID == "camera-front")
}

@Test
@MainActor
func inputDeviceSelectionIsBlockedWhileStreamIsConnecting() async {
    let pipeline = DelayedStartMediaPipeline()
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "camera-front", kind: .camera, name: "Front Camera", permission: .granted),
            CaptureDeviceInfo(id: "camera-ext", kind: .camera, name: "External Camera", permission: .granted),
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report)
    )

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))
    store.startStream()
    try? await Task.sleep(for: .milliseconds(10))

    #expect(store.isStreamConnecting)
    #expect(!store.canSelectInputDevice)

    store.selectCameraDevice(id: "camera-ext")

    #expect(store.selectedCameraDeviceID == "camera-front")
}

@Test
@MainActor
func applyingDestinationPresetConfiguresRTMPEndpoint() {
    let store = StudioStore(captureDeviceProvider: FixedCaptureDeviceProvider(report: CapturePreflightReport()))

    store.applyDestinationPreset(.twitch)

    #expect(store.destination.mode == .rtmp)
    #expect(store.destination.name == "Twitch")
    #expect(store.destination.rtmpURL == StreamPlatformPreset.twitch.ingestURL)
    #expect(store.matchingDestinationPreset == .twitch)
    #expect(store.events.contains { $0.title == "Destination preset" && $0.detail == "Twitch" })
}

@Test
@MainActor
func applyingPresetWithoutFixedIngestLeavesURLEditable() {
    let store = StudioStore(captureDeviceProvider: FixedCaptureDeviceProvider(report: CapturePreflightReport()))

    store.applyDestinationPreset(.x)

    #expect(store.destination.mode == .rtmp)
    #expect(store.destination.name == "X")
    #expect(store.destination.rtmpURL.isEmpty)
    #expect(store.matchingDestinationPreset == nil)
}

@Test
@MainActor
func matchingDestinationPresetDetectsConfiguredURL() {
    let store = StudioStore(captureDeviceProvider: FixedCaptureDeviceProvider(report: CapturePreflightReport()))

    store.destination = StreamDestination(
        mode: .rtmp,
        name: "Channel",
        rtmpURL: "rtmp://a.rtmp.youtube.com/live2/abcd-efgh"
    )

    #expect(store.matchingDestinationPreset == .youtube)
}

@Test
@MainActor
func destinationPresetCannotBeAppliedWhileStreamIsConnecting() async {
    let pipeline = DelayedStartMediaPipeline()
    let store = StudioStore(
        mediaPipeline: pipeline,
        captureDeviceProvider: FixedCaptureDeviceProvider(report: CapturePreflightReport())
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(10))

    #expect(store.isStreamConnecting)
    #expect(!store.canEditDestination)

    store.applyDestinationPreset(.twitch)

    #expect(store.destination.mode == .preview)
}

@Test
@MainActor
func reapplyingPresetPreservesEnteredStreamKey() {
    let store = StudioStore(captureDeviceProvider: FixedCaptureDeviceProvider(report: CapturePreflightReport()))
    store.applyDestinationPreset(.twitch)
    store.destination.rtmpURL = "rtmp://live.twitch.tv/app/live_123_secretkey"

    store.applyDestinationPreset(.twitch)

    #expect(store.destination.rtmpURL == "rtmp://live.twitch.tv/app/live_123_secretkey")
}

@Test
@MainActor
func switchingToAccountSpecificPresetClearsOtherPlatformURL() {
    let store = StudioStore(captureDeviceProvider: FixedCaptureDeviceProvider(report: CapturePreflightReport()))
    store.destination = StreamDestination(
        mode: .rtmp,
        name: "Twitch",
        rtmpURL: "rtmp://live.twitch.tv/app/live_123_secretkey"
    )

    store.applyDestinationPreset(.x)

    #expect(store.destination.name == "X")
    #expect(store.destination.rtmpURL.isEmpty)
}

@Test
@MainActor
func applyingCustomPresetKeepsUserTypedURL() {
    let store = StudioStore(captureDeviceProvider: FixedCaptureDeviceProvider(report: CapturePreflightReport()))
    store.destination = StreamDestination(
        mode: .rtmp,
        name: "My Server",
        rtmpURL: "rtmp://stream.example.com/live/streamkey"
    )

    store.applyDestinationPreset(.custom)

    #expect(store.destination.rtmpURL == "rtmp://stream.example.com/live/streamkey")
}

@Test
@MainActor
func kickPresetRequiresPastedEndpoint() {
    #expect(StreamPlatformPreset.kick.ingestURL == nil)
}

@Test
func presetBaseURLIsNotPersistableUntilStreamKeyAdded() {
    let draftBase = StreamDestination(mode: .rtmp, name: "Twitch", rtmpURL: StreamPlatformPreset.twitch.ingestURL ?? "")
    #expect(!draftBase.isPersistableEndpoint)

    let complete = StreamDestination(mode: .rtmp, name: "Twitch", rtmpURL: "rtmp://live.twitch.tv/app/live_key")
    #expect(complete.isPersistableEndpoint)

    #expect(!StreamDestination().isPersistableEndpoint)
}

@Test
@MainActor
func screenCaptureTargetCannotChangeWhileRecording() async {
    let pipeline = SpyMediaPipeline()
    let displayTarget = ScreenCaptureTarget(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964")
    let windowTarget = ScreenCaptureTarget(id: "window-42", kind: .window, name: "Slides", detail: "Keynote")
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: displayTarget.id, kind: .display, name: displayTarget.name, detail: displayTarget.detail, permission: .granted),
            CaptureDeviceInfo(id: windowTarget.id, kind: .window, name: windowTarget.name, detail: windowTarget.detail, permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report)
    )

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))
    store.startRecording()
    try? await Task.sleep(for: .milliseconds(50))
    store.selectScreenCaptureTarget(windowTarget)

    #expect(!store.canEditScreenCaptureTarget)
    #expect(store.selectedScreenCaptureTarget == displayTarget)
}

@Test
@MainActor
func screenCaptureTargetCannotChangeWhileStreamIsConnectingOrLive() async {
    let pipeline = DelayedStartMediaPipeline()
    let displayTarget = ScreenCaptureTarget(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964")
    let windowTarget = ScreenCaptureTarget(id: "window-42", kind: .window, name: "Slides", detail: "Keynote")
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: displayTarget.id, kind: .display, name: displayTarget.name, detail: displayTarget.detail, permission: .granted),
            CaptureDeviceInfo(id: windowTarget.id, kind: .window, name: windowTarget.name, detail: windowTarget.detail, permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report)
    )

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))
    store.startStream()
    try? await Task.sleep(for: .milliseconds(10))

    #expect(store.isStreamConnecting)
    #expect(!store.canEditScreenCaptureTarget)

    store.selectScreenCaptureTarget(windowTarget)

    #expect(store.selectedScreenCaptureTarget == displayTarget)

    try? await Task.sleep(for: .milliseconds(100))

    #expect(store.streamState == .live)
    #expect(!store.canEditScreenCaptureTarget)

    store.selectScreenCaptureTarget(windowTarget)

    #expect(store.selectedScreenCaptureTarget == displayTarget)
}

@Test
@MainActor
func captureRescanDoesNotChangeScreenTargetWhileRecording() async {
    let pipeline = ConfigurableMediaPipeline()
    let signalProvider = ConfigurableSignalProvider()
    let displayTarget = ScreenCaptureTarget(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964")
    let windowTarget = ScreenCaptureTarget(id: "window-42", kind: .window, name: "Slides", detail: "Keynote")
    let provider = SequencedCaptureDeviceProvider(reports: [
        CapturePreflightReport(
            devices: [
                CaptureDeviceInfo(id: displayTarget.id, kind: .display, name: displayTarget.name, detail: displayTarget.detail, permission: .granted)
            ],
            summary: "Display ready."
        ),
        CapturePreflightReport(
            devices: [
                CaptureDeviceInfo(id: windowTarget.id, kind: .window, name: windowTarget.name, detail: windowTarget.detail, permission: .granted)
            ],
            summary: "Window ready."
        )
    ])
    let store = StudioStore(
        mediaPipeline: pipeline,
        captureDeviceProvider: provider,
        signalProvider: signalProvider
    )

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))
    store.startRecording()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.selectedScreenCaptureTarget == displayTarget)
    #expect(pipeline.lastConfiguration?.screenCaptureTarget == displayTarget)
    #expect(signalProvider.lastConfiguration?.screenCaptureTarget == displayTarget)
    #expect(!store.canScanCaptureDevices)

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(!store.canEditScreenCaptureTarget)
    #expect(store.captureScanBlockedReason == "Stop preview, stream, or recording before checking capture devices.")
    #expect(store.captureReport.summary == "Display ready.")
    #expect(store.selectedScreenCaptureTarget == displayTarget)
    #expect(pipeline.lastConfiguration?.screenCaptureTarget == displayTarget)
    #expect(signalProvider.lastConfiguration?.screenCaptureTarget == displayTarget)
    #expect(await provider.scanCount() == 1)
}

@Test
@MainActor
func adaptivePerformanceModeUsesBalancedWhenPressureIsNominal() {
    let pipeline = ConfigurableMediaPipeline()
    let signalProvider = ConfigurableSignalProvider()
    let pressure = SystemPressureSnapshot(thermalPressure: .nominal, memoryUsedMB: 512, physicalMemoryMB: 16_384)
    let store = StudioStore(
        mediaPipeline: pipeline,
        signalProvider: signalProvider,
        performanceMonitor: FixedSystemPerformanceMonitor(snapshot: pressure),
        preferences: StudioPreferences(performanceMode: .adaptive)
    )

    store.advanceDirector()

    #expect(store.effectivePerformanceMode == .balanced)
    #expect(pipeline.lastConfiguration == expectedMediaConfiguration(.balanced))
    #expect(signalProvider.lastConfiguration == StudioPerformanceMode.balanced.signalSamplingConfiguration)
}

@Test
@MainActor
func adaptivePerformanceModeUsesEfficiencyUnderPressure() {
    let pipeline = ConfigurableMediaPipeline()
    let signalProvider = ConfigurableSignalProvider()
    let pressure = SystemPressureSnapshot(thermalPressure: .serious, memoryUsedMB: 900, physicalMemoryMB: 16_384)
    let store = StudioStore(
        mediaPipeline: pipeline,
        signalProvider: signalProvider,
        performanceMonitor: FixedSystemPerformanceMonitor(snapshot: pressure),
        preferences: StudioPreferences(performanceMode: .adaptive)
    )

    store.advanceDirector()

    #expect(store.effectivePerformanceMode == .efficiency)
    #expect(pipeline.lastConfiguration == expectedMediaConfiguration(.efficiency))
    #expect(signalProvider.lastConfiguration == StudioPerformanceMode.efficiency.signalSamplingConfiguration)
}

@Test
@MainActor
func adaptivePerformanceModeUsesEfficiencyWhenCaptureHealthDrops() async {
    let pipeline = ConfigurableMediaPipeline()
    let signalProvider = ConfigurableSignalProvider()
    pipeline.currentHealth = StreamHealth(
        bitrateKbps: 6_200,
        droppedFrames: 4,
        captureFPS: 30,
        audioLevel: 0.2,
        roundTripMs: 18
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        signalProvider: signalProvider,
        preferences: StudioPreferences(performanceMode: .adaptive)
    )
    store.directorMode = .paused

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.advanceDirector()

    #expect(store.effectivePerformanceMode == .efficiency)
    #expect(pipeline.lastConfiguration == expectedMediaConfiguration(.efficiency))
    #expect(signalProvider.lastConfiguration == StudioPerformanceMode.efficiency.signalSamplingConfiguration)
    #expect(store.streamState == .degraded("Dropped frames detected; reducing capture cost."))
}

@Test
@MainActor
func pausedLiveStreamSamplesCaptureHealthWithoutDirectorLoop() async {
    let pipeline = ConfigurableMediaPipeline()
    let signalProvider = ConfigurableSignalProvider()
    pipeline.currentHealth = StreamHealth(
        bitrateKbps: 6_200,
        droppedFrames: 4,
        captureFPS: 30,
        audioLevel: 0.2,
        roundTripMs: 18
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        signalProvider: signalProvider,
        preferences: StudioPreferences(performanceMode: .adaptive)
    )
    store.directorMode = .paused

    store.startStream()
    try? await Task.sleep(for: .milliseconds(80))

    #expect(signalProvider.startCount == 0)
    #expect(store.effectivePerformanceMode == .efficiency)
    #expect(pipeline.lastConfiguration == expectedMediaConfiguration(.efficiency))
    #expect(store.streamState == .degraded("Dropped frames detected; reducing capture cost."))
}

@Test
@MainActor
func recordingOnlySamplesCaptureHealthWithoutDirectorLoop() async {
    let pipeline = ConfigurableMediaPipeline()
    pipeline.currentHealth = StreamHealth(
        bitrateKbps: 0,
        droppedFrames: 4,
        captureFPS: 30,
        audioLevel: 0.2,
        roundTripMs: 0
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        preferences: StudioPreferences(performanceMode: .adaptive)
    )

    store.startRecording()
    try? await Task.sleep(for: .milliseconds(80))

    #expect(store.recordingState == .recording)
    #expect(store.streamState == .offline)
    #expect(store.effectivePerformanceMode == .efficiency)
    #expect(pipeline.lastConfiguration == expectedMediaConfiguration(.efficiency))
    #expect(store.events.contains { $0.title == "Capture health" })
}

@Test
@MainActor
func adaptivePerformanceModeRecoversWhenCaptureHealthStabilizes() async {
    let pipeline = ConfigurableMediaPipeline()
    let signalProvider = ConfigurableSignalProvider()
    pipeline.currentHealth = StreamHealth(
        bitrateKbps: 6_200,
        droppedFrames: 4,
        captureFPS: 30,
        audioLevel: 0.2,
        roundTripMs: 18
    )
    let store = StudioStore(
        mediaPipeline: pipeline,
        signalProvider: signalProvider,
        preferences: StudioPreferences(performanceMode: .adaptive)
    )
    store.directorMode = .paused

    store.startStream()
    try? await Task.sleep(for: .milliseconds(80))

    #expect(store.effectivePerformanceMode == .efficiency)
    #expect(pipeline.lastConfiguration == expectedMediaConfiguration(.efficiency))
    #expect(signalProvider.lastConfiguration == StudioPerformanceMode.efficiency.signalSamplingConfiguration)
    #expect(store.streamState == .degraded("Dropped frames detected; reducing capture cost."))

    pipeline.currentHealth = StreamHealth(
        bitrateKbps: 6_200,
        droppedFrames: 4,
        captureFPS: 30,
        audioLevel: 0.2,
        roundTripMs: 18
    )
    store.advanceDirector()

    #expect(store.effectivePerformanceMode == .efficiency)
    #expect(pipeline.lastConfiguration == expectedMediaConfiguration(.efficiency))
    #expect(signalProvider.lastConfiguration == StudioPerformanceMode.efficiency.signalSamplingConfiguration)
    #expect(store.streamState == .degraded("Dropped frames detected; reducing capture cost."))

    store.advanceDirector()

    #expect(store.effectivePerformanceMode == .balanced)
    #expect(pipeline.lastConfiguration == expectedMediaConfiguration(.balanced))
    #expect(signalProvider.lastConfiguration == StudioPerformanceMode.balanced.signalSamplingConfiguration)
    #expect(store.streamState == .live)
}

@Test
@MainActor
func studioStoreUsesPreviewTransportForDefaultDestination() {
    let pipeline = ConfigurableMediaPipeline(streamTransport: .rtmpPublish)
    let store = StudioStore(mediaPipeline: pipeline)

    #expect(store.streamTransport == .preview)
    #expect(store.streamStatusDetail == "Ready")
}

@Test
@MainActor
func studioStoreUpdatesDestinationModeWithoutStartingStream() {
    let pipeline = ConfigurableMediaPipeline(streamTransport: .rtmpPublish)
    let store = StudioStore(mediaPipeline: pipeline)

    store.setDestinationMode(.rtmp)

    #expect(store.destination.mode == .rtmp)
    #expect(store.destination.name == "RTMP Destination")
    #expect(store.destination.rtmpURL.isEmpty)
    #expect(store.streamTransport == .rtmpPublish)
    #expect(!store.canStartStream)
    #expect(store.canEditDestination)
    #expect(store.streamStatusDetail == "Enter a valid RTMP or RTMPS URL.")

    store.destination.rtmpURL = "rtmps://live.example.com/app/sk_live_secret"
    store.setDestinationMode(.preview)

    #expect(store.destination.mode == .preview)
    #expect(store.destination.name == "Preview Session")
    #expect(store.destination.rtmpURL == "rtmps://live.example.com/app/sk_live_secret")
    #expect(store.streamTransport == .preview)
}

@Test
@MainActor
func savedDestinationRestoresConfiguredRTMP() {
    let pipeline = ConfigurableMediaPipeline(streamTransport: .rtmpPublish)
    let store = StudioStore(mediaPipeline: pipeline)

    store.applySavedDestination(
        StreamDestination(
            mode: .rtmp,
            name: "Twitch",
            rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
        )
    )

    #expect(store.destination.mode == .rtmp)
    #expect(store.destination.name == "Twitch")
    #expect(store.destination.safeDisplayDetail == "rtmps://live.example.com/app/****")
    #expect(store.streamTransport == .rtmpPublish)
    #expect(store.canStartStream)
}

@Test
@MainActor
func redundantDestinationWritesDoNotResolveTransport() {
    let pipeline = TransportCountingMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)
    let transportReadCount = pipeline.transportReadCount

    store.destination = store.destination

    #expect(store.destination.mode == .preview)
    #expect(store.streamTransport == .preview)
    #expect(pipeline.transportReadCount == transportReadCount)
}

@Test
@MainActor
func destinationModeChangesResolveTransportOnlyWhenNeeded() {
    let pipeline = TransportCountingMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)

    #expect(store.streamTransport == .preview)
    #expect(pipeline.transportReadCount == 0)

    store.setDestinationMode(.rtmp)

    #expect(store.destination.mode == .rtmp)
    #expect(store.destination.name == "RTMP Destination")
    #expect(store.destination.rtmpURL.isEmpty)
    #expect(store.streamTransport == .rtmpPublish)
    #expect(pipeline.transportReadCount == 1)

    store.setDestinationMode(.preview)

    #expect(store.destination.mode == .preview)
    #expect(store.destination.name == "Preview Session")
    #expect(store.streamTransport == .preview)
    #expect(pipeline.transportReadCount == 1)
}

@Test
@MainActor
func invalidRTMPDestinationDoesNotStartStream() async {
    let pipeline = ConfigurableMediaPipeline(streamTransport: .rtmpPublish)
    let store = StudioStore(mediaPipeline: pipeline)
    store.setDestinationMode(.rtmp)

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.streamState == .offline)
    #expect(!store.canStartStream)
    #expect(store.canEditDestination)
    #expect(pipeline.configurationAtStartStream == nil)
    #expect(store.streamStatusDetail == "Enter a valid RTMP or RTMPS URL.")

    store.destination.rtmpURL = "rtmps://live.example.com/app/sk_live_secret"

    #expect(store.canStartStream)
}

@Test
@MainActor
func invalidRTMPDestinationCanBeEditedBackToPreview() {
    let pipeline = ConfigurableMediaPipeline(streamTransport: .rtmpPublish)
    let store = StudioStore(mediaPipeline: pipeline)

    store.setDestinationMode(.rtmp)
    #expect(store.destination.mode == .rtmp)
    #expect(!store.canStartStream)
    #expect(store.canEditDestination)

    store.setDestinationMode(.preview)

    #expect(store.destination.mode == .preview)
    #expect(store.destination.name == "Preview Session")
    #expect(store.canStartStream)
    #expect(store.canEditDestination)
    #expect(store.streamTransport == .preview)
}

@Test
@MainActor
func studioStoreReportsTransportAwareStreamStatusDetails() async {
    let pipeline = ConfigurableMediaPipeline(streamTransport: .rtmpPublish)
    let store = StudioStore(mediaPipeline: pipeline)

    store.startStream()
    #expect(store.streamStatusDetail == "Starting local preview session")
    try? await Task.sleep(for: .milliseconds(50))
    #expect(store.streamStatusDetail == "Local preview running")

    store.stopStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )
    store.startStream()
    #expect(store.streamStatusDetail == "Connecting RTMP publisher (attempt 1/3)")
    try? await Task.sleep(for: .milliseconds(50))
    #expect(store.streamStatusDetail == "Publishing media")
}

@Test
@MainActor
func previewStreamStartsWithoutArtificialDelay() async {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted),
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(
        mediaPipeline: SystemMediaPipeline(),
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report)
    )

    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))
    store.selectRecommendedStartingScene()

    store.startStream()

    #expect(store.streamStatusDetail == "Starting local preview session")
    for _ in 0..<10 {
        if store.streamState == .live { break }
        await Task.yield()
    }
    #expect(store.streamState == .live)
    #expect(store.streamStatusDetail == "Local preview running")

    store.stopStream()
}

@Test
@MainActor
func failedStreamStartStaysRetryableAndEditable() async {
    let pipeline = RecoveringMediaPipeline()
    pipeline.errorToThrow = TestStreamError(message: "Bad endpoint")
    let store = StudioStore(mediaPipeline: pipeline, streamStartRetryPolicy: .none)
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.streamState == .failed("Bad endpoint"))
    #expect(store.streamStatusDetail == "Bad endpoint")
    #expect(!store.isLive)
    #expect(store.canStartStream)
    #expect(store.canEditDestination)
    #expect(pipeline.startCount == 1)

    store.destination.rtmpURL = "rtmps://live.example.com/app/sk_live_recovered"
    pipeline.errorToThrow = nil
    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.streamState == .live)
    #expect(store.isLive)
    #expect(pipeline.startCount == 2)
}

@Test
@MainActor
func editingEndpointAfterFailedStreamClearsStaleFailure() async {
    let pipeline = RecoveringMediaPipeline()
    pipeline.errorToThrow = TestStreamError(message: "Bad endpoint")
    let store = StudioStore(mediaPipeline: pipeline, streamStartRetryPolicy: .none)
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.streamState == .failed("Bad endpoint"))
    #expect(store.streamStatusDetail == "Bad endpoint")

    store.destination.rtmpURL = "rtmps://live.example.com/app/sk_live_recovered"

    #expect(store.streamState == .offline)
    #expect(store.streamStatusDetail == "Ready")
    #expect(store.canStartStream)
    #expect(store.canEditDestination)
}

@Test
@MainActor
func editingEndpointAfterFailedStreamSurfacesNewValidationError() async {
    let pipeline = RecoveringMediaPipeline()
    pipeline.errorToThrow = TestStreamError(message: "Bad endpoint")
    let store = StudioStore(mediaPipeline: pipeline, streamStartRetryPolicy: .none)
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    store.destination.rtmpURL = "not an rtmp endpoint"

    #expect(store.streamState == .offline)
    #expect(!store.canStartStream)
    #expect(store.canEditDestination)
    #expect(store.streamStatusDetail == "Enter a valid RTMP or RTMPS URL.")
}

@Test
func streamStartRetryPolicyUsesBoundedBackoff() {
    let policy = StreamStartRetryPolicy(maxAttempts: 3, backoffMilliseconds: [10])

    #expect(policy.maxAttempts == 3)
    #expect(policy.delayBeforeRetry(afterFailedAttempt: 1) == .milliseconds(10))
    #expect(policy.delayBeforeRetry(afterFailedAttempt: 2) == .milliseconds(10))
    #expect(policy.delayBeforeRetry(afterFailedAttempt: 3) == nil)
}

@Test
@MainActor
func rtmpStreamStartRetriesTransientFailures() async {
    let pipeline = FlakyStartMediaPipeline(failuresBeforeSuccess: 2)
    let store = StudioStore(
        mediaPipeline: pipeline,
        streamStartRetryPolicy: StreamStartRetryPolicy(maxAttempts: 3, backoffMilliseconds: [1, 1])
    )
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(80))

    #expect(store.streamState == .live)
    #expect(store.streamStartAttempt == 3)
    #expect(store.streamStartMaxAttempts == 3)
    #expect(pipeline.startCount == 3)
    #expect(store.events.contains { $0.title == "Retrying RTMP Publish" })
}

@Test
@MainActor
func streamStartCancellationDoesNotRetry() async {
    let pipeline = RecoveringMediaPipeline()
    pipeline.errorToThrow = CancellationError()
    let store = StudioStore(
        mediaPipeline: pipeline,
        streamStartRetryPolicy: StreamStartRetryPolicy(maxAttempts: 3, backoffMilliseconds: [1, 1])
    )
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(pipeline.startCount == 1)
    #expect(store.streamStartAttempt == 1)
    #expect(!store.events.contains { $0.title == "Retrying RTMP Publish" })
}

@Test
@MainActor
func previewStreamStartDoesNotRetryFailures() async {
    let pipeline = FlakyStartMediaPipeline(failuresBeforeSuccess: 1, streamTransport: .preview)
    let store = StudioStore(
        mediaPipeline: pipeline,
        streamStartRetryPolicy: StreamStartRetryPolicy(maxAttempts: 3, backoffMilliseconds: [1, 1])
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.streamState == .failed("Transient start failure 1"))
    #expect(store.streamStartAttempt == 1)
    #expect(store.streamStartMaxAttempts == 1)
    #expect(pipeline.startCount == 1)
}

@Test
@MainActor
func cancelDuringRTMPRetryLeavesStreamOffline() async {
    let pipeline = FlakyStartMediaPipeline(failuresBeforeSuccess: 5)
    let store = StudioStore(
        mediaPipeline: pipeline,
        streamStartRetryPolicy: StreamStartRetryPolicy(maxAttempts: 3, backoffMilliseconds: [100, 100])
    )
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(20))
    store.stopStream()
    try? await Task.sleep(for: .milliseconds(80))

    #expect(store.streamState == .offline)
    #expect(!store.isLive)
    #expect(store.streamStartAttempt == 0)
    #expect(store.streamStartMaxAttempts == 1)
    #expect(pipeline.startCount == 1)
}

@Test
@MainActor
func stopStreamIsIdempotentWhilePipelineStops() async {
    let pipeline = DelayedStopMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)

    store.startStream()
    try? await Task.sleep(for: .milliseconds(20))

    #expect(store.streamState == .live)

    store.stopStream()

    #expect(store.isStreamStopping)
    #expect(!store.canStopStream)
    #expect(!store.canStartStream)
    #expect(store.streamStatusDetail == "Stopping stream")

    store.stopStream()
    try? await Task.sleep(for: .milliseconds(20))

    #expect(pipeline.stopCount == 1)

    try? await Task.sleep(for: .milliseconds(100))

    #expect(!store.isStreamStopping)
    #expect(store.streamState == .offline)
    #expect(store.canStartStream)
    #expect(pipeline.stopCount == 1)
    #expect(store.events.filter { $0.title == "Offline" }.count == 1)
}

@Test
@MainActor
func connectingStreamStartSuppressesDuplicateStartsAndDestinationEdits() async {
    let pipeline = DelayedStartMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)

    store.startStream()
    try? await Task.sleep(for: .milliseconds(10))

    #expect(store.isStreamConnecting)
    #expect(!store.canStartStream)
    #expect(store.canStopStream)
    #expect(!store.canEditDestination)

    store.startStream()
    store.setDestinationMode(.rtmp)
    store.destination = StreamDestination(
        name: "Edited while connecting",
        rtmpURL: "rtmps://live.example.com/app/sk_live_changed"
    )

    #expect(store.destination.mode == .preview)
    #expect(store.destination.name == "Preview Session")
    #expect(pipeline.startCount == 1)

    try? await Task.sleep(for: .milliseconds(100))

    #expect(store.streamState == .live)
    #expect(!store.canStartStream)
    #expect(store.canStopStream)
    #expect(!store.canEditDestination)
    #expect(pipeline.startCount == 1)
}

@Test
@MainActor
func liveStreamRejectsDestinationMutation() async {
    let pipeline = DelayedStartMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)

    store.startStream()
    try? await Task.sleep(for: .milliseconds(100))

    #expect(store.streamState == .live)
    #expect(!store.canEditDestination)

    store.destination = StreamDestination(
        name: "Edited while live",
        rtmpURL: "rtmps://live.example.com/app/sk_live_changed"
    )
    store.destination.name = "Renamed while live"
    store.setDestinationMode(.rtmp)

    #expect(store.destination.mode == .preview)
    #expect(store.destination.name == "Preview Session")
    #expect(store.destination.rtmpURL == "preview")
}

@Test
@MainActor
func connectingStreamStartSuppressesRecordingStart() async {
    let pipeline = DelayedStartMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)

    store.startStream()
    try? await Task.sleep(for: .milliseconds(10))

    #expect(store.isStreamConnecting)
    #expect(!store.canStartRecording)

    store.startRecording()

    #expect(pipeline.startRecordingCount == 0)

    try? await Task.sleep(for: .milliseconds(100))

    #expect(store.streamState == .live)
    #expect(store.canStartRecording)
}

@Test
@MainActor
func cancelWhileConnectingIgnoresLateStreamStartCompletion() async {
    let pipeline = NonCancellableDelayedStartMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)

    store.startStream()
    try? await Task.sleep(for: .milliseconds(10))
    store.stopStream()

    try? await Task.sleep(for: .milliseconds(120))

    #expect(store.streamState == .offline)
    #expect(!store.isLive)
    #expect(store.canStartStream)
    #expect(store.canEditDestination)
    #expect(pipeline.startCount == 1)
    #expect(pipeline.stopCount >= 1)
}

@Test
@MainActor
func studioStoreSurfacesMediaPipelineTransportForRTMPDestination() async {
    let pipeline = ConfigurableMediaPipeline(streamTransport: .rtmpPublish)
    let store = StudioStore(mediaPipeline: pipeline)
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.streamTransport == .rtmpPublish)
}

@Test
@MainActor
func studioStoreRedactsDestinationSecretInStreamEvents() async {
    let pipeline = ConfigurableMediaPipeline(streamTransport: .endpointValidation)
    let store = StudioStore(mediaPipeline: pipeline)
    store.destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    let eventDetails = store.events.map(\.detail).joined(separator: "\n")
    #expect(eventDetails.contains("rtmps://live.example.com/app/****"))
    #expect(!eventDetails.contains("sk_live_secret"))
}

@Test
@MainActor
func manualClipMarkerUsesSelectedScene() async {
    let store = StudioStore(mediaPipeline: SpyMediaPipeline())

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.markClip(reason: "Great moment.")

    #expect(store.clipMarkers.count == 1)
    #expect(store.canExportClipMarkers)
    #expect(store.clipMarkers[0].scene == store.selectedSceneKind)
    #expect(store.clipMarkers[0].source == .manual)
    #expect(store.events[0].kind == .clip)
}

@Test
@MainActor
func manualClipMarkerNormalizesReasonForExport() async {
    let store = StudioStore(mediaPipeline: SpyMediaPipeline())

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.markClip(reason: "   \n\t")

    #expect(store.clipMarkers[0].reason == "Marked by operator.")
    #expect(store.events[0].detail == "Marked by operator.")

    let longReason = String(repeating: "a", count: 400)
    store.markClip(reason: longReason)

    #expect(store.clipMarkers[0].reason.count == 240)
    #expect(store.events[0].detail.count == 240)
}

@Test
@MainActor
func manualClipMarkerRequiresActiveCapture() {
    let store = StudioStore()

    store.markClip(reason: "Not live.")

    #expect(!store.canMarkClip)
    #expect(!store.canExportClipMarkers)
    #expect(store.clipMarkers.isEmpty)
    #expect(store.events[0].title == "Clip unavailable")
}

@Test
@MainActor
func repeatedUnavailableClipMarksDoNotSpamEvents() {
    let store = StudioStore()

    store.markClip(reason: "Not live.")
    store.markClip(reason: "Still not live.")

    #expect(store.clipMarkers.isEmpty)
    #expect(store.events.filter { $0.title == "Clip unavailable" }.count == 1)
}

@Test
@MainActor
func directorAddsAutomaticClipMarkerForLiveSafetyCue() async {
    let pipeline = SpyMediaPipeline()
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: false,
            speechLevel: 0.04,
            screenMotion: 0.1,
            hasFace: true,
            activeApplication: "Keynote",
            isScreenFrozen: true
        )
    )
    let store = StudioStore(mediaPipeline: pipeline, signalProvider: provider)

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.advanceDirector()

    #expect(store.clipMarkers.count == 1)
    #expect(store.clipMarkers[0].source == .director)
    #expect(store.clipMarkers[0].scene == .face)
}

@Test
@MainActor
func directorDoesNotAutoMarkClipsWhenOffline() {
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: false,
            speechLevel: 0.04,
            screenMotion: 0.1,
            hasFace: true,
            activeApplication: "Keynote",
            isScreenFrozen: true
        )
    )
    let store = StudioStore(signalProvider: provider)

    store.advanceDirector()

    #expect(store.recommendation?.urgency == .immediate)
    #expect(store.clipMarkers.isEmpty)
}

@Test
func clipMarkerExporterWritesJSONPayload() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("macstream-clip-export-\(UUID().uuidString)", isDirectory: true)
    let marker = ClipMarker(
        title: "Clip Face",
        reason: "Great explanation.",
        scene: .face,
        source: .manual,
        timestamp: Date(timeIntervalSince1970: 10)
    )

    let url = try ClipMarkerExporter().export(
        [marker],
        to: directory,
        now: Date(timeIntervalSince1970: 20)
    )

    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let payload = try decoder.decode(ClipMarkerExportPayload.self, from: data)

    #expect(payload.markers == [marker])
}

@Test
func clipMarkerExporterAvoidsSameSecondOverwrite() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("macstream-clip-export-collision-\(UUID().uuidString)", isDirectory: true)
    let marker = ClipMarker(
        title: "Clip Face",
        reason: "Great explanation.",
        scene: .face,
        source: .manual,
        timestamp: Date(timeIntervalSince1970: 10)
    )
    let now = Date(timeIntervalSince1970: 20)
    let exporter = ClipMarkerExporter()

    let firstURL = try exporter.export([marker], to: directory, now: now)
    let secondURL = try exporter.export([marker], to: directory, now: now)

    #expect(firstURL != secondURL)
    #expect(FileManager.default.fileExists(atPath: firstURL.path))
    #expect(FileManager.default.fileExists(atPath: secondURL.path))
}

@Test
@MainActor
func studioStoreExportsClipMarkers() async {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("macstream-store-export-\(UUID().uuidString)", isDirectory: true)
    let store = StudioStore(mediaPipeline: SpyMediaPipeline())

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.markClip(reason: "Worth review.")
    let url = store.exportClipMarkers(to: directory)

    #expect(url != nil)
    #expect(store.latestClipExportURL == url)
    #expect(store.events[0].title == "Clips exported")
    #expect(FileManager.default.fileExists(atPath: url?.path ?? ""))
}

@Test
@MainActor
func newCaptureSessionClearsPreviousClipArtifacts() async {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("macstream-session-clear-\(UUID().uuidString)", isDirectory: true)
    let store = StudioStore(mediaPipeline: SpyMediaPipeline())

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.markClip(reason: "Old moment.")
    let exportURL = store.exportClipMarkers(to: directory)
    #expect(exportURL != nil)
    store.stopStream()
    try? await Task.sleep(for: .milliseconds(50))

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.clipMarkers.isEmpty)
    #expect(store.latestClipExportURL == nil)
    #expect(store.latestSessionReportURL == nil)
    #expect(store.events.contains { $0.title == "Session started" })
}

@Test
@MainActor
func studioStoreDoesNotExportEmptyClipMarkers() {
    let store = StudioStore()

    let url = store.exportClipMarkers(to: FileManager.default.temporaryDirectory)

    #expect(!store.canExportClipMarkers)
    #expect(url == nil)
    #expect(store.latestClipExportURL == nil)
    #expect(store.events[0].title == "No clips")
}

@Test
@MainActor
func repeatedEmptyClipExportsDoNotSpamEvents() {
    let store = StudioStore()

    let firstURL = store.exportClipMarkers(to: FileManager.default.temporaryDirectory)
    let secondURL = store.exportClipMarkers(to: FileManager.default.temporaryDirectory)

    #expect(firstURL == nil)
    #expect(secondURL == nil)
    #expect(store.events.filter { $0.title == "No clips" }.count == 1)
}

@Test
func sessionReportExporterWritesJSONPayload() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("macstream-session-export-\(UUID().uuidString)", isDirectory: true)
    let report = SessionReportPayload(
        exportedAt: Date(timeIntervalSince1970: 30),
        destinationName: "Twitch",
        streamTransport: .endpointValidation,
        recordingPath: "/tmp/macstream.mov",
        sourceStates: [
            SessionSourceState(kind: .camera, title: "FaceTime Camera", isEnabled: true, level: 1),
            SessionSourceState(kind: .microphone, title: "Studio Mic", isEnabled: false, level: 0.4)
        ],
        screenCaptureTarget: ScreenCaptureTarget(id: "display-1", kind: .display, name: "Studio Display", detail: "3024x1964"),
        preferences: StudioPreferences(performanceMode: .efficiency),
        effectivePerformanceMode: .efficiency,
        health: StreamHealth(bitrateKbps: 4_000, captureFPS: 24),
        systemPressure: SystemPressureSnapshot(
            timestamp: Date(timeIntervalSince1970: 50),
            thermalPressure: .fair,
            memoryUsedMB: 512,
            physicalMemoryMB: 16_384
        ),
        latestSignals: SignalSnapshot(timestamp: Date(timeIntervalSince1970: 40), activeApplication: "Xcode"),
        clipMarkers: [],
        events: []
    )

    let url = try SessionReportExporter().export(report, to: directory)
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let payload = try decoder.decode(SessionReportPayload.self, from: data)

    #expect(payload == report)
}

@Test
func sessionReportExporterAvoidsSameSecondOverwrite() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("macstream-session-export-collision-\(UUID().uuidString)", isDirectory: true)
    let report = SessionReportPayload(
        exportedAt: Date(timeIntervalSince1970: 20),
        destinationName: "Preview",
        streamTransport: .preview,
        recordingPath: nil,
        preferences: StudioPreferences(),
        effectivePerformanceMode: .balanced,
        health: StreamHealth(),
        latestSignals: SignalSnapshot(),
        clipMarkers: [],
        events: []
    )
    let exporter = SessionReportExporter()

    let firstURL = try exporter.export(report, to: directory)
    let secondURL = try exporter.export(report, to: directory)

    #expect(firstURL != secondURL)
    #expect(FileManager.default.fileExists(atPath: firstURL.path))
    #expect(FileManager.default.fileExists(atPath: secondURL.path))
}

@Test
@MainActor
func studioStoreExportsSessionReportWithoutSecretURL() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("macstream-session-store-\(UUID().uuidString)", isDirectory: true)
    let store = StudioStore(mediaPipeline: SpyMediaPipeline())
    store.destination = StreamDestination(name: "Twitch", rtmpURL: "rtmps://live.example.com/app/sk_live_secret")
    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.markClip(reason: "Worth review.")

    let url = try #require(store.exportSessionReport(to: directory))
    let data = try Data(contentsOf: url)
    let text = String(decoding: data, as: UTF8.self)

    #expect(store.latestSessionReportURL == url)
    #expect(store.events[0].title == "Report exported")
    #expect(text.contains("\"destinationName\" : \"Twitch\""))
    #expect(!text.contains("sk_live_secret"))
    #expect(!text.contains("rtmps://live.example.com"))
}

@Test
@MainActor
func studioStoreRetainsExtendedCurrentSessionEventsForReport() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("macstream-session-events-\(UUID().uuidString)", isDirectory: true)
    let store = StudioStore(mediaPipeline: SpyMediaPipeline())

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    for index in 0..<12 {
        store.selectScene(store.scenes[index % store.scenes.count])
    }

    let url = try #require(store.exportSessionReport(to: directory))
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let payload = try decoder.decode(SessionReportPayload.self, from: data)

    #expect(payload.events.count > 8)
    #expect(payload.events.contains { $0.title == "Session started" })
}

@Test
@MainActor
func studioStoreExportsSourceAndCaptureTargetContextInSessionReport() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("macstream-session-context-\(UUID().uuidString)", isDirectory: true)
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted),
            CaptureDeviceInfo(id: "window-42", kind: .window, name: "Slides", detail: "Keynote", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(
        mediaPipeline: SpyMediaPipeline(),
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report)
    )
    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))
    let microphone = store.sources.first { $0.kind == .microphone }!
    store.updateLevel(for: microphone, level: 0.35)
    store.toggleSource(microphone)

    let url = try #require(store.exportSessionReport(to: directory))
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let payload = try decoder.decode(SessionReportPayload.self, from: data)

    let microphoneState = try #require(payload.sourceStates.first { $0.kind == .microphone })
    #expect(microphoneState.title == "Studio Mic")
    #expect(!microphoneState.isEnabled)
    #expect(microphoneState.level == 0.35)
    #expect(payload.screenCaptureTarget == ScreenCaptureTarget(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964"))
}

@Test
@MainActor
func disabledMicrophoneSuppressesSpeechSignal() {
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: true,
            speechLevel: 0.82,
            screenMotion: 0.1,
            hasFace: true,
            activeApplication: "Notes"
        )
    )
    let store = StudioStore(signalProvider: provider)
    let microphone = store.sources.first { $0.kind == .microphone }!

    store.toggleSource(microphone)
    store.advanceDirector()

    #expect(!store.latestSignals.isSpeaking)
    #expect(store.latestSignals.speechLevel == 0)
    #expect(store.latestSignals.isMicMuted)
}

@Test
@MainActor
func disabledScreenSuppressesMotionSignal() {
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: false,
            speechLevel: 0.02,
            screenMotion: 0.92,
            hasFace: true,
            activeApplication: "Xcode",
            isScreenFrozen: true
        )
    )
    let store = StudioStore(signalProvider: provider)
    let screen = store.sources.first { $0.kind == .screen }!

    store.toggleSource(screen)
    store.advanceDirector()

    #expect(store.latestSignals.screenMotion == 0)
    #expect(!store.latestSignals.isScreenFrozen)
}

@Test
@MainActor
func sourceLevelsScaleDirectorSignals() {
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: true,
            speechLevel: 0.8,
            screenMotion: 0.6,
            hasFace: true,
            activeApplication: "Xcode"
        )
    )
    let store = StudioStore(signalProvider: provider)
    let microphone = store.sources.first { $0.kind == .microphone }!
    let screen = store.sources.first { $0.kind == .screen }!

    store.updateLevel(for: microphone, level: 0.5)
    store.updateLevel(for: screen, level: 0.25)
    store.advanceDirector()

    #expect(abs(store.latestSignals.speechLevel - 0.4) < 0.000_001)
    #expect(store.latestSignals.isSpeaking)
    #expect(abs(store.latestSignals.screenMotion - 0.15) < 0.000_001)
}

@Test
@MainActor
func sourceLevelsAreClampedAndZeroLevelMutesSignal() {
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: true,
            speechLevel: 0.8,
            screenMotion: 0.6,
            hasFace: true,
            activeApplication: "Xcode",
            isScreenFrozen: true
        )
    )
    let store = StudioStore(signalProvider: provider)
    let microphone = store.sources.first { $0.kind == .microphone }!
    let screen = store.sources.first { $0.kind == .screen }!

    store.updateLevel(for: microphone, level: -1)
    store.updateLevel(for: screen, level: 2)
    store.advanceDirector()

    #expect(store.sourceLevel(.microphone) == 0)
    #expect(store.sourceLevel(.screen) == 1)
    #expect(store.latestSignals.speechLevel == 0)
    #expect(!store.latestSignals.isSpeaking)
    #expect(store.latestSignals.isMicMuted)
    #expect(store.latestSignals.screenMotion == 0.6)
    #expect(store.latestSignals.isScreenFrozen)
}

@Test
@MainActor
func launchSetupDefaultsApplySavedSceneAndPrompt() {
    let store = StudioStore()

    store.applyLaunchSetupDefaults(
        defaultSceneKind: .screenAndFace,
        setupPrompt: "Coding demo with a face camera"
    )

    #expect(store.selectedSceneKind == .screenAndFace)
    #expect(store.setupPrompt == "Coding demo with a face camera")
}

@Test
@MainActor
func savedSetupPromptIsBoundedForPersistence() {
    let store = StudioStore()
    let longPrompt = String(
        repeating: "a",
        count: SetupPlanPromptBuilder.maxStreamDescriptionCharacters + 25
    )

    store.applySavedSetupPrompt(longPrompt)

    #expect(store.setupPrompt.count == SetupPlanPromptBuilder.maxStreamDescriptionCharacters)
}

@Test
@MainActor
func setupRulesApplyCodingProfile() async {
    let store = StudioStore()
    store.setupPrompt = "I am doing coding streams in Xcode"

    store.generateSetupPlan()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.directorProfile.kind == .coding)
}

@Test
@MainActor
func setupRulesBoundPromptSentToProvider() async {
    let provider = PromptCapturingSetupProvider()
    let store = StudioStore(intelligenceProvider: provider)
    let prefix = String(repeating: "a", count: SetupPlanPromptBuilder.maxStreamDescriptionCharacters)
    let suffix = "SHOULD_NOT_REACH_PROVIDER"

    store.setupPrompt = prefix + suffix
    store.generateSetupPlan()
    try? await Task.sleep(for: .milliseconds(20))

    let prompt = await provider.receivedPrompt()
    #expect(prompt == prefix)
}

@Test
@MainActor
func setupRulesBlockBlankPromptBeforeProviderCall() async {
    let provider = CountingSetupProvider()
    let store = StudioStore(intelligenceProvider: provider)

    store.setupPrompt = " \n\t "

    #expect(!store.canGenerateSetupPlan)
    #expect(store.setupGenerationStatusDetail == "Describe the stream before generating setup rules.")

    store.generateSetupPlan()
    try? await Task.sleep(for: .milliseconds(20))

    #expect(await provider.generatedCount() == 0)
    #expect(store.setupSummary == "Describe the stream before generating setup rules.")
    #expect(store.events.contains { $0.title == "Setup paused" })
}

@Test
@MainActor
func setupRulesTrimPromptBeforeProviderCall() async {
    let provider = PromptCapturingSetupProvider()
    let store = StudioStore(intelligenceProvider: provider)

    store.setupPrompt = " \n coding stream in Xcode \t "
    store.generateSetupPlan()
    try? await Task.sleep(for: .milliseconds(20))

    let prompt = await provider.receivedPrompt()
    #expect(prompt == "coding stream in Xcode")
}

@Test
func mlxLocalProviderFallsBackWhenRuntimeIsNotLinked() async throws {
    let provider = MLXLocalIntelligenceProvider()

    let plan = try await provider.generateSetupPlan(for: "coding stream in xcode")

    #expect(provider.modelIdentifier == MLXLocalIntelligenceProvider.defaultModelIdentifier)
    #expect(provider.modelIdentifier == "LiquidAI/LFM2.5-8B-A1B-MLX-4bit")
    #expect(plan.directorProfile.kind == .coding)
    #if MAC_STREAM_HAS_MLX
    #expect(provider.status.availability == .available)
    #else
    #expect(provider.status.availability == .fallback)
    #endif
}

@Test
func setupPlanPromptConstrainsModelOutput() {
    let prompt = SetupPlanPromptBuilder().prompt(for: "I teach SwiftUI with screen and camera")

    #expect(prompt.contains("Return only compact JSON"))
    #expect(prompt.contains("balanced|coding|demo|teaching|podcast"))
    #expect(prompt.contains("do not ask for real-time LLM control"))
}

@Test
func setupPlanPromptBoundsStreamDescriptionForLocalModels() {
    let prefix = String(repeating: "a", count: SetupPlanPromptBuilder.maxStreamDescriptionCharacters)
    let suffix = "SHOULD_NOT_REACH_MODEL"
    let prompt = SetupPlanPromptBuilder().prompt(for: prefix + suffix)

    #expect(prompt.contains(prefix))
    #expect(!prompt.contains(suffix))
}

@Test
func setupPlanResponseDecoderBuildsTypedProfile() throws {
    let response = """
    {"title":"Swift Workshop","profile":"teaching","summary":"Keep the camera visible while explaining and cut to screen for demos."}
    """

    let plan = try SetupPlanResponseDecoder().decode(response)

    #expect(plan.title == "Swift Workshop")
    #expect(plan.directorProfile.kind == .teaching)
    #expect(plan.scenes == [.face, .screenAndFace, .screenOnly, .brb])
}

@Test
func setupPlanResponseDecoderUsesFirstCompleteJSONObject() throws {
    let response = """
    Here is the plan:
    {"title":"Product Demo","profile":"demo","summary":"Open on Face, then cut to Screen + Face for product motion."}
    Ignore this duplicate:
    {"title":"Podcast","profile":"podcast","summary":"Do not use this."}
    """

    let plan = try SetupPlanResponseDecoder().decode(response)

    #expect(plan.title == "Product Demo")
    #expect(plan.directorProfile.kind == .demo)
}

@Test
func setupPlanResponseDecoderIgnoresBracesInsideStrings() throws {
    let response = #"""
    ```json
    {"title":"Coding","profile":"coding","summary":"Treat {editor} motion as screen context and escaped \"quotes\" as text."}
    ```
    """#

    let plan = try SetupPlanResponseDecoder().decode(response)

    #expect(plan.directorProfile.kind == .coding)
    #expect(plan.directorRuleSummary.contains("{editor}"))
    #expect(plan.directorRuleSummary.contains(#""quotes""#))
}

@Test
func setupPlanResponseDecoderRejectsUnsupportedProfile() {
    let response = """
    {"title":"Bad","profile":"cinematic","summary":"Unsupported."}
    """

    #expect(throws: SetupPlanDecodingError.self) {
        try SetupPlanResponseDecoder().decode(response)
    }
}

@Test
func mlxLocalProviderExposesSetupPlanDecoder() throws {
    let provider = MLXLocalIntelligenceProvider()
    let plan = try provider.decodeSetupPlanResponse(
        #"{"title":"Product Demo","profile":"demo","summary":"Balance face and screen while showing the product."}"#
    )

    #expect(plan.directorProfile.kind == .demo)
}

@Test
func localModelStrategyDocumentsTextAndVisionModelBoundaries() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let architecture = try String(
        contentsOf: root.appendingPathComponent("docs/architecture.md"),
        encoding: .utf8
    )
    let risks = try String(
        contentsOf: root.appendingPathComponent("docs/technical-risks.md"),
        encoding: .utf8
    )

    #expect(architecture.contains(MLXLocalIntelligenceProvider.defaultModelIdentifier))
    #expect(architecture.contains("RuleBasedLocalIntelligenceProvider"))
    #expect(architecture.contains("OpenAI-compatible endpoints"))
    #expect(risks.contains("Provider-first beats managed runtime ownership"))
    #expect(risks.contains("Foundation Models and OpenAI-compatible providers"))
    #expect(risks.contains("Moondream"))
    #expect(risks.contains("sampled frames"))
    #expect(risks.contains("cloud vision"))
    #expect(risks.contains("hot path"))
}

@Test
@MainActor
func setupRulesTrackGenerationStateAndProviderStatus() async {
    let status = LocalIntelligenceStatus(
        provider: .mlx,
        availability: .fallback,
        detail: "test fallback"
    )
    let provider = DelayedSetupProvider(
        status: status,
        plan: SetupPlan(
            title: "Demo",
            scenes: [.face, .screenAndFace, .screenOnly, .brb],
            directorProfile: .demo,
            directorRuleSummary: "demo rules"
        )
    )
    let store = StudioStore(intelligenceProvider: provider)

    store.generateSetupPlan()

    #expect(store.isGeneratingSetupPlan)
    #expect(store.setupSummary == "Generating setup rules...")

    try? await Task.sleep(for: .milliseconds(80))

    #expect(!store.isGeneratingSetupPlan)
    #expect(store.localIntelligenceStatus == status)
    #expect(store.directorProfile.kind == .demo)
    #expect(store.setupSummary == "demo rules")
}

@Test
@MainActor
func setupRulesDoNotApplyFinishedPlanAfterStreamStarts() async {
    let status = LocalIntelligenceStatus(
        provider: .mlx,
        availability: .available,
        detail: "test model"
    )
    let provider = DelayedSetupProvider(
        status: status,
        plan: SetupPlan(
            title: "Demo",
            scenes: [.face, .screenAndFace, .screenOnly, .brb],
            directorProfile: .demo,
            directorRuleSummary: "demo rules"
        )
    )
    let store = StudioStore(
        mediaPipeline: SpyMediaPipeline(),
        intelligenceProvider: provider
    )

    store.generateSetupPlan()
    store.startStream()
    try? await Task.sleep(for: .milliseconds(80))

    #expect(!store.isGeneratingSetupPlan)
    #expect(store.localIntelligenceStatus == status)
    #expect(store.directorProfile.kind == .balanced)
    #expect(store.setupSummary == "Stop preview before generating local setup rules.")
    #expect(store.events.contains { $0.title == "Setup paused" })
    #expect(!store.events.contains { $0.title == "Demo" })
}

@Test
@MainActor
func setupRulesCancelInFlightGenerationWhenStreamStarts() async {
    let provider = CancellableDelayedSetupProvider()
    let store = StudioStore(
        mediaPipeline: SpyMediaPipeline(),
        intelligenceProvider: provider
    )

    store.generateSetupPlan()
    try? await Task.sleep(for: .milliseconds(10))

    #expect(store.isGeneratingSetupPlan)

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(!store.isGeneratingSetupPlan)
    #expect(store.directorProfile.kind == .balanced)
    #expect(store.setupSummary == "Stop preview before generating local setup rules.")
    #expect(store.events.contains { $0.title == "Setup paused" })
    #expect(!store.events.contains { $0.title == "Setup failed" })
    #expect(await provider.startedCount() == 1)
    #expect(await provider.completedCount() == 0)
    #expect(await provider.cancelledCount() == 1)
}

@Test
@MainActor
func setupRulesDoNotApplyFinishedPlanAfterPromptChanges() async {
    let provider = DelayedSetupProvider(
        status: LocalIntelligenceStatus(
            provider: .mlx,
            availability: .available,
            detail: "test model"
        ),
        plan: SetupPlan(
            title: "Demo",
            scenes: [.face, .screenAndFace, .screenOnly, .brb],
            directorProfile: .demo,
            directorRuleSummary: "demo rules"
        )
    )
    let store = StudioStore(intelligenceProvider: provider)

    store.setupPrompt = "coding stream in xcode"
    store.generateSetupPlan()
    store.setupPrompt = "podcast with guests"
    try? await Task.sleep(for: .milliseconds(80))

    #expect(!store.isGeneratingSetupPlan)
    #expect(store.directorProfile.kind == .balanced)
    #expect(store.setupSummary == "Setup prompt changed; generate rules again.")
    #expect(store.events.contains { $0.title == "Setup changed" })
    #expect(!store.events.contains { $0.title == "Demo" })
}

@Test
@MainActor
func setupRulesPauseGenerationWhileStreamIsLive() async {
    let provider = CountingSetupProvider()
    let store = StudioStore(
        mediaPipeline: SpyMediaPipeline(),
        intelligenceProvider: provider
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.generateSetupPlan()
    try? await Task.sleep(for: .milliseconds(20))

    #expect(!store.canGenerateSetupPlan)
    #expect(store.setupGenerationStatusDetail == "Stop preview before generating local setup rules.")
    #expect(store.setupSummary == "Stop preview before generating local setup rules.")
    #expect(await provider.generatedCount() == 0)
    #expect(store.events.contains { $0.title == "Setup paused" })
}

@Test
@MainActor
func repeatedBlockedSetupGenerationDoesNotSpamEvents() async {
    let provider = CountingSetupProvider()
    let store = StudioStore(
        mediaPipeline: SpyMediaPipeline(),
        intelligenceProvider: provider
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    store.generateSetupPlan()
    store.generateSetupPlan()
    try? await Task.sleep(for: .milliseconds(20))

    #expect(store.setupSummary == "Stop preview before generating local setup rules.")
    #expect(await provider.generatedCount() == 0)
    #expect(store.events.filter { $0.title == "Setup paused" }.count == 1)
}

@Test
@MainActor
func setupRulesPauseGenerationWhileStreamIsConnecting() async {
    let provider = CountingSetupProvider()
    let store = StudioStore(
        mediaPipeline: DelayedStartMediaPipeline(),
        intelligenceProvider: provider
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(10))
    store.generateSetupPlan()
    try? await Task.sleep(for: .milliseconds(20))

    #expect(!store.canGenerateSetupPlan)
    #expect(store.setupGenerationStatusDetail == "Finish connecting before generating setup rules.")
    #expect(await provider.generatedCount() == 0)
}

@Test
@MainActor
func setupRulesPauseGenerationWhileRecording() async {
    let provider = CountingSetupProvider()
    let store = StudioStore(
        mediaPipeline: SpyMediaPipeline(),
        intelligenceProvider: provider
    )

    store.startRecording()
    try? await Task.sleep(for: .milliseconds(50))
    store.generateSetupPlan()
    try? await Task.sleep(for: .milliseconds(20))

    #expect(!store.canGenerateSetupPlan)
    #expect(store.setupGenerationStatusDetail == "Stop recording before generating local setup rules.")
    #expect(await provider.generatedCount() == 0)
}

@Test
@MainActor
func defaultPreferencesKeepAutoRecordingOff() async {
    let pipeline = SpyMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(pipeline.didStartStream)
    #expect(!pipeline.didStartRecording)
    #expect(store.recordingState == .stopped)
}

@Test
@MainActor
func startStreamHonorsRecordWhileStreamingPreference() async {
    let pipeline = SpyMediaPipeline()
    let store = StudioStore(
        mediaPipeline: pipeline,
        preferences: StudioPreferences(recordWhileStreaming: false)
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(pipeline.didStartStream)
    #expect(!pipeline.didStartRecording)
    #expect(store.recordingState == .stopped)
}

@Test
@MainActor
func startStreamRecordsWhenPreferenceEnabled() async {
    let pipeline = SpyMediaPipeline()
    let store = StudioStore(
        mediaPipeline: pipeline,
        preferences: StudioPreferences(recordWhileStreaming: true)
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(pipeline.didStartStream)
    #expect(pipeline.didStartRecording)
}

@Test
@MainActor
func stopStreamStopsOnlyAutoStartedRecording() async {
    let pipeline = SpyMediaPipeline()
    let store = StudioStore(
        mediaPipeline: pipeline,
        preferences: StudioPreferences(recordWhileStreaming: true)
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(80))
    store.stopStream()
    try? await Task.sleep(for: .milliseconds(80))

    #expect(pipeline.didStartRecording)
    #expect(pipeline.didStopRecording)
    #expect(store.recordingState == .stopped)
}

@Test
@MainActor
func stopStreamPreservesManualRecording() async {
    let pipeline = SpyMediaPipeline()
    let store = StudioStore(
        mediaPipeline: pipeline,
        preferences: StudioPreferences(recordWhileStreaming: true)
    )

    store.startRecording()
    try? await Task.sleep(for: .milliseconds(50))
    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.stopStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(pipeline.didStartStream)
    #expect(pipeline.didStartRecording)
    #expect(!pipeline.didStopRecording)
    #expect(store.recordingState == .recording)
}

@Test
@MainActor
func recordingStartCanBeCancelledAndSuppressesDuplicateStarts() async {
    let pipeline = NonCancellableDelayedRecordingPipeline()
    let store = StudioStore(mediaPipeline: pipeline)

    store.startRecording()
    try? await Task.sleep(for: .milliseconds(10))

    #expect(store.isRecordingStarting)
    #expect(!store.canStartRecording)
    #expect(store.canStopRecording)

    store.startRecording()

    #expect(pipeline.startRecordingCount == 1)

    store.stopRecording()
    try? await Task.sleep(for: .milliseconds(120))

    #expect(store.recordingState == .stopped)
    #expect(store.canStartRecording)
    #expect(!store.canStopRecording)
    #expect(pipeline.startRecordingCount == 1)
    #expect(pipeline.stopRecordingCount >= 1)
}

@Test
@MainActor
func stopRecordingIsIdempotentWhilePipelineStops() async {
    let pipeline = DelayedStopRecordingPipeline()
    let store = StudioStore(mediaPipeline: pipeline)

    store.startRecording()
    try? await Task.sleep(for: .milliseconds(20))

    #expect(store.recordingState == .recording)

    store.stopRecording()

    #expect(store.isRecordingStopping)
    #expect(!store.canStopRecording)
    #expect(!store.canStartRecording)
    #expect(!store.canStartStream)
    #expect(store.recordingStatusDetail == "Stopping local archive")
    #expect(store.setupGenerationStatusDetail == "Finish recording stop before generating setup rules.")

    store.stopRecording()
    try? await Task.sleep(for: .milliseconds(20))

    #expect(pipeline.stopRecordingCount == 1)

    try? await Task.sleep(for: .milliseconds(100))

    #expect(!store.isRecordingStopping)
    #expect(store.recordingState == .stopped)
    #expect(store.canStartRecording)
    #expect(store.canStartStream)
    #expect(pipeline.stopRecordingCount == 1)
    #expect(store.events.filter { $0.title == "Recording stopped" }.count == 1)
}

@Test
@MainActor
func pendingRecordingStartupSuppressesStreamStart() async {
    let pipeline = NonCancellableDelayedRecordingPipeline()
    let store = StudioStore(mediaPipeline: pipeline)

    store.startRecording()
    try? await Task.sleep(for: .milliseconds(10))

    #expect(store.isRecordingStarting)
    #expect(!store.canStartStream)

    store.startStream()

    #expect(pipeline.startStreamCount == 0)

    try? await Task.sleep(for: .milliseconds(120))

    #expect(store.recordingState == .recording)
    #expect(store.canStartStream)

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(pipeline.startStreamCount == 1)
}

private final class FixedSignalProvider: SignalProvider, @unchecked Sendable {
    private let fixedSnapshot: SignalSnapshot

    init(snapshot: SignalSnapshot) {
        self.fixedSnapshot = snapshot
    }

    func start() {}

    func stop() {}

    func snapshot() -> SignalSnapshot {
        fixedSnapshot
    }
}

private final class ConfigurableMediaPipeline: MediaPipeline, @unchecked Sendable {
    let streamTransport: StreamTransportKind
    var currentHealth: StreamHealth?
    var lastConfiguration: MediaPipelineConfiguration?
    var configurationAtStartStream: MediaPipelineConfiguration?
    var updateCount = 0

    init(streamTransport: StreamTransportKind = .endpointValidation) {
        self.streamTransport = streamTransport
    }

    func update(configuration: MediaPipelineConfiguration) {
        updateCount += 1
        lastConfiguration = configuration
    }

    func startStream(destination: StreamDestination) async throws {
        configurationAtStartStream = lastConfiguration
    }

    func stopStream() async {}

    func startRecording() async throws -> URL {
        URL(fileURLWithPath: "/tmp/macstream-configurable.mov")
    }

    func stopRecording() async {}
}

private final class TransportCountingMediaPipeline: MediaPipeline, @unchecked Sendable {
    var transportReadCount = 0

    var streamTransport: StreamTransportKind {
        transportReadCount += 1
        return .rtmpPublish
    }

    func startStream(destination: StreamDestination) async throws {}

    func stopStream() async {}

    func startRecording() async throws -> URL {
        URL(fileURLWithPath: "/tmp/macstream-transport-counting.mov")
    }

    func stopRecording() async {}
}

private final class ReadinessGatedMediaPipeline: MediaPipeline, @unchecked Sendable {
    var requiresCaptureReadinessForStart: Bool {
        true
    }

    func startStream(destination: StreamDestination) async throws {}

    func stopStream() async {}

    func startRecording() async throws -> URL {
        URL(fileURLWithPath: "/tmp/macstream-readiness-gated.mov")
    }

    func stopRecording() async {}
}

private final class ScreenVideoGatedMediaPipeline: MediaPipeline, @unchecked Sendable {
    let streamTransport: StreamTransportKind

    init(streamTransport: StreamTransportKind = .rtmpPublish) {
        self.streamTransport = streamTransport
    }

    var requiresCaptureReadinessForStart: Bool {
        true
    }

    var requiresScreenCaptureVideoForStream: Bool {
        true
    }

    var requiresScreenCaptureVideoForRecording: Bool {
        true
    }

    var supportedSceneKindsForStream: Set<SceneKind> {
        [.screenOnly]
    }

    var supportedSceneKindsForRecording: Set<SceneKind> {
        [.screenOnly, .screenAndFace]
    }

    func startStream(destination: StreamDestination) async throws {}

    func stopStream() async {}

    func startRecording() async throws -> URL {
        URL(fileURLWithPath: "/tmp/macstream-screen-video-gated.mov")
    }

    func stopRecording() async {}
}

private final class ComposedScreenVideoMediaPipeline: MediaPipeline, @unchecked Sendable {
    let streamTransport: StreamTransportKind
    var lastConfiguration: MediaPipelineConfiguration?
    var configurationAtStartStream: MediaPipelineConfiguration?
    var startCount = 0

    init(streamTransport: StreamTransportKind = .rtmpPublish) {
        self.streamTransport = streamTransport
    }

    var requiresCaptureReadinessForStart: Bool {
        true
    }

    var requiresScreenCaptureVideoForStream: Bool {
        true
    }

    var requiresScreenCaptureVideoForRecording: Bool {
        true
    }

    var supportedSceneKindsForStream: Set<SceneKind> {
        [.screenOnly, .screenAndFace]
    }

    var supportedSceneKindsForRecording: Set<SceneKind> {
        [.screenOnly, .screenAndFace]
    }

    func update(configuration: MediaPipelineConfiguration) {
        lastConfiguration = configuration
    }

    func startStream(destination: StreamDestination) async throws {
        startCount += 1
        configurationAtStartStream = lastConfiguration
    }

    func stopStream() async {}

    func startRecording() async throws -> URL {
        URL(fileURLWithPath: "/tmp/macstream-composed-screen-video.mov")
    }

    func stopRecording() async {}
}

private actor DelayedSuccessfulRTMPPublisher: RTMPPublisher {
    private var hasStartedConnect = false
    private var shouldFinishConnect = false
    private var connectStartedContinuation: CheckedContinuation<Void, Never>?
    private var finishConnectContinuation: CheckedContinuation<Void, Never>?
    private(set) var closeCount = 0

    func connect() async throws {
        hasStartedConnect = true
        connectStartedContinuation?.resume()
        connectStartedContinuation = nil

        guard !shouldFinishConnect else { return }

        await withCheckedContinuation { continuation in
            finishConnectContinuation = continuation
        }
    }

    func waitUntilConnectStarted() async {
        guard !hasStartedConnect else { return }

        await withCheckedContinuation { continuation in
            connectStartedContinuation = continuation
        }
    }

    func finishConnect() {
        shouldFinishConnect = true
        finishConnectContinuation?.resume()
        finishConnectContinuation = nil
    }

    nonisolated func append(_ sampleBuffer: CMSampleBuffer) -> Bool {
        true
    }

    func close() {
        closeCount += 1
    }
}

private final class RecoveringMediaPipeline: MediaPipeline, @unchecked Sendable {
    var streamTransport: StreamTransportKind = .rtmpPublish
    var errorToThrow: (any Error)?
    var startCount = 0

    func startStream(destination: StreamDestination) async throws {
        startCount += 1
        if let errorToThrow {
            throw errorToThrow
        }
    }

    func stopStream() async {}

    func startRecording() async throws -> URL {
        URL(fileURLWithPath: "/tmp/macstream-recovering.mov")
    }

    func stopRecording() async {}
}

private final class FlakyStartMediaPipeline: MediaPipeline, @unchecked Sendable {
    let streamTransport: StreamTransportKind
    private let failuresBeforeSuccess: Int
    var startCount = 0

    init(failuresBeforeSuccess: Int, streamTransport: StreamTransportKind = .rtmpPublish) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
        self.streamTransport = streamTransport
    }

    func startStream(destination: StreamDestination) async throws {
        startCount += 1
        if startCount <= failuresBeforeSuccess {
            throw TestStreamError(message: "Transient start failure \(startCount)")
        }
    }

    func stopStream() async {}

    func startRecording() async throws -> URL {
        URL(fileURLWithPath: "/tmp/macstream-flaky.mov")
    }

    func stopRecording() async {}
}

private final class DelayedStartMediaPipeline: MediaPipeline, @unchecked Sendable {
    var streamTransport: StreamTransportKind = .preview
    var startCount = 0
    var startRecordingCount = 0

    func startStream(destination: StreamDestination) async throws {
        startCount += 1
        try await Task.sleep(for: .milliseconds(70))
    }

    func stopStream() async {}

    func startRecording() async throws -> URL {
        startRecordingCount += 1
        return URL(fileURLWithPath: "/tmp/macstream-delayed.mov")
    }

    func stopRecording() async {}
}

private final class DelayedStopMediaPipeline: MediaPipeline, @unchecked Sendable {
    var streamTransport: StreamTransportKind = .preview
    var stopCount = 0

    func startStream(destination: StreamDestination) async throws {}

    func stopStream() async {
        stopCount += 1
        try? await Task.sleep(for: .milliseconds(70))
    }

    func startRecording() async throws -> URL {
        URL(fileURLWithPath: "/tmp/macstream-delayed-stop.mov")
    }

    func stopRecording() async {}
}

private final class DelayedStopRecordingPipeline: MediaPipeline, @unchecked Sendable {
    var streamTransport: StreamTransportKind = .preview
    var stopRecordingCount = 0

    func startStream(destination: StreamDestination) async throws {}

    func stopStream() async {}

    func startRecording() async throws -> URL {
        URL(fileURLWithPath: "/tmp/macstream-delayed-stop-recording.mov")
    }

    func stopRecording() async {
        stopRecordingCount += 1
        try? await Task.sleep(for: .milliseconds(70))
    }
}

private final class NonCancellableDelayedStartMediaPipeline: MediaPipeline, @unchecked Sendable {
    var streamTransport: StreamTransportKind = .preview
    var startCount = 0
    var stopCount = 0

    func startStream(destination: StreamDestination) async throws {
        startCount += 1
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.06) {
                continuation.resume()
            }
        }
    }

    func stopStream() async {
        stopCount += 1
    }

    func startRecording() async throws -> URL {
        URL(fileURLWithPath: "/tmp/macstream-noncancellable.mov")
    }

    func stopRecording() async {}
}

private final class NonCancellableDelayedRecordingPipeline: MediaPipeline, @unchecked Sendable {
    var streamTransport: StreamTransportKind = .preview
    var startStreamCount = 0
    var startRecordingCount = 0
    var stopRecordingCount = 0

    func startStream(destination: StreamDestination) async throws {
        startStreamCount += 1
    }

    func stopStream() async {}

    func startRecording() async throws -> URL {
        startRecordingCount += 1
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.06) {
                continuation.resume()
            }
        }
        return URL(fileURLWithPath: "/tmp/macstream-delayed-recording.mov")
    }

    func stopRecording() async {
        stopRecordingCount += 1
    }
}

private struct TestStreamError: LocalizedError {
    var message: String

    var errorDescription: String? {
        message
    }
}

private final class ConfigurableSignalProvider: SignalProvider, @unchecked Sendable {
    var lastConfiguration: SignalSamplingConfiguration?
    var updateCount = 0
    var startCount = 0
    var stopCount = 0

    func update(configuration: SignalSamplingConfiguration) {
        updateCount += 1
        lastConfiguration = configuration
    }

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func snapshot() -> SignalSnapshot {
        SignalSnapshot()
    }
}

private struct FixedCaptureDeviceProvider: CaptureDeviceProvider {
    var report: CapturePreflightReport

    func scan() async -> CapturePreflightReport {
        report
    }
}

private actor CountingScreenCaptureContentListing: ScreenCaptureContentListing {
    private var count = 0

    func devices(permission: CapturePermissionState) async throws -> [CaptureDeviceInfo] {
        count += 1
        return [
            CaptureDeviceInfo(
                id: "display-7",
                kind: .display,
                name: "Studio Display",
                detail: "3024x1964",
                permission: permission
            )
        ]
    }

    func deviceLoadCount() -> Int {
        count
    }
}

private actor DelayedCountingCaptureDeviceProvider: CaptureDeviceProvider {
    private var count = 0
    private let report: CapturePreflightReport

    init(report: CapturePreflightReport) {
        self.report = report
    }

    func scan() async -> CapturePreflightReport {
        count += 1
        try? await Task.sleep(for: .milliseconds(40))
        return report
    }

    func scanCount() -> Int {
        count
    }
}

private actor SequencedCaptureDeviceProvider: CaptureDeviceProvider {
    private var reports: [CapturePreflightReport]
    private var index = 0

    init(reports: [CapturePreflightReport]) {
        self.reports = reports
    }

    func scan() async -> CapturePreflightReport {
        guard !reports.isEmpty else { return CapturePreflightReport() }

        let report = reports[min(index, reports.count - 1)]
        index += 1
        return report
    }

    func scanCount() -> Int {
        index
    }
}

private struct DelayedSetupProvider: LocalIntelligenceProvider {
    let status: LocalIntelligenceStatus
    let plan: SetupPlan

    func generateSetupPlan(for prompt: String) async throws -> SetupPlan {
        try await Task.sleep(for: .milliseconds(30))
        return plan
    }

    func explain(_ recommendation: DirectorRecommendation, snapshot: SignalSnapshot) async throws -> String {
        "test explanation"
    }
}

private actor CancellableDelayedSetupProvider: LocalIntelligenceProvider {
    nonisolated let status = LocalIntelligenceStatus(
        provider: .mlx,
        availability: .available,
        detail: "test model"
    )
    nonisolated let plan = SetupPlan(
        title: "Cancelled Demo",
        scenes: [.face, .screenAndFace, .screenOnly, .brb],
        directorProfile: .demo,
        directorRuleSummary: "cancelled rules"
    )
    private var started = 0
    private var completed = 0
    private var cancelled = 0

    func generateSetupPlan(for prompt: String) async throws -> SetupPlan {
        started += 1
        do {
            try await Task.sleep(for: .milliseconds(250))
        } catch is CancellationError {
            cancelled += 1
            throw CancellationError()
        }
        completed += 1
        return plan
    }

    func explain(_ recommendation: DirectorRecommendation, snapshot: SignalSnapshot) async throws -> String {
        "test explanation"
    }

    func startedCount() -> Int {
        started
    }

    func completedCount() -> Int {
        completed
    }

    func cancelledCount() -> Int {
        cancelled
    }
}

private func expectedMediaConfiguration(
    _ mode: StudioPerformanceMode,
    sceneKind: SceneKind = .brb,
    capturesSystemAudio: Bool = false,
    capturesMicrophone: Bool = true,
    systemAudioLevel: Double = 0.72,
    microphoneLevel: Double = 1,
    screenCaptureTarget: ScreenCaptureTarget? = nil
) -> MediaPipelineConfiguration {
    var configuration = mode.mediaConfiguration
    configuration.sceneKind = sceneKind
    configuration.capturesSystemAudio = capturesSystemAudio
    configuration.capturesMicrophone = capturesMicrophone
    configuration.systemAudioLevel = systemAudioLevel
    configuration.microphoneLevel = microphoneLevel
    configuration.screenCaptureTarget = screenCaptureTarget
    return configuration
}

private actor CountingSetupProvider: LocalIntelligenceProvider {
    nonisolated let status = LocalIntelligenceStatus(
        provider: .mlx,
        availability: .fallback,
        detail: "test fallback"
    )
    nonisolated let plan = SetupPlan(
        title: "Counted",
        scenes: [.face, .screenAndFace, .screenOnly, .brb],
        directorProfile: .coding,
        directorRuleSummary: "counted rules"
    )
    private var callCount = 0

    func generateSetupPlan(for prompt: String) async throws -> SetupPlan {
        callCount += 1
        return plan
    }

    func explain(_ recommendation: DirectorRecommendation, snapshot: SignalSnapshot) async throws -> String {
        "test explanation"
    }

    func generatedCount() -> Int {
        callCount
    }
}

private actor PromptCapturingSetupProvider: LocalIntelligenceProvider {
    nonisolated let status = LocalIntelligenceStatus(
        provider: .mlx,
        availability: .fallback,
        detail: "test fallback"
    )
    nonisolated let plan = SetupPlan(
        title: "Captured",
        scenes: [.face, .screenAndFace, .screenOnly, .brb],
        directorProfile: .balanced,
        directorRuleSummary: "captured rules"
    )
    private var prompt: String?

    func generateSetupPlan(for prompt: String) async throws -> SetupPlan {
        self.prompt = prompt
        return plan
    }

    func explain(_ recommendation: DirectorRecommendation, snapshot: SignalSnapshot) async throws -> String {
        "test explanation"
    }

    func receivedPrompt() -> String? {
        prompt
    }
}

@MainActor
private final class SpyMediaPipeline: MediaPipeline, @unchecked Sendable {
    var didStartStream = false
    var didStartRecording = false
    var didStopRecording = false

    func startStream(destination: StreamDestination) async throws {
        didStartStream = true
    }

    func stopStream() async {}

    func startRecording() async throws -> URL {
        didStartRecording = true
        return URL(fileURLWithPath: "/tmp/macstream-test.mov")
    }

    func stopRecording() async {
        didStopRecording = true
    }
}
