import SwiftUI
import MacStreamCore

struct PreviewCanvasView: View {
    var scene: StudioScene
    var signals: SignalSnapshot
    var previewConfiguration = PreviewCaptureConfiguration()
    var cameraEnhancements = CameraEnhancementSettings()
    var isCameraEnabled = true
    var isCameraCaptureReady = true
    var isScreenEnabled = true
    var screenLevel = 1.0
    var isScreenCaptureReady = true
    var screenCaptureTarget: ScreenCaptureTarget?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.black)

                switch scene.kind {
                case .face:
                    cameraFill
                case .screenAndFace:
                    screenFill
                    pictureInPictureCamera
                        .frame(width: min(proxy.size.width * 0.28, 260), height: min(proxy.size.height * 0.28, 170))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(.white.opacity(0.24), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(18)
                case .screenOnly:
                    screenFill
                case .brb:
                    brbLayer
                }

                VStack {
                    HStack {
                        Label(scene.title, systemImage: scene.kind.symbolName)
                            .font(.headline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.42), in: Capsule())
                            .overlay {
                                Capsule()
                                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                            }
                        Spacer()
                    }
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(16)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(scene.title) preview"))
        .accessibilityValue(Text(previewAccessibilityValue))
    }

    private var previewAccessibilityValue: String {
        "\(cameraAccessibilityValue). \(screenAccessibilityValue). Active app \(signals.activeApplication)."
    }

    private var cameraAccessibilityValue: String {
        if !isCameraEnabled { return "Camera off" }
        return isCameraCaptureReady ? "Camera ready" : "Camera capture not ready"
    }

    private var screenAccessibilityValue: String {
        if !isScreenPreviewActive { return "Screen off" }
        return isScreenCaptureReady ? "Screen capture ready" : "Screen capture not ready"
    }

    private var screenFill: some View {
        Group {
            if !isScreenPreviewActive {
                disabledSourceLayer(.screen)
            } else if !isScreenCaptureReady {
                screenCaptureUnavailableLayer
            } else {
                ZStack(alignment: .topLeading) {
                    ScreenCapturePreviewView(
                        configuration: previewConfiguration,
                        captureTarget: screenCaptureTarget
                    )
                    .opacity(screenPreviewOpacity)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Circle().fill(.red).frame(width: 9, height: 9)
                            Circle().fill(.yellow).frame(width: 9, height: 9)
                            Circle().fill(.green).frame(width: 9, height: 9)
                        }
                        .accessibilityHidden(true)

                        Text(signals.activeApplication)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(18)
                    .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                    }
                    .padding(18)
                }
            }
        }
    }

    private var isScreenPreviewActive: Bool {
        isScreenEnabled && screenPreviewOpacity > 0
    }

    private var screenPreviewOpacity: Double {
        min(max(screenLevel, 0), 1)
    }

    private var screenCaptureUnavailableLayer: some View {
        VStack(spacing: 10) {
            Image(systemName: "display.trianglebadge.exclamationmark")
                .font(.system(size: 34, weight: .semibold))
            Text("Screen Capture Not Ready")
                .font(.headline)
            Text("Grant Screen Recording access in Capture preflight.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.56))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.72))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }

    private var cameraFill: some View {
        Group {
            if !isCameraEnabled {
                disabledSourceLayer(.camera)
            } else if !isCameraCaptureReady {
                cameraCaptureUnavailableLayer
            } else {
                ZStack {
                    CameraPreviewView(
                        configuration: previewConfiguration,
                        cameraEnhancements: cameraEnhancements
                    )

                    VStack {
                        Spacer()
                        Text(signals.isSpeaking ? "Speaking" : "Listening")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.44), in: Capsule())
                            .padding(10)
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }

    private var pictureInPictureCamera: some View {
        Group {
            if !isCameraEnabled {
                disabledSourceLayer(.camera)
                    .background(.black.opacity(0.72))
            } else if !isCameraCaptureReady {
                cameraCaptureUnavailableLayer
                    .background(.black.opacity(0.72))
            } else {
                cameraFill
            }
        }
    }

    private var cameraCaptureUnavailableLayer: some View {
        VStack(spacing: 10) {
            Image(systemName: "video.badge.exclamationmark")
                .font(.system(size: 34, weight: .semibold))
            Text("Camera Capture Not Ready")
                .font(.headline)
            Text("Grant camera access in Capture preflight.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.56))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.72))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }

    private var brbLayer: some View {
        VStack(spacing: 12) {
            Image(systemName: "pause.rectangle.fill")
                .font(.system(size: 52))
            Text("Be Right Back")
                .font(.system(size: 36, weight: .semibold))
            Text("Camera and screen capture stay idle on this scene.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.62))
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
    }

    private func disabledSourceLayer(_ kind: SourceKind) -> some View {
        VStack(spacing: 10) {
            Image(systemName: kind.symbolName)
                .font(.system(size: 34, weight: .semibold))
            Text("\(kind.title) Off")
                .font(.headline)
            Text("Enable it in Sources before going live.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.56))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.72))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }
}
