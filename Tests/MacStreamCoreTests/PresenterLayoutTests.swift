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
