@preconcurrency import AVFoundation
import Testing
@testable import MacStreamCore

@Test
func cameraDiscoveryTypesKeepExistingCamerasAndAddContinuityTypes() {
    let deviceTypes = SystemCaptureDeviceProvider.cameraDiscoveryDeviceTypes()

    #expect(deviceTypes == [
        .builtInWideAngleCamera,
        .external,
        .continuityCamera,
        .deskViewCamera
    ])
}

@Test
func cameraUniqueIDStripsCaptureDevicePrefixOnlyWhenPresent() {
    #expect(NativeCameraEffects.cameraUniqueID(fromCaptureDeviceID: "camera-abc-123") == "abc-123")
    #expect(NativeCameraEffects.cameraUniqueID(fromCaptureDeviceID: "raw-device-id") == "raw-device-id")
    #expect(NativeCameraEffects.cameraUniqueID(fromCaptureDeviceID: nil) == nil)
}

@Test
func nativeCameraEffectsStatusMapsActiveAndAvailableStates() {
    let snapshot = NativeCameraEffectsSnapshot(
        cameraName: "Moinul's iPhone",
        isContinuityCamera: true,
        centerStageSupported: true,
        centerStageActive: false,
        portraitSupported: true,
        portraitActive: true,
        studioLightSupported: true,
        studioLightActive: false,
        backgroundReplacementSupported: true,
        backgroundReplacementActive: true,
        reactionsAvailable: true,
        reactionGesturesEnabled: false
    )

    let rows = NativeCameraEffectsStatus.make(from: snapshot).rows

    #expect(rows.map(\.title) == ["Continuity", "Center Stage", "Portrait", "Studio Light", "Background", "Reactions"])
    #expect(rows[0].value == "Moinul's iPhone")
    #expect(rows[0].tone == .active)
    #expect(rows[1].value == "Supported")
    #expect(rows[1].tone == .available)
    #expect(rows[2].value == "Active")
    #expect(rows[2].tone == .active)
    #expect(rows[3].value == "Off")
    #expect(rows[3].tone == .available)
    #expect(rows[4].value == "Active")
    #expect(rows[4].tone == .active)
    #expect(rows[5].value == "Manual only")
    #expect(rows[5].tone == .available)
}

@Test
func nativeCameraEffectsStatusReportsUnsupportedAndUnavailableStates() {
    let snapshot = NativeCameraEffectsSnapshot(
        cameraName: "Studio Display Camera",
        isContinuityCamera: false,
        centerStageSupported: false,
        centerStageActive: false,
        portraitSupported: false,
        portraitActive: false,
        studioLightSupported: false,
        studioLightActive: false,
        backgroundReplacementSupported: false,
        backgroundReplacementActive: false,
        reactionsAvailable: false,
        reactionGesturesEnabled: true
    )

    let rows = NativeCameraEffectsStatus.make(from: snapshot).rows

    #expect(rows[0].value == "Built-in or USB")
    #expect(rows[0].tone == .muted)
    #expect(rows[1].value == "Unsupported")
    #expect(rows[1].tone == .muted)
    #expect(rows[5].value == "Unavailable")
    #expect(rows[5].tone == .muted)
}

@Test
func nativeCameraEffectsStatusHandlesMissingSelection() {
    let rows = NativeCameraEffectsStatus.make(from: nil).rows

    #expect(rows.count == 1)
    #expect(rows[0].title == "Camera Effects")
    #expect(rows[0].value == "No camera selected")
    #expect(rows[0].tone == .muted)
}
