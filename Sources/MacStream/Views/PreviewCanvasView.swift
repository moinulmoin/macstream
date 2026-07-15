import SwiftUI
import MacStreamCore
import AppKit

struct PreviewCanvasView: View {
    var scene: StudioScene
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
    var mediaPreviewFrameSource: MediaPreviewFrameSource?
    var shouldUseMediaOutputPreview = false
    var onCameraPreviewFailure: (@MainActor (String) -> Void)? = nil

    var body: some View {
        previewContent
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
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

    @ViewBuilder
    private var previewContent: some View {
        if shouldUseMediaOutputPreview, let mediaPreviewFrameSource {
            MediaOutputPreviewView(
                source: mediaPreviewFrameSource,
                maximumFramesPerSecond: previewConfiguration.framesPerSecond
            )
            .background(.black)
        } else {
            offlinePreview
        }
    }

    private var offlinePreview: some View {
        GeometryReader { proxy in
            let canvasLayout = StudioCanvasLayout(size: proxy.size, settings: layoutSettings)

            ZStack {
                canvasBackground(in: proxy.size)

                Group {
                    switch scene.kind {
                    case .face:
                        sourceFrame(cornerRadius: canvasLayout.sourceCornerRadius) {
                            zoomedCameraFill
                        }
                        .frame(width: canvasLayout.contentRect.width, height: canvasLayout.contentRect.height)
                        .position(x: canvasLayout.contentRect.midX, y: canvasLayout.contentRect.midY)
                    case .screenAndFace:
                        screenAndWebcamLayout(in: canvasLayout)
                    case .screenOnly:
                        sourceFrame(cornerRadius: canvasLayout.sourceCornerRadius) {
                            zoomedScreenFill
                        }
                        .frame(width: canvasLayout.contentRect.width, height: canvasLayout.contentRect.height)
                        .position(x: canvasLayout.contentRect.midX, y: canvasLayout.contentRect.midY)
                    case .brb:
                        brbLayer
                            .frame(width: canvasLayout.contentRect.width, height: canvasLayout.contentRect.height)
                            .position(x: canvasLayout.contentRect.midX, y: canvasLayout.contentRect.midY)
                    }
                }
            }
        }
    }

    private var previewAccessibilityValue: String {
        "\(cameraAccessibilityValue). \(screenAccessibilityValue)."
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
        sourceViewport(layoutSettings.screenViewport) {
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
        sourceViewport(layoutSettings.webcamViewport) {
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
        ZStack {
            sourceFrame(cornerRadius: layout.sourceCornerRadius) {
                zoomedScreenFill
            }
            .frame(width: layout.splitScreenRect.width, height: layout.splitScreenRect.height)
            .position(x: layout.splitScreenRect.midX, y: layout.splitScreenRect.midY)

            sourceFrame(cornerRadius: layout.sourceCornerRadius) {
                zoomedCameraFill
            }
            .frame(width: layout.splitWebcamRect.width, height: layout.splitWebcamRect.height)
            .position(x: layout.splitWebcamRect.midX, y: layout.splitWebcamRect.midY)
        }
    }

    private func pictureInPictureLayout(in layout: StudioCanvasLayout) -> some View {
        let pipRect = layout.pictureInPictureRect

        return ZStack {
            sourceFrame(cornerRadius: layout.sourceCornerRadius) {
                zoomedScreenFill
            }
            .frame(width: layout.contentRect.width, height: layout.contentRect.height)
            .position(x: layout.contentRect.midX, y: layout.contentRect.midY)

            sourceFrame(cornerRadius: layout.sourceCornerRadius) {
                sourceViewport(layoutSettings.webcamViewport) {
                    pictureInPictureCamera
                }
            }
            .frame(width: pipRect.width, height: pipRect.height)
            .overlay {
                RoundedRectangle(cornerRadius: layout.sourceCornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
            .position(x: pipRect.midX, y: layout.outputRect.height - pipRect.midY)
        }
    }

    private func sourceViewport<Content: View>(
        _ viewport: StudioSourceViewportSettings,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        GeometryReader { proxy in
            let zoom = StudioLayoutSettings.normalizedSourceZoom(viewport.zoom)
            let panX = StudioLayoutSettings.normalizedSourcePan(viewport.panX)
            let panY = StudioLayoutSettings.normalizedSourcePan(viewport.panY)
            let maxPanX = max(0, proxy.size.width * (zoom - 1) / 2)
            let maxPanY = max(0, proxy.size.height * (zoom - 1) / 2)

            content()
                .scaleEffect(zoom)
                .offset(x: -CGFloat(panX) * maxPanX, y: -CGFloat(panY) * maxPanY)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
    }

    private func sourceFrame<Content: View>(
        cornerRadius: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func canvasBackground(in size: CGSize) -> some View {
        switch layoutSettings.background {
        case let .localImage(path):
            if let image = LocalCanvasBackgroundImageCache.shared.image(for: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                backgroundColor(.black)
            }
        case let .color(color):
            backgroundColor(Color(
                .sRGB,
                red: color.red,
                green: color.green,
                blue: color.blue,
                opacity: color.alpha
            ))
        case let .preset(style):
            backgroundColor(Self.backgroundColor(for: style))
        }
    }

    private func backgroundColor(_ color: Color) -> some View {
        Rectangle()
            .fill(color)
    }

    private static func backgroundColor(for style: StudioBackgroundStyle) -> Color {
        switch style {
        case .black:
            .black
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

@MainActor
private final class LocalCanvasBackgroundImageCache {
    static let shared = LocalCanvasBackgroundImageCache()

    private var cachedPath: String?
    private var cachedImage: NSImage?

    func image(for path: String) -> NSImage? {
        guard !path.isEmpty else { return nil }
        if cachedPath == path {
            return cachedImage
        }

        cachedPath = path
        cachedImage = NSImage(contentsOfFile: path)
        return cachedImage
    }
}
