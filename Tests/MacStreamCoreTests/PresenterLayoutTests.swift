import CoreGraphics
import Foundation
import Testing
@testable import MacStreamCore

@Test
func presenterCompositionSettingsNormalizeAndPersist() throws {
    let settings = StudioPresenterCompositionSettings(
        mode: .presenterOverlay,
        placement: .manual,
        manualPosition: StudioNormalizedPoint(x: 1.8, y: -.infinity),
        scale: 2.4
    )
    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(StudioPresenterCompositionSettings.self, from: encoded)

    #expect(settings.manualPosition == StudioNormalizedPoint(x: 1, y: 0.5))
    #expect(settings.scale == StudioPresenterCompositionSettings.maximumScale)
    #expect(decoded == settings)
}

@Test
func presenterCompositionSettingsDecodeRobustDefaults() throws {
    let persistedSettings = """
    {
      "mode": "futureMode",
      "placement": "futurePlacement",
      "manualPosition": { "x": 0.3336, "y": 4 },
      "scale": -8
    }
    """

    let decoded = try JSONDecoder().decode(
        StudioPresenterCompositionSettings.self,
        from: Data(persistedSettings.utf8)
    )

    #expect(decoded.mode == .preserveLayout)
    #expect(decoded.placement == .right)
    #expect(decoded.manualPosition == StudioNormalizedPoint(x: 0.334, y: 1))
    #expect(decoded.scale == StudioPresenterCompositionSettings.minimumScale)

    let empty = try JSONDecoder().decode(
        StudioPresenterCompositionSettings.self,
        from: Data("{}".utf8)
    )

    #expect(empty == StudioPresenterCompositionSettings())
}

@Test
func studioLayoutSettingsPreserveExistingLayoutsByDefault() throws {
    let persistedLayout = """
    {
      "preset": "screen70Webcam30",
      "background": { "kind": "preset", "style": "stage" }
    }
    """

    let decoded = try JSONDecoder().decode(
        StudioLayoutSettings.self,
        from: Data(persistedLayout.utf8)
    )
    let layout = StudioCanvasLayout(
        size: CGSize(width: 1_280, height: 720),
        settings: decoded
    )

    #expect(decoded.presenterComposition == StudioPresenterCompositionSettings())
    #expect(layout.presenterComposition.screenRect == layout.splitScreenRect)
    #expect(layout.presenterComposition.presenterRect == layout.splitWebcamRect)
}

@Test
func presenterCompositionDisplayTitlesAreStable() {
    #expect(StudioPresenterCompositionMode.preserveLayout.title == "Framed")
    #expect(StudioPresenterCompositionMode.presenterOverlay.title == "Cutout")
    #expect(StudioPresenterPlacement.left.title == "Left")
    #expect(StudioPresenterPlacement.right.title == "Right")
    #expect(StudioPresenterPlacement.top.title == "Top")
    #expect(StudioPresenterPlacement.bottom.title == "Bottom")
    #expect(StudioPresenterPlacement.manual.title == "Manual")
}

@Test
func studioCanvasLayoutComputesPresenterOverlayGeometry() {
    let settings = StudioLayoutSettings(
        preset: .screen70Webcam30,
        canvasPadding: 0.05,
        presenterComposition: StudioPresenterCompositionSettings(
            mode: .presenterOverlay,
            placement: .bottom,
            scale: 0.25
        )
    )
    let layout = StudioCanvasLayout(
        size: CGSize(width: 1_600, height: 900),
        settings: settings
    )
    let geometry = layout.presenterComposition

    #expect(geometry.screenRect == layout.contentRect)
    #expect(geometry.presenterRect == layout.presenterOverlayRect)
    #expect(abs(geometry.presenterRect.width - (layout.contentRect.width * 0.25)) < 0.001)
    #expect(abs(geometry.presenterRect.height - (geometry.presenterRect.width * 9 / 16)) < 0.001)
    #expect(abs(geometry.presenterRect.midX - layout.contentRect.midX) < 0.001)
    #expect(geometry.presenterRect.midY < layout.contentRect.midY)
}

@Test
func studioCanvasLayoutClampsManualPresenterOverlayGeometry() {
    let settings = StudioLayoutSettings(
        preset: .pictureInPicture,
        canvasPadding: 0,
        presenterComposition: StudioPresenterCompositionSettings(
            mode: .presenterOverlay,
            placement: .manual,
            manualPosition: StudioNormalizedPoint(x: 1, y: 1),
            scale: 0.5
        )
    )
    let layout = StudioCanvasLayout(
        size: CGSize(width: 400, height: 220),
        settings: settings
    )
    let presenterRect = layout.presenterComposition.presenterRect

    #expect(presenterRect.maxX <= layout.contentRect.maxX)
    #expect(presenterRect.maxY <= layout.contentRect.maxY)
    #expect(presenterRect.minX >= layout.contentRect.minX)
    #expect(presenterRect.minY >= layout.contentRect.minY)
}

@Test
func studioCanvasLayoutPlacesPresenterOnEveryRequestedEdge() {
    let size = CGSize(width: 1_600, height: 900)

    func layout(for placement: StudioPresenterPlacement) -> StudioCanvasLayout {
        StudioCanvasLayout(
            size: size,
            settings: StudioLayoutSettings(
                canvasPadding: 0.04,
                presenterComposition: StudioPresenterCompositionSettings(
                    mode: .presenterOverlay,
                    placement: placement,
                    scale: 0.28
                )
            )
        )
    }

    let left = layout(for: .left)
    let right = layout(for: .right)
    let top = layout(for: .top)
    let bottom = layout(for: .bottom)

    #expect(left.presenterOverlayRect.midX < left.contentRect.midX)
    #expect(right.presenterOverlayRect.midX > right.contentRect.midX)
    #expect(top.presenterOverlayRect.midY > top.contentRect.midY)
    #expect(bottom.presenterOverlayRect.midY < bottom.contentRect.midY)
}

@Test
func framedPictureInPictureHonorsManualPresenterPositionAndScale() {
    let settings = StudioLayoutSettings(
        preset: .pictureInPicture,
        canvasPadding: 0.04,
        presenterComposition: StudioPresenterCompositionSettings(
            mode: .preserveLayout,
            placement: .manual,
            manualPosition: StudioNormalizedPoint(x: 0.25, y: 0.75),
            scale: 0.32
        )
    )
    let layout = StudioCanvasLayout(
        size: CGSize(width: 1_920, height: 1_080),
        settings: settings
    )
    let presenterRect = layout.presenterComposition.presenterRect

    #expect(abs(presenterRect.width - (layout.contentRect.width * 0.32)) < 0.001)
    #expect(presenterRect.midX < layout.contentRect.midX)
    #expect(presenterRect.midY > layout.contentRect.midY)
    #expect(presenterRect.minX >= layout.contentRect.minX)
    #expect(presenterRect.maxY <= layout.contentRect.maxY)
}

@Test
func splitLayoutRemainsFixedWhenManualPresenterPositionExists() {
    let settings = StudioLayoutSettings(
        preset: .screen70Webcam30,
        presenterComposition: StudioPresenterCompositionSettings(
            mode: .preserveLayout,
            placement: .manual,
            manualPosition: StudioNormalizedPoint(x: 0.1, y: 0.9),
            scale: 0.5
        )
    )
    let layout = StudioCanvasLayout(
        size: CGSize(width: 1_280, height: 720),
        settings: settings
    )

    #expect(layout.presenterComposition.screenRect == layout.splitScreenRect)
    #expect(layout.presenterComposition.presenterRect == layout.splitWebcamRect)
}

@Test
func studioCanvasLayoutNormalizesOutputPointsWithinContent() {
    let layout = StudioCanvasLayout(
        size: CGSize(width: 1_000, height: 600),
        settings: StudioLayoutSettings(canvasPadding: 0.1)
    )

    #expect(
        layout.normalizedContentPoint(forOutputPoint: layout.contentRect.center)
            == StudioNormalizedPoint(x: 0.5, y: 0.5)
    )
    #expect(
        layout.normalizedContentPoint(
            forOutputPoint: CGPoint(x: layout.contentRect.maxX + 200, y: layout.contentRect.minY - 200)
        ) == StudioNormalizedPoint(x: 1, y: 0)
    )
}

@Test
func presenterResizePreservesTheGestureAnchor() {
    let size = CGSize(width: 1_600, height: 900)
    let startSettings = StudioLayoutSettings(
        presenterComposition: StudioPresenterCompositionSettings(
            mode: .presenterOverlay,
            placement: .manual,
            manualPosition: StudioNormalizedPoint(x: 0.55, y: 0.45),
            scale: 0.25
        )
    )
    let startLayout = StudioCanvasLayout(size: size, settings: startSettings)
    let startRect = startLayout.presenterComposition.presenterRect
    let anchor = StudioNormalizedPoint(x: 0.2, y: 0.8)
    var resizedSettings = startSettings
    resizedSettings.presenterComposition.scale = 0.4
    let provisionalLayout = StudioCanvasLayout(size: size, settings: resizedSettings)
    let resizedSize = provisionalLayout.presenterComposition.presenterRect.size
    resizedSettings.presenterComposition.manualPosition = startLayout.manualPresenterPosition(
        resizingFrom: startRect,
        to: resizedSize,
        preservingUnitAnchor: anchor
    )
    let finalRect = StudioCanvasLayout(
        size: size,
        settings: resizedSettings
    ).presenterComposition.presenterRect
    let startAnchor = CGPoint(
        x: startRect.minX + (startRect.width * anchor.x),
        y: startRect.minY + (startRect.height * anchor.y)
    )
    let finalAnchor = CGPoint(
        x: finalRect.minX + (finalRect.width * anchor.x),
        y: finalRect.minY + (finalRect.height * anchor.y)
    )

    #expect(abs(finalAnchor.x - startAnchor.x) < 2)
    #expect(abs(finalAnchor.y - startAnchor.y) < 2)
}

@Test
func sourceViewportGeometrySharesAspectFillPanAndZoomMath() {
    let geometry = StudioSourceViewportGeometry(
        sourceSize: CGSize(width: 4, height: 3),
        targetSize: CGSize(width: 1_600, height: 900),
        viewport: StudioSourceViewportSettings(zoom: 1, panX: 0, panY: 1)
    )

    #expect(abs(geometry.scaledSourceSize.width - 1_600) < 0.001)
    #expect(abs(geometry.scaledSourceSize.height - 1_200) < 0.001)
    #expect(abs(geometry.contentOffset.width) < 0.001)
    #expect(abs(geometry.contentOffset.height - 150) < 0.001)

    let zoomedOut = StudioSourceViewportGeometry(
        sourceSize: CGSize(width: 4, height: 3),
        targetSize: CGSize(width: 1_600, height: 900),
        viewport: StudioSourceViewportSettings(zoom: 0.75, panX: 1, panY: 1)
    )

    #expect(abs(zoomedOut.scaledSourceSize.width - 1_200) < 0.001)
    #expect(abs(zoomedOut.scaledSourceSize.height - 900) < 0.001)
    #expect(zoomedOut.contentOffset == .zero)
}

@Test
func sourceViewportDragTracksCanvasTranslationAcrossAspectRatios() {
    let start = StudioSourceViewportSettings()
    let verticalGeometry = StudioSourceViewportGeometry(
        sourceSize: CGSize(width: 4, height: 3),
        targetSize: CGSize(width: 1_600, height: 900),
        viewport: start
    )
    let verticallyDragged = verticalGeometry.viewport(
        applyingCanvasTranslation: CGSize(width: 0, height: 75),
        to: start
    )
    let verticalResult = StudioSourceViewportGeometry(
        sourceSize: verticalGeometry.sourceSize,
        targetSize: verticalGeometry.targetSize,
        viewport: verticallyDragged
    )

    #expect(abs(verticalResult.contentOffset.height + 75) < 0.001)

    let horizontalGeometry = StudioSourceViewportGeometry(
        sourceSize: CGSize(width: 16, height: 9),
        targetSize: CGSize(width: 400, height: 300),
        viewport: start
    )
    let horizontallyDragged = horizontalGeometry.viewport(
        applyingCanvasTranslation: CGSize(width: 30, height: 0),
        to: start
    )
    let horizontalResult = StudioSourceViewportGeometry(
        sourceSize: horizontalGeometry.sourceSize,
        targetSize: horizontalGeometry.targetSize,
        viewport: horizontallyDragged
    )

    #expect(abs(horizontalResult.contentOffset.width - 30) < 0.001)
}

@Test
func sourceViewportZoomPreservesTheGestureAnchor() {
    let start = StudioSourceViewportSettings(zoom: 1, panX: 0.15, panY: -0.25)
    let geometry = StudioSourceViewportGeometry(
        sourceSize: CGSize(width: 4, height: 3),
        targetSize: CGSize(width: 1_600, height: 900),
        viewport: start
    )
    let anchor = CGPoint(x: 240, y: -180)
    let sourcePointBefore = CGPoint(
        x: (anchor.x - geometry.contentOffset.width) / geometry.scale,
        y: (anchor.y + geometry.contentOffset.height) / geometry.scale
    )
    let zoomedViewport = geometry.viewport(
        settingZoom: 1.35,
        preservingCanvasPoint: anchor,
        in: start
    )
    let zoomedGeometry = StudioSourceViewportGeometry(
        sourceSize: geometry.sourceSize,
        targetSize: geometry.targetSize,
        viewport: zoomedViewport
    )
    let sourcePointAfter = CGPoint(
        x: (anchor.x - zoomedGeometry.contentOffset.width) / zoomedGeometry.scale,
        y: (anchor.y + zoomedGeometry.contentOffset.height) / zoomedGeometry.scale
    )

    #expect(abs(sourcePointAfter.x - sourcePointBefore.x) < 0.005)
    #expect(abs(sourcePointAfter.y - sourcePointBefore.y) < 0.005)
}

@Test
func screenCaptureTargetRetainsSourceDimensions() throws {
    let target = ScreenCaptureTarget(
        id: "window-42",
        kind: .window,
        name: "Slides",
        detail: "Keynote",
        pixelWidth: 1_440,
        pixelHeight: 900
    )
    let encoded = try JSONEncoder().encode(target)
    let decoded = try JSONDecoder().decode(ScreenCaptureTarget.self, from: encoded)

    #expect(decoded == target)
    #expect(decoded.sourceSize == CGSize(width: 1_440, height: 900))
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
