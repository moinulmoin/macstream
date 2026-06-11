import Foundation

public struct PreflightAdvice: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var action: PreflightAdviceAction

    public init(id: String, title: String, detail: String, action: PreflightAdviceAction) {
        self.id = id
        self.title = title
        self.detail = detail
        self.action = action
    }
}

public enum PreflightAdviceAction: Equatable, Sendable {
    case openCaptureSettings(CaptureDeviceKind)
    case rescanCapture
    case selectScreenCaptureTarget(ScreenCaptureTarget)
    case selectCameraDevice(String)
    case selectMicrophoneDevice(String)
    case fixSelectedSceneSources
    case usePreviewDestination
}

public enum PreflightCoach {
    public static func advice(
        report: CapturePreflightReport,
        sources: [StudioSource],
        selectedScene: SceneKind,
        selectedScreenCaptureTarget: ScreenCaptureTarget?,
        selectedCameraDeviceID: String?,
        selectedMicrophoneDeviceID: String?,
        destination: StreamDestination,
        hasRunInitialCaptureScan: Bool,
        isScanningCapture: Bool
    ) -> [PreflightAdvice] {
        if isScanningCapture {
            return [
                PreflightAdvice(
                    id: "capture-checking",
                    title: "Checking capture permissions",
                    detail: report.summary,
                    action: .rescanCapture
                )
            ]
        }

        guard hasRunInitialCaptureScan else {
            return [
                PreflightAdvice(
                    id: "capture-unchecked",
                    title: "Check capture permissions",
                    detail: "Run a capture scan before going live.",
                    action: .rescanCapture
                )
            ]
        }

        let requiredPermissionKinds = requiredCapturePermissionKinds(for: selectedScene, sources: sources)
        let missingPermissionKinds = report.missingPermissionKinds(requiredKinds: requiredPermissionKinds)
        if !missingPermissionKinds.isEmpty {
            return missingPermissionKinds.map { kind in
                let settingsKind = screenSettingsKind(for: kind)
                guard report.permissionState(for: settingsKind) != nil else {
                    return PreflightAdvice(
                        id: "hardware-\(settingsKind.id)",
                        title: "Connect \(permissionTitle(for: settingsKind)) hardware",
                        detail: permissionDetail(for: settingsKind, report: report),
                        action: .rescanCapture
                    )
                }

                return PreflightAdvice(
                    id: "permission-\(settingsKind.id)",
                    title: "Grant \(permissionTitle(for: settingsKind)) access",
                    detail: permissionDetail(for: settingsKind, report: report),
                    action: .openCaptureSettings(settingsKind)
                )
            }
        }

        if sceneUsesScreenCaptureVideo(selectedScene) && sourceIsReady(.screen, sources: sources) {
            if let advice = screenCaptureTargetAdvice(
                report: report,
                selectedScreenCaptureTarget: selectedScreenCaptureTarget
            ) {
                return [advice]
            }
        }

        if sourceIsReady(.camera, sources: sources), requiredSourceKinds(for: selectedScene).contains(.camera) {
            if let advice = inputDeviceAdvice(
                kind: .camera,
                selectedID: selectedCameraDeviceID,
                report: report
            ) {
                return [advice]
            }
        }

        if sourceIsReady(.microphone, sources: sources), selectedScene != .brb {
            if let advice = inputDeviceAdvice(
                kind: .microphone,
                selectedID: selectedMicrophoneDeviceID,
                report: report
            ) {
                return [advice]
            }
        }

        if hasRepairableSelectedSceneSource(selectedScene: selectedScene, sources: sources) {
            return [
                PreflightAdvice(
                    id: "selected-scene-sources",
                    title: "Fix scene sources",
                    detail: "Enable or raise the needed sources for \(selectedScene.title).",
                    action: .fixSelectedSceneSources
                )
            ]
        }

        if !destination.isReadyToStart {
            return [
                PreflightAdvice(
                    id: "destination-preview",
                    title: "Use preview destination",
                    detail: destination.validationError ?? "Destination is not ready.",
                    action: .usePreviewDestination
                )
            ]
        }

        return []
    }

    private static func screenCaptureTargetAdvice(
        report: CapturePreflightReport,
        selectedScreenCaptureTarget: ScreenCaptureTarget?
    ) -> PreflightAdvice? {
        let targets = report.screenCaptureTargets
        guard !targets.isEmpty else {
            return PreflightAdvice(
                id: "screen-target-missing",
                title: "Connect a screen target",
                detail: "No display or window is available. Check hardware, then scan again.",
                action: .rescanCapture
            )
        }

        guard selectedScreenCaptureTarget == nil else { return nil }
        let target = targets.first { $0.kind == .display } ?? targets[0]
        return PreflightAdvice(
            id: "screen-target-select",
            title: "Select a screen target",
            detail: "Use \(target.title) for \(target.kind.title.lowercased()) capture.",
            action: .selectScreenCaptureTarget(target)
        )
    }

    private static func inputDeviceAdvice(
        kind: CaptureDeviceKind,
        selectedID: String?,
        report: CapturePreflightReport
    ) -> PreflightAdvice? {
        let devices = report.devices.filter { $0.kind == kind && $0.permission == .granted }
        guard !devices.isEmpty else {
            return PreflightAdvice(
                id: "\(kind.id)-device-missing",
                title: "Connect \(kind.title.lowercased()) hardware",
                detail: "No granted \(kind.title.lowercased()) device is available. Check hardware, then scan again.",
                action: .rescanCapture
            )
        }

        guard selectedID == nil else { return nil }
        let device = devices[0]
        return PreflightAdvice(
            id: "\(kind.id)-device-select",
            title: "Select \(kind.title.lowercased())",
            detail: "Use \(device.name) for \(kind.title.lowercased()) capture.",
            action: kind == .camera ? .selectCameraDevice(device.id) : .selectMicrophoneDevice(device.id)
        )
    }

    private static func hasRepairableSelectedSceneSource(selectedScene: SceneKind, sources: [StudioSource]) -> Bool {
        recommendedSourceKinds(for: selectedScene).contains { kind in
            guard let source = sources.first(where: { $0.kind == kind }) else { return true }
            return !source.isEnabled || (source.kind.supportsLevelControl && source.level <= 0)
        }
    }

    private static func sourceIsReady(_ kind: SourceKind, sources: [StudioSource]) -> Bool {
        guard let source = sources.first(where: { $0.kind == kind }), source.isEnabled else { return false }
        guard source.kind.supportsLevelControl else { return true }
        return source.level > 0
    }

    private static func requiredSourceKinds(for sceneKind: SceneKind) -> [SourceKind] {
        switch sceneKind {
        case .face:
            [.camera]
        case .screenAndFace:
            [.screen, .camera]
        case .screenOnly:
            [.screen]
        case .brb:
            []
        }
    }

    private static func recommendedSourceKinds(for sceneKind: SceneKind) -> [SourceKind] {
        var kinds = requiredSourceKinds(for: sceneKind)
        if sceneKind != .brb {
            kinds.append(.microphone)
        }
        return kinds.reduce(into: []) { uniqueKinds, kind in
            guard !uniqueKinds.contains(kind) else { return }
            uniqueKinds.append(kind)
        }
    }

    private static func requiredCapturePermissionKinds(for sceneKind: SceneKind, sources: [StudioSource]) -> [CaptureDeviceKind] {
        switch sceneKind {
        case .face:
            return sourceIsReady(SourceKind.camera, sources: sources) ? [CaptureDeviceKind.camera] : []
        case .screenAndFace:
            var kinds: [CaptureDeviceKind] = []
            if sourceIsReady(SourceKind.screen, sources: sources) {
                kinds.append(CaptureDeviceKind.display)
            }
            if sourceIsReady(SourceKind.camera, sources: sources) {
                kinds.append(CaptureDeviceKind.camera)
            }
            return kinds
        case .screenOnly:
            return sourceIsReady(SourceKind.screen, sources: sources) ? [CaptureDeviceKind.display] : []
        case .brb:
            return []
        }
    }

    private static func sceneUsesScreenCaptureVideo(_ sceneKind: SceneKind) -> Bool {
        sceneKind == .screenAndFace || sceneKind == .screenOnly
    }

    private static func screenSettingsKind(for kind: CaptureDeviceKind) -> CaptureDeviceKind {
        switch kind {
        case .display, .window:
            .display
        case .camera, .microphone:
            kind
        }
    }

    private static func permissionTitle(for kind: CaptureDeviceKind) -> String {
        switch kind {
        case .display, .window:
            "Screen Recording"
        case .camera:
            "Camera"
        case .microphone:
            "Microphone"
        }
    }

    private static func permissionDetail(for kind: CaptureDeviceKind, report: CapturePreflightReport) -> String {
        if let state = report.permissionState(for: kind) {
            return "\(permissionTitle(for: kind)) permission is \(state.title.lowercased()). Open System Settings to fix it."
        }
        return "\(permissionTitle(for: kind)) hardware was not found. Check hardware, then scan again."
    }
}
