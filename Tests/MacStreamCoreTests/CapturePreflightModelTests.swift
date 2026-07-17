import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import Network
import Testing
@testable import MacStreamCore

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
func preflightAdviceRequestsNativeCameraAndMicrophonePermissionWhenPromptable() {
    let sources = [
        StudioSource(kind: .camera),
        StudioSource(kind: .screen),
        StudioSource(kind: .microphone)
    ]

    let cameraAdvice = PreflightCoach.advice(
        report: CapturePreflightReport(devices: [
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .notDetermined)
        ]),
        sources: sources,
        selectedScene: .face,
        selectedScreenCaptureTarget: nil,
        selectedCameraDeviceID: nil,
        selectedMicrophoneDeviceID: nil,
        destination: StreamDestination(),
        hasRunInitialCaptureScan: true,
        isScanningCapture: false
    )

    #expect(cameraAdvice.first?.action == .requestCapturePermission(.camera))
    #expect(cameraAdvice.first?.detail == "Camera permission has not been granted yet. Ask macOS for access.")

    let microphoneAdvice = PreflightCoach.advice(
        report: CapturePreflightReport(devices: [
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .granted),
            CaptureDeviceInfo(id: "microphone-1", kind: .microphone, name: "Studio Mic", permission: .notDetermined)
        ]),
        sources: sources,
        selectedScene: .face,
        selectedScreenCaptureTarget: nil,
        selectedCameraDeviceID: "camera-1",
        selectedMicrophoneDeviceID: nil,
        destination: StreamDestination(),
        hasRunInitialCaptureScan: true,
        isScanningCapture: false
    )

    #expect(microphoneAdvice.first?.action == .requestCapturePermission(.microphone))
    #expect(microphoneAdvice.first?.detail == "Microphone permission has not been granted yet. Ask macOS for access.")
}

@Test
func preflightAdviceKeepsSettingsAndRelaunchPathForBlockedPermissions() {
    let sources = [
        StudioSource(kind: .camera),
        StudioSource(kind: .screen),
        StudioSource(kind: .microphone)
    ]

    let deniedCameraAdvice = PreflightCoach.advice(
        report: CapturePreflightReport(devices: [
            CaptureDeviceInfo(id: "camera-1", kind: .camera, name: "FaceTime Camera", permission: .denied)
        ]),
        sources: sources,
        selectedScene: .face,
        selectedScreenCaptureTarget: nil,
        selectedCameraDeviceID: nil,
        selectedMicrophoneDeviceID: nil,
        destination: StreamDestination(),
        hasRunInitialCaptureScan: true,
        isScanningCapture: false
    )

    #expect(deniedCameraAdvice.first?.action == .openCaptureSettings(.camera))
    #expect(deniedCameraAdvice.first?.detail == "Camera permission was denied. Open System Settings to grant access.")

    let screenAdvice = PreflightCoach.advice(
        report: CapturePreflightReport(devices: [
            CaptureDeviceInfo(id: "display-1", kind: .display, name: "Studio Display", permission: .notDetermined)
        ]),
        sources: sources,
        selectedScene: .screenOnly,
        selectedScreenCaptureTarget: nil,
        selectedCameraDeviceID: nil,
        selectedMicrophoneDeviceID: nil,
        destination: StreamDestination(),
        hasRunInitialCaptureScan: true,
        isScanningCapture: false
    )

    #expect(screenAdvice.first?.action == .openCaptureSettings(.display))
    #expect(screenAdvice.first?.detail == "Screen Recording permission has not been granted yet. Open System Settings, then reopen MacStream.")
}

@Test
func incompleteRTMPAdviceKeepsDestinationSetupAsPrimaryIntent() {
    let advice = PreflightCoach.advice(
        report: CapturePreflightReport(),
        sources: [],
        selectedScene: .brb,
        selectedScreenCaptureTarget: nil,
        selectedCameraDeviceID: nil,
        selectedMicrophoneDeviceID: nil,
        destination: StreamDestination(mode: .rtmp, name: "Twitch", rtmpURL: ""),
        hasRunInitialCaptureScan: true,
        isScanningCapture: false
    )

    #expect(advice.first?.id == "destination-rtmp-setup")
    #expect(advice.first?.title == "Finish RTMP setup")
    #expect(advice.first?.action == .openDestinationSetup)
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
