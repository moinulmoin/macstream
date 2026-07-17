@preconcurrency import AVFoundation
import Foundation

public struct NativeCameraEffectsSnapshot: Equatable, Sendable {
    public var cameraName: String
    public var isContinuityCamera: Bool
    public var centerStageSupported: Bool
    public var centerStageActive: Bool
    public var portraitSupported: Bool
    public var portraitActive: Bool
    public var studioLightSupported: Bool
    public var studioLightActive: Bool
    public var backgroundReplacementSupported: Bool
    public var backgroundReplacementActive: Bool
    public var reactionsAvailable: Bool
    public var reactionGesturesEnabled: Bool

    public init(
        cameraName: String,
        isContinuityCamera: Bool,
        centerStageSupported: Bool,
        centerStageActive: Bool,
        portraitSupported: Bool,
        portraitActive: Bool,
        studioLightSupported: Bool,
        studioLightActive: Bool,
        backgroundReplacementSupported: Bool,
        backgroundReplacementActive: Bool,
        reactionsAvailable: Bool,
        reactionGesturesEnabled: Bool
    ) {
        self.cameraName = cameraName
        self.isContinuityCamera = isContinuityCamera
        self.centerStageSupported = centerStageSupported
        self.centerStageActive = centerStageActive
        self.portraitSupported = portraitSupported
        self.portraitActive = portraitActive
        self.studioLightSupported = studioLightSupported
        self.studioLightActive = studioLightActive
        self.backgroundReplacementSupported = backgroundReplacementSupported
        self.backgroundReplacementActive = backgroundReplacementActive
        self.reactionsAvailable = reactionsAvailable
        self.reactionGesturesEnabled = reactionGesturesEnabled
    }
}

public struct NativeCameraEffectsStatus: Equatable, Sendable {
    public var rows: [NativeCameraEffectsStatusRow]

    public init(rows: [NativeCameraEffectsStatusRow]) {
        self.rows = rows
    }

    public static func make(from snapshot: NativeCameraEffectsSnapshot?) -> Self {
        guard let snapshot else {
            return Self(rows: [
                NativeCameraEffectsStatusRow(
                    title: "Camera Effects",
                    value: "No camera selected",
                    tone: .muted,
                    systemImage: "video.slash"
                )
            ])
        }

        return Self(rows: [
            NativeCameraEffectsStatusRow(
                title: "Continuity",
                value: snapshot.isContinuityCamera ? snapshot.cameraName : "Built-in or USB",
                tone: snapshot.isContinuityCamera ? .active : .muted,
                systemImage: snapshot.isContinuityCamera ? "iphone.gen3" : "video"
            ),
            NativeCameraEffectsStatusRow(
                title: "Center Stage",
                value: centerStageValue(supported: snapshot.centerStageSupported, active: snapshot.centerStageActive),
                tone: tone(supported: snapshot.centerStageSupported, active: snapshot.centerStageActive),
                systemImage: "person.crop.rectangle"
            ),
            NativeCameraEffectsStatusRow(
                title: "Portrait",
                value: effectValue(supported: snapshot.portraitSupported, active: snapshot.portraitActive),
                tone: tone(supported: snapshot.portraitSupported, active: snapshot.portraitActive),
                systemImage: "person.crop.circle"
            ),
            NativeCameraEffectsStatusRow(
                title: "Studio Light",
                value: effectValue(supported: snapshot.studioLightSupported, active: snapshot.studioLightActive),
                tone: tone(supported: snapshot.studioLightSupported, active: snapshot.studioLightActive),
                systemImage: "sun.max"
            ),
            NativeCameraEffectsStatusRow(
                title: "Background",
                value: effectValue(
                    supported: snapshot.backgroundReplacementSupported,
                    active: snapshot.backgroundReplacementActive
                ),
                tone: tone(
                    supported: snapshot.backgroundReplacementSupported,
                    active: snapshot.backgroundReplacementActive
                ),
                systemImage: "rectangle.on.rectangle"
            ),
            NativeCameraEffectsStatusRow(
                title: "Reactions",
                value: reactionsValue(available: snapshot.reactionsAvailable, gesturesEnabled: snapshot.reactionGesturesEnabled),
                tone: snapshot.reactionsAvailable ? .available : .muted,
                systemImage: "hands.sparkles"
            )
        ])
    }

    private static func centerStageValue(supported: Bool, active: Bool) -> String {
        guard supported else { return "Unsupported" }
        return active ? "Active" : "Supported"
    }

    private static func effectValue(supported: Bool, active: Bool) -> String {
        guard supported else { return "Unsupported" }
        return active ? "Active" : "Off"
    }

    private static func reactionsValue(available: Bool, gesturesEnabled: Bool) -> String {
        guard available else { return "Unavailable" }
        return gesturesEnabled ? "Available" : "Manual only"
    }

    private static func tone(supported: Bool, active: Bool) -> NativeCameraEffectsStatusTone {
        if active { return .active }
        if supported { return .available }
        return .muted
    }
}

public struct NativeCameraEffectsStatusRow: Equatable, Sendable, Identifiable {
    public var id: String { title }
    public var title: String
    public var value: String
    public var tone: NativeCameraEffectsStatusTone
    public var systemImage: String

    public init(title: String, value: String, tone: NativeCameraEffectsStatusTone, systemImage: String) {
        self.title = title
        self.value = value
        self.tone = tone
        self.systemImage = systemImage
    }
}

public enum NativeCameraEffectsStatusTone: Equatable, Sendable {
    case active
    case available
    case muted
}

public enum NativeCameraEffects {
    public static func cameraUniqueID(fromCaptureDeviceID id: String?) -> String? {
        guard let id else { return nil }
        let prefix = "camera-"
        guard id.hasPrefix(prefix) else { return id }
        return String(id.dropFirst(prefix.count))
    }

    public static func snapshot(for device: AVCaptureDevice) -> NativeCameraEffectsSnapshot {
        NativeCameraEffectsSnapshot(
            cameraName: device.localizedName,
            isContinuityCamera: device.isContinuityCamera,
            centerStageSupported: device.activeFormat.isCenterStageSupported,
            centerStageActive: device.isCenterStageActive,
            portraitSupported: device.activeFormat.isPortraitEffectSupported,
            portraitActive: device.isPortraitEffectActive,
            studioLightSupported: device.activeFormat.isStudioLightSupported,
            studioLightActive: device.isStudioLightActive,
            backgroundReplacementSupported: device.activeFormat.isBackgroundReplacementSupported,
            backgroundReplacementActive: device.isBackgroundReplacementActive,
            reactionsAvailable: device.canPerformReactionEffects,
            reactionGesturesEnabled: AVCaptureDevice.reactionEffectGesturesEnabled
        )
    }
}
