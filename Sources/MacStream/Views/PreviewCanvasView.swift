import SwiftUI
import MacStreamCore

struct PreviewCanvasView: View {
    var scene: StudioScene
    var signals: SignalSnapshot
    var previewConfiguration = PreviewCaptureConfiguration()
    var cameraEnhancements = CameraEnhancementSettings()
    var layoutSettings = StudioLayoutSettings()
    var cameraDeviceID: String?
    var isCameraEnabled = true
    var isCameraCaptureReady = true
    var isScreenEnabled = true
    var screenLevel = 1.0
    var isScreenCaptureReady = true
    var screenCaptureTarget: ScreenCaptureTarget?
    var onCameraPreviewFailure: (@MainActor (String) -> Void)? = nil

    var body: some View {
        GeometryReader { proxy in
            let canvasLayout = StudioCanvasLayout(size: proxy.size, settings: layoutSettings)

            ZStack {
                canvasBackground

                Group {
                    switch scene.kind {
                    case .face:
                        zoomedCameraFill
                    case .screenAndFace:
                        screenAndWebcamLayout(in: canvasLayout)
                    case .screenOnly:
                        zoomedScreenFill
                    case .brb:
                        brbLayer
                    }
                }
                .padding(canvasLayout.canvasInset)
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
                ScreenCapturePreviewView(
                    configuration: previewConfiguration,
                    captureTarget: screenCaptureTarget
                )
                .opacity(screenPreviewOpacity)
            }
        }
    }

    private var zoomedScreenFill: some View {
        sourceViewport(zoom: layoutSettings.screenZoom) {
            screenFill
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
                CameraPreviewView(
                    configuration: previewConfiguration,
                    cameraEnhancements: cameraEnhancements,
                    cameraDeviceID: cameraDeviceID,
                    onSetupFailure: onCameraPreviewFailure
                )
            }
        }
    }

    private var zoomedCameraFill: some View {
        sourceViewport(zoom: layoutSettings.webcamZoom) {
            cameraFill
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

    private func screenAndWebcamLayout(in layout: StudioCanvasLayout) -> some View {
        Group {
            if layoutSettings.preset.isSplit {
                splitScreenAndWebcamLayout(in: layout)
            } else {
                pictureInPictureLayout(in: layout)
            }
        }
    }

    private func splitScreenAndWebcamLayout(in layout: StudioCanvasLayout) -> some View {
        HStack(spacing: layout.sourceGap) {
            sourceFrame {
                zoomedScreenFill
            }
            .frame(width: layout.splitScreenRect.width)

            sourceFrame {
                zoomedCameraFill
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func pictureInPictureLayout(in layout: StudioCanvasLayout) -> some View {
        let pipRect = layout.pictureInPictureRect
        let trailingPadding = layout.contentRect.maxX - pipRect.maxX
        let bottomPadding = pipRect.minY - layout.contentRect.minY

        return ZStack {
            zoomedScreenFill

            sourceFrame {
                sourceViewport(zoom: layoutSettings.webcamZoom) {
                    pictureInPictureCamera
                }
            }
            .frame(width: pipRect.width, height: pipRect.height)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, trailingPadding)
            .padding(.bottom, bottomPadding)
        }
    }

    private func sourceViewport<Content: View>(
        zoom: Double,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .scaleEffect(StudioLayoutSettings.normalizedSourceZoom(zoom))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }

    private func sourceFrame<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.72))
            .clipped()
    }

    private var canvasBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(backgroundFill)
    }

    private var backgroundFill: Color {
        switch layoutSettings.backgroundStyle {
        case .black:
            Color.black
        case .studio:
            Color(red: 0.06, green: 0.07, blue: 0.10)
        case .stage:
            Color(red: 0.08, green: 0.02, blue: 0.04)
        case .warm:
            Color(red: 0.14, green: 0.10, blue: 0.06)
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
