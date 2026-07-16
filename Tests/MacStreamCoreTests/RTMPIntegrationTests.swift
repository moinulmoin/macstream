import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Testing
@testable import MacStreamCore

#if MAC_STREAM_HAS_HAISHINKIT
@Test
func haishinKitPublisherSendsSyntheticVideoToConfiguredRTMPIngest() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["MAC_STREAM_RUN_RTMP_INTEGRATION"] == "1" else {
        return
    }

    let connectionURL = try #require(environment["MAC_STREAM_RTMP_INTEGRATION_URL"])
    let streamName = try #require(environment["MAC_STREAM_RTMP_INTEGRATION_STREAM_NAME"])
    let durationSeconds = max(1, Int(environment["MAC_STREAM_RTMP_INTEGRATION_DURATION"] ?? "") ?? 5)
    let warmupSeconds = max(1, Int(environment["MAC_STREAM_RTMP_INTEGRATION_WARMUP_DURATION"] ?? "") ?? 5)
    let framesPerSecond = min(max(Int(environment["MAC_STREAM_RTMP_INTEGRATION_FPS"] ?? "") ?? 15, 10), 30)
    let expectedFrameCount = (warmupSeconds + durationSeconds) * framesPerSecond

    let publisher = HaishinKitRTMPPublisher(target: RTMPPublishTarget(
        connectionURL: connectionURL,
        streamName: streamName
    ))
    let configuration = MediaPipelineConfiguration(
        maxVideoWidth: 640,
        framesPerSecond: framesPerSecond,
        videoBitrate: 1_000_000,
        queueDepth: 3,
        sceneKind: .screenOnly,
        capturesSystemAudio: false,
        capturesMicrophone: false
    )

    do {
        try await publisher.configure(configuration: configuration)
        try await publisher.connect()

        let acceptedFrames: Int
        if let fixturePath = environment["MAC_STREAM_RTMP_INTEGRATION_FIXTURE_PATH"],
           !fixturePath.isEmpty {
            acceptedFrames = try await publishRTMPIntegrationFixture(
                at: URL(fileURLWithPath: fixturePath),
                publisher: publisher,
                framesPerSecond: framesPerSecond
            )
        } else {
            var rawAcceptedFrames = 0
            for frameIndex in 0..<expectedFrameCount {
                let sampleBuffer = try makeRTMPIntegrationVideoSample(
                    frameIndex: frameIndex,
                    framesPerSecond: framesPerSecond
                )
                if try await appendRTMPIntegrationSample(sampleBuffer, to: publisher) {
                    rawAcceptedFrames += 1
                }
                try await Task.sleep(for: .milliseconds(1_000 / framesPerSecond))
            }
            acceptedFrames = rawAcceptedFrames
        }

        var outboundBytes: Int64 = 0
        for _ in 0..<50 {
            outboundBytes = await publisher.currentByteCount()
            if outboundBytes > 0 {
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        await publisher.close()

        #expect(acceptedFrames >= Int(Double(expectedFrameCount) * 0.9))
        #expect(outboundBytes > 0)
        #expect(publisher.appendQueueSnapshot().pendingCount == 0)
    } catch {
        await publisher.close()
        throw error
    }
}

private func publishRTMPIntegrationFixture(
    at url: URL,
    publisher: HaishinKitRTMPPublisher,
    framesPerSecond: Int
) async throws -> Int {
    let asset = AVURLAsset(url: url)
    guard let track = try await asset.loadTracks(withMediaType: .video).first else {
        throw RTMPIntegrationError.fixtureMissingVideoTrack
    }

    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else {
        throw RTMPIntegrationError.fixtureReaderSetupFailed
    }
    reader.add(output)
    guard reader.startReading() else {
        throw RTMPIntegrationError.fixtureReaderSetupFailed
    }

    var acceptedFrames = 0
    while let sampleBuffer = output.copyNextSampleBuffer() {
        if try await appendRTMPIntegrationSample(sampleBuffer, to: publisher) {
            acceptedFrames += 1
        }
        try await Task.sleep(for: .milliseconds(1_000 / framesPerSecond))
    }
    guard reader.status == .completed else {
        throw RTMPIntegrationError.fixtureReaderFailed
    }
    return acceptedFrames
}

private func appendRTMPIntegrationSample(
    _ sampleBuffer: CMSampleBuffer,
    to publisher: HaishinKitRTMPPublisher
) async throws -> Bool {
    var accepted = publisher.append(sampleBuffer, track: 0)
    var retryCount = 0
    while !accepted, retryCount < 20 {
        try await Task.sleep(for: .milliseconds(5))
        accepted = publisher.append(sampleBuffer, track: 0)
        retryCount += 1
    }
    return accepted
}

private func makeRTMPIntegrationVideoSample(
    frameIndex: Int,
    framesPerSecond: Int
) throws -> CMSampleBuffer {
    let width = 640
    let height = 360
    let attributes: [CFString: Any] = [
        kCVPixelBufferIOSurfacePropertiesKey: [:]
    ]
    var pixelBuffer: CVPixelBuffer?
    let pixelStatus = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        attributes as CFDictionary,
        &pixelBuffer
    )
    guard pixelStatus == kCVReturnSuccess,
          let pixelBuffer
    else {
        throw RTMPIntegrationError.pixelBufferCreationFailed(pixelStatus)
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
        let pixelsPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer) / MemoryLayout<UInt32>.size
        let pixelCount = pixelsPerRow * height
        let colorPhase = UInt32(frameIndex % 255)
        let color = UInt32(0xFF00_0000)
            | (colorPhase << 16)
            | ((255 - colorPhase) << 8)
            | UInt32(96)
        let pixels = baseAddress.assumingMemoryBound(to: UInt32.self)
        for index in 0..<pixelCount {
            pixels[index] = color
        }
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

    var formatDescription: CMVideoFormatDescription?
    guard CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescriptionOut: &formatDescription
    ) == noErr,
          let formatDescription
    else {
        throw RTMPIntegrationError.formatDescriptionCreationFailed
    }

    let timescale = CMTimeScale(framesPerSecond * 100)
    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 100, timescale: timescale),
        presentationTimeStamp: CMTime(value: CMTimeValue(frameIndex * 100), timescale: timescale),
        decodeTimeStamp: .invalid
    )
    var sampleBuffer: CMSampleBuffer?
    guard CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescription: formatDescription,
        sampleTiming: &timing,
        sampleBufferOut: &sampleBuffer
    ) == noErr,
          let sampleBuffer
    else {
        throw RTMPIntegrationError.sampleBufferCreationFailed
    }
    return sampleBuffer
}

private enum RTMPIntegrationError: Error {
    case fixtureMissingVideoTrack
    case fixtureReaderSetupFailed
    case fixtureReaderFailed
    case pixelBufferCreationFailed(CVReturn)
    case formatDescriptionCreationFailed
    case sampleBufferCreationFailed
}
#endif
