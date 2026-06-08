import AppKit
@preconcurrency import AVFoundation
import MacStreamCore

enum CapturePermissionActions {
    @MainActor
    static func requestAccess(for kind: CaptureDeviceKind, store: StudioStore) {
        let mediaType: AVMediaType
        switch kind {
        case .camera:
            mediaType = .video
        case .microphone:
            mediaType = .audio
        case .display, .window:
            return
        }

        AVCaptureDevice.requestAccess(for: mediaType) { _ in
            Task { @MainActor in
                store.scanCaptureDevices()
            }
        }
    }

    static func openSettings(for kind: CaptureDeviceKind) {
        guard let url = privacySettingsURL(for: kind) else { return }
        NSWorkspace.shared.open(url)
    }

    static func privacySettingsURL(for kind: CaptureDeviceKind) -> URL? {
        switch kind {
        case .camera:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
        case .microphone:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .display, .window:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        }
    }
}
