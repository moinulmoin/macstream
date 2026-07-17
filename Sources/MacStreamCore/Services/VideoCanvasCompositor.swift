import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

struct VideoCanvasRenderPlan: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        case screenOnly
        case pictureInPicture
        case split
        case presenterOverlay
    }

    enum BackgroundDescriptor: Equatable, Sendable {
        case color(red: Double, green: Double, blue: Double, alpha: Double)
        case localImage(path: String)
        case fallbackBlack
    }

    var mode: Mode
    var screenRect: CGRect
    var cameraRect: CGRect
    var screenViewport: StudioSourceViewportSettings
    var cameraViewport: StudioSourceViewportSettings
    var sourceCornerRadius: CGFloat
    var backgroundDescriptor: BackgroundDescriptor

    var screenZoom: Double { screenViewport.zoom }
    var cameraZoom: Double { cameraViewport.zoom }

    static func make(
        outputSize: CGSize,
        layoutSettings: StudioLayoutSettings,
        sceneKind: SceneKind = .screenAndFace
    ) -> VideoCanvasRenderPlan {
        let canvasLayout = StudioCanvasLayout(size: outputSize, settings: layoutSettings)
        if sceneKind == .screenOnly {
            return VideoCanvasRenderPlan(
                mode: .screenOnly,
                screenRect: canvasLayout.contentRect.integral,
                cameraRect: .zero,
                screenViewport: layoutSettings.screenViewport,
                cameraViewport: layoutSettings.webcamViewport,
                sourceCornerRadius: canvasLayout.sourceCornerRadius,
                backgroundDescriptor: backgroundDescriptor(for: layoutSettings.background)
            )
        }
        if layoutSettings.presenterComposition.mode == .presenterOverlay {
            let geometry = canvasLayout.presenterComposition
            return VideoCanvasRenderPlan(
                mode: .presenterOverlay,
                screenRect: geometry.screenRect.integral,
                cameraRect: geometry.presenterRect.integral,
                screenViewport: layoutSettings.screenViewport,
                cameraViewport: layoutSettings.webcamViewport,
                sourceCornerRadius: canvasLayout.sourceCornerRadius,
                backgroundDescriptor: backgroundDescriptor(for: layoutSettings.background)
            )
        }
        if layoutSettings.preset.isSplit {
            return VideoCanvasRenderPlan(
                mode: .split,
                screenRect: canvasLayout.splitScreenRect.integral,
                cameraRect: canvasLayout.splitWebcamRect.integral,
                screenViewport: layoutSettings.screenViewport,
                cameraViewport: layoutSettings.webcamViewport,
                sourceCornerRadius: canvasLayout.sourceCornerRadius,
                backgroundDescriptor: backgroundDescriptor(for: layoutSettings.background)
            )
        }

        return VideoCanvasRenderPlan(
            mode: .pictureInPicture,
            screenRect: canvasLayout.contentRect.integral,
            cameraRect: canvasLayout.pictureInPictureRect.integral,
            screenViewport: layoutSettings.screenViewport,
            cameraViewport: layoutSettings.webcamViewport,
            sourceCornerRadius: canvasLayout.sourceCornerRadius,
            backgroundDescriptor: backgroundDescriptor(for: layoutSettings.background)
        )
    }

    static func backgroundDescriptor(
        for background: StudioCanvasBackground,
        isReadableFile: (String) -> Bool = FileManager.default.isReadableFile(atPath:)
    ) -> BackgroundDescriptor {
        switch background {
        case let .preset(style):
            let color = backgroundColor(for: style)
            return .color(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        case let .color(color):
            return .color(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        case let .localImage(path):
            return path.isEmpty || !isReadableFile(path) ? .fallbackBlack : .localImage(path: path)
        }
    }

    static func sourceTransform(
        sourceExtent: CGRect,
        targetRect: CGRect,
        viewport: StudioSourceViewportSettings
    ) -> CGAffineTransform {
        guard !sourceExtent.isEmpty,
              targetRect.width > 0,
              targetRect.height > 0
        else {
            return .identity
        }

        let normalizedViewport = StudioSourceViewportSettings(
            zoom: viewport.zoom,
            panX: viewport.panX,
            panY: viewport.panY
        )
        let baseScale = max(
            targetRect.width / sourceExtent.width,
            targetRect.height / sourceExtent.height
        )
        let scale = baseScale * normalizedViewport.zoom
        let scaledWidth = sourceExtent.width * scale
        let scaledHeight = sourceExtent.height * scale
        let maxPanX = max(0, (scaledWidth - targetRect.width) / 2)
        let maxPanY = max(0, (scaledHeight - targetRect.height) / 2)
        let contentShiftX = -normalizedViewport.panX * maxPanX
        let contentShiftY = normalizedViewport.panY * maxPanY

        return CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: scale,
            tx: targetRect.midX - (sourceExtent.midX * scale) + contentShiftX,
            ty: targetRect.midY - (sourceExtent.midY * scale) + contentShiftY
        )
    }

    private static func backgroundColor(for style: StudioBackgroundStyle) -> StudioRGBAColor {
        switch style {
        case .black:
            StudioRGBAColor(red: 0, green: 0, blue: 0)
        case .studio:
            StudioRGBAColor(red: 0.06, green: 0.07, blue: 0.10)
        case .stage:
            StudioRGBAColor(red: 0.08, green: 0.02, blue: 0.04)
        case .warm:
            StudioRGBAColor(red: 0.14, green: 0.10, blue: 0.06)
        }
    }
}

final class VideoCanvasCompositor {
    private let context = CIContext()
    private let outputRect: CGRect
    private var cameraEnhancements: CameraEnhancementSettings
    private var layoutSettings: StudioLayoutSettings
    private var renderPlan: VideoCanvasRenderPlan
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var background: CIImage
    private var screenSourceMask: CIImage
    private var cameraSourceMask: CIImage
    private lazy var colorControlsFilter: CIFilter? = CIFilter(name: "CIColorControls")

    init(
        outputWidth: Int,
        outputHeight: Int,
        cameraEnhancements: CameraEnhancementSettings,
        layoutSettings: StudioLayoutSettings,
        sceneKind: SceneKind
    ) {
        let outputRect = CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight)
        self.outputRect = outputRect
        self.cameraEnhancements = cameraEnhancements
        self.layoutSettings = layoutSettings
        self.renderPlan = Self.renderPlan(
            outputRect: outputRect,
            layoutSettings: layoutSettings,
            sceneKind: sceneKind
        )
        self.background = Self.backgroundImage(
            for: self.renderPlan.backgroundDescriptor,
            outputRect: outputRect
        )
        self.screenSourceMask = Self.sourceMask(rect: self.renderPlan.screenRect, cornerRadius: self.renderPlan.sourceCornerRadius)
        self.cameraSourceMask = Self.sourceMask(rect: self.renderPlan.cameraRect, cornerRadius: self.renderPlan.sourceCornerRadius)
    }

    func update(
        cameraEnhancements: CameraEnhancementSettings,
        layoutSettings: StudioLayoutSettings,
        sceneKind: SceneKind
    ) {
        let previousPlan = renderPlan
        self.cameraEnhancements = cameraEnhancements
        self.layoutSettings = layoutSettings
        self.renderPlan = Self.renderPlan(
            outputRect: outputRect,
            layoutSettings: layoutSettings,
            sceneKind: sceneKind
        )
        if previousPlan.backgroundDescriptor != renderPlan.backgroundDescriptor {
            background = Self.backgroundImage(
                for: renderPlan.backgroundDescriptor,
                outputRect: outputRect
            )
        }
        if previousPlan.screenRect != renderPlan.screenRect
            || previousPlan.sourceCornerRadius != renderPlan.sourceCornerRadius {
            screenSourceMask = Self.sourceMask(rect: renderPlan.screenRect, cornerRadius: renderPlan.sourceCornerRadius)
        }
        if previousPlan.cameraRect != renderPlan.cameraRect
            || previousPlan.sourceCornerRadius != renderPlan.sourceCornerRadius {
            cameraSourceMask = Self.sourceMask(rect: renderPlan.cameraRect, cornerRadius: renderPlan.sourceCornerRadius)
        }
    }

    func render(
        screenPixelBuffer: CVPixelBuffer,
        cameraPixelBuffer: CVPixelBuffer?,
        cameraMattePixelBuffer: CVPixelBuffer? = nil,
        to outputPixelBuffer: CVPixelBuffer
    ) {
        let screenImage = normalized(CIImage(cvPixelBuffer: screenPixelBuffer))
        let cameraImage = cameraPixelBuffer.map { enhancedCameraImage(from: $0) }
        let cameraMatteImage = cameraMattePixelBuffer.map { orientedCameraImage(CIImage(cvPixelBuffer: $0)) }
        let plan = renderPlan
        var composed = background

        composed = renderSource(
            screenImage,
            in: plan.screenRect,
            viewport: plan.screenViewport,
            mask: screenSourceMask
        )
            .composited(over: composed)
        if plan.mode != .screenOnly {
            let cameraLayer = if plan.mode == .presenterOverlay,
                                 let cameraImage,
                                 let cameraMatteImage {
                renderPresenter(
                    cameraImage,
                    matteImage: cameraMatteImage,
                    in: plan.cameraRect,
                    viewport: plan.cameraViewport
                )
            } else {
                renderCamera(
                    cameraImage,
                    in: plan.cameraRect,
                    viewport: plan.cameraViewport,
                    mask: cameraSourceMask
                )
            }
            composed = cameraLayer.composited(over: composed)
        }

        context.render(
            composed.cropped(to: outputRect),
            to: outputPixelBuffer,
            bounds: outputRect,
            colorSpace: colorSpace
        )
    }

    private static func renderPlan(
        outputRect: CGRect,
        layoutSettings: StudioLayoutSettings,
        sceneKind: SceneKind
    ) -> VideoCanvasRenderPlan {
        VideoCanvasRenderPlan.make(
            outputSize: outputRect.size,
            layoutSettings: layoutSettings,
            sceneKind: sceneKind
        )
    }

    private func renderCamera(
        _ cameraImage: CIImage?,
        in targetRect: CGRect,
        viewport: StudioSourceViewportSettings,
        mask: CIImage
    ) -> CIImage {
        guard let cameraImage else {
            return clipSource(
                CIImage(color: CIColor(red: 0.02, green: 0.02, blue: 0.02))
                    .cropped(to: targetRect),
                to: targetRect,
                mask: mask
            )
        }

        return renderSource(cameraImage, in: targetRect, viewport: viewport, mask: mask)
    }

    private func renderPresenter(
        _ cameraImage: CIImage,
        matteImage: CIImage,
        in targetRect: CGRect,
        viewport: StudioSourceViewportSettings
    ) -> CIImage {
        let targetRect = targetRect.integral
        guard !targetRect.isEmpty,
              !cameraImage.extent.isEmpty,
              !matteImage.extent.isEmpty
        else {
            return CIImage.empty()
        }

        let transform = VideoCanvasRenderPlan.sourceTransform(
            sourceExtent: cameraImage.extent,
            targetRect: targetRect,
            viewport: viewport
        )
        let renderedCamera = cameraImage
            .transformed(by: transform)
            .cropped(to: targetRect)
        let cameraAlignedMatte = matteImage.transformed(by: CGAffineTransform(
            scaleX: cameraImage.extent.width / matteImage.extent.width,
            y: cameraImage.extent.height / matteImage.extent.height
        ))
        let renderedMatte = normalized(cameraAlignedMatte)
            .transformed(by: transform)
            .cropped(to: targetRect)

        return renderedCamera
            .applyingFilter(
                "CIBlendWithMask",
                parameters: [
                    kCIInputBackgroundImageKey: CIImage.empty(),
                    kCIInputMaskImageKey: renderedMatte
                ]
            )
            .cropped(to: targetRect)
    }

    private func renderSource(
        _ image: CIImage,
        in targetRect: CGRect,
        viewport: StudioSourceViewportSettings,
        mask: CIImage
    ) -> CIImage {
        let targetRect = targetRect.integral
        guard !targetRect.isEmpty else {
            return CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: targetRect)
        }

        let transform = VideoCanvasRenderPlan.sourceTransform(
            sourceExtent: image.extent,
            targetRect: targetRect,
            viewport: viewport
        )
        let rendered = image
            .transformed(by: transform)
            .cropped(to: targetRect)
        return clipSource(rendered, to: targetRect, mask: mask)
    }

    private func clipSource(_ image: CIImage, to targetRect: CGRect, mask: CIImage) -> CIImage {
        image.applyingFilter(
            "CIBlendWithAlphaMask",
            parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(),
                kCIInputMaskImageKey: mask
            ]
        )
        .cropped(to: targetRect)
    }

    private func enhancedCameraImage(from pixelBuffer: CVPixelBuffer) -> CIImage {
        let image = orientedCameraImage(CIImage(cvPixelBuffer: pixelBuffer))

        guard cameraEnhancements.usesAutoLight,
              let filter = colorControlsFilter
        else {
            return image
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(cameraEnhancements.autoLightAmount * 0.18, forKey: kCIInputBrightnessKey)
        filter.setValue(1 + cameraEnhancements.autoLightAmount * 0.08, forKey: kCIInputContrastKey)
        filter.setValue(1 + cameraEnhancements.autoLightAmount * 0.10, forKey: kCIInputSaturationKey)
        let outputImage = filter.outputImage.map(normalized) ?? image
        filter.setValue(nil, forKey: kCIInputImageKey)
        return outputImage
    }

    private func orientedCameraImage(_ source: CIImage) -> CIImage {
        var image = normalized(source)

        if cameraEnhancements.mirrorsPreview {
            image = image.transformed(by: CGAffineTransform(scaleX: -1, y: 1))
            image = normalized(image)
        }

        if cameraEnhancements.rotation != .degrees0 {
            image = image.transformed(by: CGAffineTransform(rotationAngle: cameraEnhancements.rotation.radians))
            image = normalized(image)
        }

        return image
    }

    private static func backgroundImage(
        for descriptor: VideoCanvasRenderPlan.BackgroundDescriptor,
        outputRect: CGRect
    ) -> CIImage {
        switch descriptor {
        case let .color(red, green, blue, alpha):
            return CIImage(color: CIColor(red: red, green: green, blue: blue, alpha: alpha))
                .cropped(to: outputRect)
        case let .localImage(path):
            guard let image = CIImage(contentsOf: URL(fileURLWithPath: path), options: [.applyOrientationProperty: true])
            else {
                return blackBackground(outputRect: outputRect)
            }
            return aspectFill(image, in: outputRect)
        case .fallbackBlack:
            return blackBackground(outputRect: outputRect)
        }
    }

    private static func blackBackground(outputRect: CGRect) -> CIImage {
        CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: outputRect)
    }

    private static func sourceMask(rect: CGRect, cornerRadius: CGFloat) -> CIImage {
        let rect = rect.integral
        guard !rect.isEmpty else {
            return CIImage.empty()
        }

        let radius = min(max(0, cornerRadius), min(rect.width, rect.height) / 2)
        guard radius > 0 else {
            return CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
                .cropped(to: rect)
        }

        return CIFilter(
            name: "CIRoundedRectangleGenerator",
            parameters: [
                "inputExtent": CIVector(cgRect: rect),
                "inputRadius": radius,
                "inputColor": CIColor(red: 1, green: 1, blue: 1, alpha: 1)
            ]
        )?.outputImage?.cropped(to: rect)
            ?? CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)).cropped(to: rect)
    }

    private static func aspectFill(_ image: CIImage, in targetRect: CGRect) -> CIImage {
        guard !image.extent.isEmpty,
              targetRect.width > 0,
              targetRect.height > 0
        else {
            return CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: targetRect)
        }

        let scale = max(
            targetRect.width / image.extent.width,
            targetRect.height / image.extent.height
        )
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let translation = CGAffineTransform(
            translationX: targetRect.midX - scaled.extent.midX,
            y: targetRect.midY - scaled.extent.midY
        )
        return scaled
            .transformed(by: translation)
            .cropped(to: targetRect)
    }

    private func normalized(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(
            translationX: -image.extent.minX,
            y: -image.extent.minY
        ))
    }
}
