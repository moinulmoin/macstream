@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit

public protocol CaptureDeviceProvider: Sendable {
    func scan() async -> CapturePreflightReport
}

protocol ScreenCaptureContentListing: Sendable {
    func devices(permission: CapturePermissionState) async throws -> [CaptureDeviceInfo]
}

struct ScreenCaptureKitContentListing: ScreenCaptureContentListing {
    func devices(permission: CapturePermissionState) async throws -> [CaptureDeviceInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displays = content.displays.map { display in
            CaptureDeviceInfo(
                id: "display-\(display.displayID)",
                kind: .display,
                name: "Display \(display.displayID)",
                detail: "\(display.width)x\(display.height)",
                permission: permission
            )
        }

        let windows = content.windows
            .prefix(6)
            .map { window in
                let appName = window.owningApplication?.applicationName ?? "Unknown App"
                let title = window.title?.isEmpty == false ? window.title! : appName
                return CaptureDeviceInfo(
                    id: "window-\(window.windowID)",
                    kind: .window,
                    name: title,
                    detail: appName,
                    permission: permission
                )
            }

        return displays + windows
    }
}

public struct SystemCaptureDeviceProvider: CaptureDeviceProvider {
    private let screenCaptureAccessProvider: @Sendable () -> Bool
    private let screenContentListing: any ScreenCaptureContentListing

    public init() {
        self.init(
            screenCaptureAccessProvider: { CGPreflightScreenCaptureAccess() },
            screenContentListing: ScreenCaptureKitContentListing()
        )
    }

    init(
        screenCaptureAccessProvider: @escaping @Sendable () -> Bool,
        screenContentListing: any ScreenCaptureContentListing
    ) {
        self.screenCaptureAccessProvider = screenCaptureAccessProvider
        self.screenContentListing = screenContentListing
    }

    public func scan() async -> CapturePreflightReport {
        var devices: [CaptureDeviceInfo] = []

        devices.append(contentsOf: cameraDevices())
        devices.append(contentsOf: microphoneDevices())
        devices.append(contentsOf: await screenDevices())

        let summary = CapturePreflightReport.permissionAttentionSummary(for: devices)

        return CapturePreflightReport(devices: devices, summary: summary)
    }

    private func cameraDevices() -> [CaptureDeviceInfo] {
        let permission = permissionState(for: AVCaptureDevice.authorizationStatus(for: .video))
        let session = Self.cameraDiscoverySession()

        return session.devices.map { device in
            CaptureDeviceInfo(
                id: CaptureDeviceInfo.cameraID(uniqueID: device.uniqueID),
                kind: .camera,
                name: device.localizedName,
                detail: device.manufacturer,
                permission: permission
            )
        }
    }

    private func microphoneDevices() -> [CaptureDeviceInfo] {
        let permission = permissionState(for: AVCaptureDevice.authorizationStatus(for: .audio))
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )

        return session.devices.map { device in
            CaptureDeviceInfo(
                id: CaptureDeviceInfo.microphoneID(uniqueID: device.uniqueID),
                kind: .microphone,
                name: device.localizedName,
                detail: device.manufacturer,
                permission: permission
            )
        }
    }

    private func screenDevices() async -> [CaptureDeviceInfo] {
        let permission: CapturePermissionState = screenCaptureAccessProvider() ? .granted : .notDetermined

        guard permission == .granted else {
            return [
                CaptureDeviceInfo(
                    id: "screen-permission",
                    kind: .display,
                    name: "Screen Capture",
                    detail: "Screen Recording permission is not visible to this launch.",
                    permission: permission
                )
            ]
        }

        do {
            return try await screenContentListing.devices(permission: permission)
        } catch {
            return [
                CaptureDeviceInfo(
                    id: "screen-permission",
                    kind: .display,
                    name: "Screen Capture",
                    detail: error.localizedDescription,
                    permission: permission == .granted ? .unknown : permission
                )
            ]
        }
    }

    private func permissionState(for status: AVAuthorizationStatus) -> CapturePermissionState {
        switch status {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .unknown
        }
    }

    public static func cameraDiscoveryDeviceTypes() -> [AVCaptureDevice.DeviceType] {
        [
            .builtInWideAngleCamera,
            .external,
            .continuityCamera,
            .deskViewCamera
        ]
    }

    public static func cameraDiscoverySession() -> AVCaptureDevice.DiscoverySession {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: cameraDiscoveryDeviceTypes(),
            mediaType: .video,
            position: .unspecified
        )
    }

    public static func cameraDevice(matchingCaptureDeviceID id: String) -> AVCaptureDevice? {
        cameraDiscoverySession().devices.first {
            CaptureDeviceInfo.cameraID(uniqueID: $0.uniqueID) == id
        }
    }

    public static func defaultCameraDevice() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
            ?? AVCaptureDevice.default(for: .video)
            ?? cameraDiscoverySession().devices.first
    }
}

public struct PreviewCaptureDeviceProvider: CaptureDeviceProvider {
    public init() {}

    public func scan() async -> CapturePreflightReport {
        CapturePreflightReport(
            devices: [
                CaptureDeviceInfo(id: "preview-camera", kind: .camera, name: "FaceTime Camera", detail: "Preview", permission: .granted),
                CaptureDeviceInfo(id: "preview-mic", kind: .microphone, name: "Studio Mic", detail: "Preview", permission: .granted),
                CaptureDeviceInfo(id: "preview-display", kind: .display, name: "Main Display", detail: "3024x1964", permission: .granted)
            ],
            summary: "Preview capture sources are ready."
        )
    }
}
