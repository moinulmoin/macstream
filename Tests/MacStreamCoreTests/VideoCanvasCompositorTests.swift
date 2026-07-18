@preconcurrency import CoreVideo
import Foundation
@testable import MacStreamCore
import Testing

@Test
func videoCanvasCompositorAppliesCanvasBackgroundToScreenOnlyOutput() throws {
    let output = try makeSolidPixelBuffer(width: 160, height: 90, bgra: (0, 0, 0, 255))
    let screen = try makeSolidPixelBuffer(width: 160, height: 90, bgra: (0, 0, 255, 255))
    let settings = StudioLayoutSettings(
        preset: .screen70Webcam30,
        background: .color(StudioRGBAColor(red: 0, green: 0, blue: 1)),
        canvasPadding: 0.1,
        sourceGap: 0,
        sourceCornerRadius: 0
    )
    let compositor = VideoCanvasCompositor(
        outputWidth: 160,
        outputHeight: 90,
        cameraEnhancements: CameraEnhancementSettings(),
        layoutSettings: settings,
        sceneKind: .screenOnly
    )

    compositor.render(screenPixelBuffer: screen, cameraPixelBuffer: nil, to: output)

    #expect(pixel(in: output, x: 0, y: 0) == Pixel(b: 255, g: 0, r: 0, a: 255))
    #expect(pixel(in: output, x: 80, y: 45) == Pixel(b: 0, g: 0, r: 255, a: 255))
}

@Test
func videoCanvasCompositorRendersBothSplitSources() throws {
    let output = try makeSolidPixelBuffer(width: 160, height: 90, bgra: (0, 0, 0, 255))
    let screen = try makeSolidPixelBuffer(width: 160, height: 90, bgra: (0, 0, 255, 255))
    let camera = try makeSolidPixelBuffer(width: 160, height: 90, bgra: (0, 255, 0, 255))
    let settings = StudioLayoutSettings(
        preset: .screen70Webcam30,
        backgroundStyle: .black,
        canvasPadding: 0,
        sourceGap: 0,
        sourceCornerRadius: 0
    )
    let compositor = VideoCanvasCompositor(
        outputWidth: 160,
        outputHeight: 90,
        cameraEnhancements: CameraEnhancementSettings(mirrorsPreview: false),
        layoutSettings: settings,
        sceneKind: .screenAndFace
    )

    compositor.render(screenPixelBuffer: screen, cameraPixelBuffer: camera, to: output)

    #expect(pixel(in: output, x: 24, y: 45) == Pixel(b: 0, g: 0, r: 255, a: 255))
    #expect(pixel(in: output, x: 144, y: 45) == Pixel(b: 0, g: 255, r: 0, a: 255))
}

@Test
func videoCanvasCompositorRendersMirroredCameraSource() throws {
    let output = try makeSolidPixelBuffer(width: 160, height: 90, bgra: (0, 0, 0, 255))
    let screen = try makeSolidPixelBuffer(width: 160, height: 90, bgra: (0, 0, 255, 255))
    let camera = try makeSolidPixelBuffer(width: 160, height: 90, bgra: (0, 255, 0, 255))
    let settings = StudioLayoutSettings(
        preset: .screen70Webcam30,
        backgroundStyle: .black,
        canvasPadding: 0,
        sourceGap: 0,
        sourceCornerRadius: 0
    )
    let compositor = VideoCanvasCompositor(
        outputWidth: 160,
        outputHeight: 90,
        cameraEnhancements: CameraEnhancementSettings(mirrorsPreview: true),
        layoutSettings: settings,
        sceneKind: .screenAndFace
    )

    compositor.render(screenPixelBuffer: screen, cameraPixelBuffer: camera, to: output)

    #expect(pixel(in: output, x: 144, y: 45) == Pixel(b: 0, g: 255, r: 0, a: 255))
}

@Test
func videoCanvasCompositorRendersBiPlanarCameraSource() throws {
    let output = try makeSolidPixelBuffer(width: 160, height: 90, bgra: (0, 0, 0, 255))
    let screen = try makeSolidPixelBuffer(width: 160, height: 90, bgra: (0, 0, 255, 255))
    let camera = try makeBiPlanarPixelBuffer(width: 160, height: 90, luma: 200, chroma: 128)
    let settings = StudioLayoutSettings(
        preset: .screen70Webcam30,
        backgroundStyle: .black,
        canvasPadding: 0,
        sourceGap: 0,
        sourceCornerRadius: 0
    )
    let compositor = VideoCanvasCompositor(
        outputWidth: 160,
        outputHeight: 90,
        cameraEnhancements: CameraEnhancementSettings(mirrorsPreview: true),
        layoutSettings: settings,
        sceneKind: .screenAndFace
    )

    compositor.render(screenPixelBuffer: screen, cameraPixelBuffer: camera, to: output)

    let cameraPixel = pixel(in: output, x: 144, y: 45)
    #expect(cameraPixel.r > 150)
    #expect(cameraPixel.g > 150)
    #expect(cameraPixel.b > 150)
}

@Test
func videoCanvasCompositorUsesPresenterMatteWhenAvailable() throws {
    let output = try makeSolidPixelBuffer(width: 160, height: 90, bgra: (0, 0, 0, 255))
    let screen = try makeSolidPixelBuffer(width: 160, height: 90, bgra: (0, 0, 255, 255))
    let camera = try makeSolidPixelBuffer(width: 160, height: 90, bgra: (0, 255, 0, 255))
    let transparentMatte = try makeSolidMattePixelBuffer(width: 160, height: 90, value: 0)
    let settings = StudioLayoutSettings(
        canvasPadding: 0,
        sourceGap: 0,
        sourceCornerRadius: 0,
        presenterComposition: StudioPresenterCompositionSettings(
            mode: .presenterOverlay,
            placement: .manual,
            manualPosition: StudioNormalizedPoint(x: 0.5, y: 0.5),
            scale: 0.5
        )
    )
    let compositor = VideoCanvasCompositor(
        outputWidth: 160,
        outputHeight: 90,
        cameraEnhancements: CameraEnhancementSettings(mirrorsPreview: false),
        layoutSettings: settings,
        sceneKind: .screenAndFace
    )

    compositor.render(
        screenPixelBuffer: screen,
        cameraPixelBuffer: camera,
        cameraMattePixelBuffer: transparentMatte,
        to: output
    )

    #expect(pixel(in: output, x: 80, y: 45) == Pixel(b: 0, g: 0, r: 255, a: 255))
    #expect(pixel(in: output, x: 8, y: 8) == Pixel(b: 0, g: 0, r: 255, a: 255))
}

@Test
func videoCanvasCompositorRendersPresenterInsideOpaqueMatte() throws {
    let output = try makeSolidPixelBuffer(width: 160, height: 90, bgra: (0, 0, 0, 255))
    let screen = try makeSolidPixelBuffer(width: 160, height: 90, bgra: (0, 0, 255, 255))
    let camera = try makeSolidPixelBuffer(width: 160, height: 90, bgra: (0, 255, 0, 255))
    let opaqueMatte = try makeSolidMattePixelBuffer(width: 160, height: 90, value: 255)
    let settings = StudioLayoutSettings(
        canvasPadding: 0,
        sourceGap: 0,
        sourceCornerRadius: 0,
        presenterComposition: StudioPresenterCompositionSettings(
            mode: .presenterOverlay,
            placement: .manual,
            manualPosition: StudioNormalizedPoint(x: 0.5, y: 0.5),
            scale: 0.5
        )
    )
    let compositor = VideoCanvasCompositor(
        outputWidth: 160,
        outputHeight: 90,
        cameraEnhancements: CameraEnhancementSettings(mirrorsPreview: false),
        layoutSettings: settings,
        sceneKind: .screenAndFace
    )

    compositor.render(
        screenPixelBuffer: screen,
        cameraPixelBuffer: camera,
        cameraMattePixelBuffer: opaqueMatte,
        to: output
    )

    #expect(pixel(in: output, x: 80, y: 45) == Pixel(b: 0, g: 255, r: 0, a: 255))
    #expect(pixel(in: output, x: 8, y: 8) == Pixel(b: 0, g: 0, r: 255, a: 255))
}

@Test
func videoCanvasCompositorDoesNotExposeCameraBackgroundWithoutFreshPresenterMatte() throws {
    let output = try makeSolidPixelBuffer(width: 160, height: 90, bgra: (0, 0, 0, 255))
    let screen = try makeSolidPixelBuffer(width: 160, height: 90, bgra: (0, 0, 255, 255))
    let camera = try makeSolidPixelBuffer(width: 160, height: 90, bgra: (0, 255, 0, 255))
    let settings = StudioLayoutSettings(
        canvasPadding: 0,
        sourceGap: 0,
        sourceCornerRadius: 0,
        presenterComposition: StudioPresenterCompositionSettings(
            mode: .presenterOverlay,
            placement: .manual,
            manualPosition: StudioNormalizedPoint(x: 0.5, y: 0.5),
            scale: 0.5
        )
    )
    let compositor = VideoCanvasCompositor(
        outputWidth: 160,
        outputHeight: 90,
        cameraEnhancements: CameraEnhancementSettings(mirrorsPreview: false),
        layoutSettings: settings,
        sceneKind: .screenAndFace
    )

    compositor.render(screenPixelBuffer: screen, cameraPixelBuffer: camera, to: output)

    #expect(pixel(in: output, x: 80, y: 45) == Pixel(b: 0, g: 0, r: 255, a: 255))
    #expect(pixel(in: output, x: 8, y: 8) == Pixel(b: 0, g: 0, r: 255, a: 255))
}

private struct Pixel: Equatable {
    var b: UInt8
    var g: UInt8
    var r: UInt8
    var a: UInt8
}

private func makeSolidPixelBuffer(
    width: Int,
    height: Int,
    bgra: (UInt8, UInt8, UInt8, UInt8)
) throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    guard CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary,
        &pixelBuffer
    ) == kCVReturnSuccess,
          let pixelBuffer
    else {
        throw PixelBufferTestError.creationFailed
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
        throw PixelBufferTestError.missingBaseAddress
    }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    for y in 0..<height {
        let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
        for x in 0..<width {
            let offset = x * 4
            row[offset] = bgra.0
            row[offset + 1] = bgra.1
            row[offset + 2] = bgra.2
            row[offset + 3] = bgra.3
        }
    }
    return pixelBuffer
}

private func makeBiPlanarPixelBuffer(
    width: Int,
    height: Int,
    luma: UInt8,
    chroma: UInt8
) throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    guard CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary,
        &pixelBuffer
    ) == kCVReturnSuccess,
          let pixelBuffer
    else {
        throw PixelBufferTestError.creationFailed
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    guard let lumaBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
          let chromaBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)
    else {
        throw PixelBufferTestError.missingBaseAddress
    }

    for y in 0..<CVPixelBufferGetHeightOfPlane(pixelBuffer, 0) {
        memset(
            lumaBaseAddress.advanced(by: y * CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)),
            Int32(luma),
            CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        )
    }
    for y in 0..<CVPixelBufferGetHeightOfPlane(pixelBuffer, 1) {
        memset(
            chromaBaseAddress.advanced(by: y * CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)),
            Int32(chroma),
            CVPixelBufferGetWidthOfPlane(pixelBuffer, 1) * 2
        )
    }
    return pixelBuffer
}

private func makeSolidMattePixelBuffer(width: Int, height: Int, value: UInt8) throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    guard CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_OneComponent8,
        [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary,
        &pixelBuffer
    ) == kCVReturnSuccess,
          let pixelBuffer
    else {
        throw PixelBufferTestError.creationFailed
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
        throw PixelBufferTestError.missingBaseAddress
    }
    for y in 0..<height {
        memset(baseAddress.advanced(by: y * CVPixelBufferGetBytesPerRow(pixelBuffer)), Int32(value), width)
    }
    return pixelBuffer
}

private func pixel(in pixelBuffer: CVPixelBuffer, x: Int, y: Int) -> Pixel {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)!
        .advanced(by: y * bytesPerRow)
        .assumingMemoryBound(to: UInt8.self)
    let offset = x * 4
    return Pixel(
        b: baseAddress[offset],
        g: baseAddress[offset + 1],
        r: baseAddress[offset + 2],
        a: baseAddress[offset + 3]
    )
}

private enum PixelBufferTestError: Error {
    case creationFailed
    case missingBaseAddress
}
