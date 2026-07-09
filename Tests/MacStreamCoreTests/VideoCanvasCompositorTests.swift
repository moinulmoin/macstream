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
