@preconcurrency import CoreMedia
@preconcurrency import CoreVideo
import Foundation
@testable import MacStreamCore
import Testing

@Test
func mediaPreviewFrameSourceBoundsDeliveryRateWithoutBuffering() async throws {
    let source = MediaPreviewFrameSource()
    let collector = PreviewSampleCollector()
    let subscription = source.subscribe(maximumFramesPerSecond: 10) { sampleBuffer in
        collector.append(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }

    source.publish(try makePreviewSampleBuffer(seconds: 0))
    try? await Task.sleep(for: .milliseconds(10))
    source.publish(try makePreviewSampleBuffer(seconds: 0.05))
    source.publish(try makePreviewSampleBuffer(seconds: 0.10))
    try? await Task.sleep(for: .milliseconds(10))
    source.publish(try makePreviewSampleBuffer(seconds: 0.15))
    source.publish(try makePreviewSampleBuffer(seconds: 0.20))
    try? await Task.sleep(for: .milliseconds(10))

    #expect(collector.seconds == [0, 0.1, 0.2])
    source.unsubscribe(subscription)
}

@Test
func staleMediaPreviewFrameSubscriptionCannotClearReplacement() async throws {
    let source = MediaPreviewFrameSource()
    let firstCollector = PreviewSampleCollector()
    let secondCollector = PreviewSampleCollector()
    let first = source.subscribe(maximumFramesPerSecond: 30) { sampleBuffer in
        firstCollector.append(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }
    let second = source.subscribe(maximumFramesPerSecond: 30) { sampleBuffer in
        secondCollector.append(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }

    source.unsubscribe(first)
    source.publish(try makePreviewSampleBuffer(seconds: 1))
    try? await Task.sleep(for: .milliseconds(30))

    #expect(firstCollector.seconds.isEmpty)
    #expect(secondCollector.seconds == [1])
    source.unsubscribe(second)
}

@Test
@MainActor
func studioStoreUsesPipelineOutputPreviewOnlyDuringRealCapture() async {
    let pipeline = PreviewFrameMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)

    #expect(store.mediaPreviewFrameSource === pipeline.source)
    #expect(!store.shouldUseMediaOutputPreview)

    store.startRecording()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.recordingState == .recording)
    #expect(store.shouldUseMediaOutputPreview)

    store.stopRecording()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(store.recordingState == .stopped)
    #expect(!store.shouldUseMediaOutputPreview)
}

@Test
@MainActor
func studioStoreReleasesIdlePreviewWhileRecordingStarts() async {
    let pipeline = PreviewFrameMediaPipeline(recordingStartDelay: .milliseconds(60))
    let store = StudioStore(mediaPipeline: pipeline)

    store.startRecording()
    try? await Task.sleep(for: .milliseconds(10))

    #expect(store.recordingState == .starting)
    #expect(store.shouldUseMediaOutputPreview)

    try? await Task.sleep(for: .milliseconds(80))
    #expect(store.recordingState == .recording)
}

private final class PreviewFrameMediaPipeline: MediaPipeline, @unchecked Sendable {
    let source = MediaPreviewFrameSource()
    let recordingStartDelay: Duration?

    init(recordingStartDelay: Duration? = nil) {
        self.recordingStartDelay = recordingStartDelay
    }

    var mediaPreviewFrameSource: MediaPreviewFrameSource? { source }

    func startStream(destinations: [StreamDestination]) async throws {}
    func stopStream() async {}

    func startRecording() async throws -> URL {
        if let recordingStartDelay {
            try await Task.sleep(for: recordingStartDelay)
        }
        return URL(fileURLWithPath: "/tmp/macstream-preview-source.mov")
    }

    func stopRecording() async {}
}

private final class PreviewSampleCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var presentationTimes: [CMTime] = []

    var seconds: [Double] {
        lock.withLock {
            presentationTimes.map(CMTimeGetSeconds)
        }
    }

    func append(_ presentationTime: CMTime) {
        lock.withLock {
            presentationTimes.append(presentationTime)
        }
    }
}

private func makePreviewSampleBuffer(seconds: Double) throws -> CMSampleBuffer {
    var pixelBuffer: CVPixelBuffer?
    let pixelStatus = CVPixelBufferCreate(
        kCFAllocatorDefault,
        2,
        2,
        kCVPixelFormatType_32BGRA,
        nil,
        &pixelBuffer
    )
    guard pixelStatus == kCVReturnSuccess, let pixelBuffer else {
        throw PreviewSampleBufferError.pixelBufferCreationFailed
    }

    var formatDescription: CMVideoFormatDescription?
    guard CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescriptionOut: &formatDescription
    ) == noErr,
          let formatDescription
    else {
        throw PreviewSampleBufferError.formatDescriptionCreationFailed
    }

    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 30),
        presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 600),
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
        throw PreviewSampleBufferError.sampleBufferCreationFailed
    }
    return sampleBuffer
}

private enum PreviewSampleBufferError: Error {
    case pixelBufferCreationFailed
    case formatDescriptionCreationFailed
    case sampleBufferCreationFailed
}
