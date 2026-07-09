import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import Network
import Testing
@testable import MacStreamCore

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
    #expect(store.captureReadiness.detail == "Camera needs access.")
    #expect(store.missingRequiredCapturePermissionKinds == [.camera])

    let camera = try #require(store.sources.first { $0.kind == .camera })
    let microphone = try #require(store.sources.first { $0.kind == .microphone })
    store.toggleSource(camera)
    store.toggleSource(microphone)

    #expect(store.captureReadiness.state == .ready)
    #expect(store.captureReadiness.title == "Ready")
    #expect(store.captureReadiness.detail == "Capture sources are ready.")
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

    #expect(store.missingRequiredCapturePermissionKinds == [.camera])
    #expect(store.promptableRequiredCapturePermissionKinds.isEmpty)
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

    #expect(store.missingRequiredCapturePermissionKinds == [.camera])
    #expect(store.promptableRequiredCapturePermissionKinds.isEmpty)
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
    #expect(store.setupChecklistItems.first { $0.id == .scene }?.detail == "Choose Webcam, Screen + Webcam, or Screen.")
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
    #expect(store.startBlockedReason == "Choose Webcam, Screen + Webcam, or Screen before starting.")
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
    #expect(store.startBlockedReason == "Enable Screen and Webcam for Screen + Webcam before starting.")
    #expect(store.captureStartBlockedReason == "Enable Screen and Webcam for Screen + Webcam before starting.")
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
    #expect(store.startBlockedReason == "Enable Webcam for Webcam before starting.")
    #expect(store.captureStartBlockedReason == "Enable Webcam for Webcam before starting.")

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
    #expect(store.recordingStartBlockedReason == "Choose Screen or Screen + Webcam before starting a local recording.")
    #expect(store.canStartStream)
    #expect(!store.canStartRecording)

    store.destination = StreamDestination(name: "RTMP", rtmpURL: "rtmp://127.0.0.1/live/stream")

    #expect(!store.canStartStream)
    #expect(store.streamStartBlockedReason == "Choose Screen or Screen + Webcam before starting real capture.")
    #expect(store.startBlockedReason == "Choose Screen or Screen + Webcam before starting real capture.")
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
    let signalProvider = ConfigurableSignalProvider()
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "microphone-built", kind: .microphone, name: "Built-in Mic", permission: .granted),
            CaptureDeviceInfo(id: "microphone-usb", kind: .microphone, name: "USB Mic", permission: .granted)
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
    store.selectMicrophoneDevice(id: "microphone-usb")

    #expect(store.selectedMicrophoneDeviceID == "microphone-usb")
    #expect(pipeline.lastConfiguration?.microphoneDeviceID == "microphone-usb")
    #expect(signalProvider.lastConfiguration?.microphoneDeviceID == "microphone-usb")
    #expect(store.events.contains { $0.title == "Mic device" && $0.detail == "USB Mic" })
}

@Test
@MainActor
func captureScanPropagatesSelectedMicrophoneToSignalConfiguration() async {
    let pipeline = ConfigurableMediaPipeline()
    let signalProvider = ConfigurableSignalProvider()
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "microphone-built", kind: .microphone, name: "Built-in Mic", permission: .granted),
            CaptureDeviceInfo(id: "microphone-usb", kind: .microphone, name: "USB Mic", permission: .granted)
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

    #expect(store.selectedMicrophoneDeviceID == "microphone-built")
    #expect(pipeline.lastConfiguration?.microphoneDeviceID == "microphone-built")
    #expect(signalProvider.lastConfiguration?.microphoneDeviceID == "microphone-built")
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
func PreflightCoachReportsMissingPermissionFirst() {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", permission: .denied),
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .granted)
        ],
        summary: "Screen access needed."
    )
    let advice = PreflightCoach.advice(
        report: report,
        sources: [
            StudioSource(kind: .screen),
            StudioSource(kind: .camera),
            StudioSource(kind: .microphone)
        ],
        selectedScene: .screenAndFace,
        selectedScreenCaptureTarget: nil,
        selectedCameraDeviceID: nil,
        selectedMicrophoneDeviceID: nil,
        destination: StreamDestination(),
        hasRunInitialCaptureScan: true,
        isScanningCapture: false
    )

    #expect(advice.first?.action == .openCaptureSettings(.display))
}

@Test
func PreflightCoachReportsMissingDeviceOrTarget() {
    let displayTarget = ScreenCaptureTarget(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964")
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: displayTarget.id, kind: .display, name: displayTarget.name, detail: displayTarget.detail, permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let advice = PreflightCoach.advice(
        report: report,
        sources: [
            StudioSource(kind: .screen),
            StudioSource(kind: .camera),
            StudioSource(kind: .microphone)
        ],
        selectedScene: .screenAndFace,
        selectedScreenCaptureTarget: displayTarget,
        selectedCameraDeviceID: nil,
        selectedMicrophoneDeviceID: "microphone-1",
        destination: StreamDestination(),
        hasRunInitialCaptureScan: true,
        isScanningCapture: false
    )

    #expect(advice.first?.action == .rescanCapture)
}

@Test
func PreflightCoachReportsMutedOrZeroLevelNeededSource() {
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", permission: .granted),
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let advice = PreflightCoach.advice(
        report: report,
        sources: [
            StudioSource(kind: .screen, level: 0),
            StudioSource(kind: .camera, isEnabled: false),
            StudioSource(kind: .microphone)
        ],
        selectedScene: .screenAndFace,
        selectedScreenCaptureTarget: nil,
        selectedCameraDeviceID: nil,
        selectedMicrophoneDeviceID: "microphone-1",
        destination: StreamDestination(),
        hasRunInitialCaptureScan: true,
        isScanningCapture: false
    )

    #expect(advice.first?.action == .fixSelectedSceneSources)
}

@Test
func PreflightCoachReportsMissingDestinationAfterCaptureAndSources() {
    let displayTarget = ScreenCaptureTarget(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964")
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: displayTarget.id, kind: .display, name: displayTarget.name, detail: displayTarget.detail, permission: .granted),
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    var destination = StreamDestination()
    destination.setRTMPServerURL("rtmps://live.example.com")
    destination.setRTMPStreamKey("sk_live_secret")
    let advice = PreflightCoach.advice(
        report: report,
        sources: [
            StudioSource(kind: .screen),
            StudioSource(kind: .camera),
            StudioSource(kind: .microphone)
        ],
        selectedScene: .screenAndFace,
        selectedScreenCaptureTarget: displayTarget,
        selectedCameraDeviceID: "camera-1",
        selectedMicrophoneDeviceID: "microphone-1",
        destination: destination,
        hasRunInitialCaptureScan: true,
        isScanningCapture: false
    )

    #expect(advice.first?.action == .usePreviewDestination)
    #expect(advice.first?.detail == destination.validationError)
    #expect(advice.first?.detail.contains("sk_live_secret") == false)
}

@Test
func PreflightCoachReturnsEmptyWhenAllClear() {
    let displayTarget = ScreenCaptureTarget(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964")
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: displayTarget.id, kind: .display, name: displayTarget.name, detail: displayTarget.detail, permission: .granted),
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let advice = PreflightCoach.advice(
        report: report,
        sources: [
            StudioSource(kind: .screen),
            StudioSource(kind: .camera),
            StudioSource(kind: .microphone)
        ],
        selectedScene: .screenAndFace,
        selectedScreenCaptureTarget: displayTarget,
        selectedCameraDeviceID: "camera-1",
        selectedMicrophoneDeviceID: "microphone-1",
        destination: StreamDestination(),
        hasRunInitialCaptureScan: true,
        isScanningCapture: false
    )

    #expect(advice.isEmpty)
}
