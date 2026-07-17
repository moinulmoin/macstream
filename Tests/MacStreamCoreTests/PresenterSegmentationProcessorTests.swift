@preconcurrency import CoreMedia
@preconcurrency import CoreVideo
import Foundation
@testable import MacStreamCore
import Testing

@Test
func presenterSegmentationSubmitDoesNotSynchronouslyRunClient() throws {
    let clock = TestSegmentationClock()
    let client = FakePresenterSegmentationClient()
    let release = DispatchSemaphore(value: 0)
    let matte = try makePixelBuffer(width: 2, height: 2, pixelFormat: kCVPixelFormatType_OneComponent8)
    client.enqueue(.blocked(release: release, matte: matte))
    let processor = PresenterSegmentationProcessor(client: client, clock: clock.processorClock)

    processor.submit(
        try makePixelBuffer(width: 2, height: 2),
        presentationTime: CMTime(seconds: 1, preferredTimescale: 600)
    )

    #expect(client.waitForStartedCallCount(1))
    #expect(processor.latestMatte() == nil)

    clock.advance(byNanoseconds: 1)
    release.signal()

    #expect(client.waitForCompletedCallCount(1))
    #expect(processor.latestMatte()?.presentationTime.seconds == 1)
}

@Test
func presenterSegmentationCoalescesPendingFramesBehindInFlightRequest() throws {
    let clock = TestSegmentationClock()
    let client = FakePresenterSegmentationClient()
    let release = DispatchSemaphore(value: 0)
    let firstMatte = try makePixelBuffer(width: 2, height: 2, pixelFormat: kCVPixelFormatType_OneComponent8)
    let finalMatte = try makePixelBuffer(width: 2, height: 2, pixelFormat: kCVPixelFormatType_OneComponent8)
    client.enqueue(.blocked(release: release, matte: firstMatte))
    client.enqueue(.matte(finalMatte))
    let processor = PresenterSegmentationProcessor(client: client, clock: clock.processorClock)

    processor.submit(
        try makePixelBuffer(width: 2, height: 2),
        presentationTime: CMTime(seconds: 0, preferredTimescale: 600)
    )
    #expect(client.waitForStartedCallCount(1))

    clock.advance(byNanoseconds: 100_000_000)
    processor.submit(
        try makePixelBuffer(width: 2, height: 2),
        presentationTime: CMTime(seconds: 0.1, preferredTimescale: 600)
    )

    clock.advance(byNanoseconds: 100_000_000)
    processor.submit(
        try makePixelBuffer(width: 2, height: 2),
        presentationTime: CMTime(seconds: 0.2, preferredTimescale: 600)
    )

    release.signal()

    #expect(client.waitForCompletedCallCount(2))
    #expect(client.presentationSeconds == [0, 0.2])
    #expect(processor.latestMatte()?.presentationTime.seconds == 0.2)
}

@Test
func presenterSegmentationDropsFramesAboveRateCap() throws {
    let clock = TestSegmentationClock()
    let client = FakePresenterSegmentationClient()
    client.enqueue(.matte(try makePixelBuffer(width: 2, height: 2, pixelFormat: kCVPixelFormatType_OneComponent8)))
    let processor = PresenterSegmentationProcessor(client: client, maximumFramesPerSecond: 12, clock: clock.processorClock)

    processor.submit(
        try makePixelBuffer(width: 2, height: 2),
        presentationTime: CMTime(seconds: 0, preferredTimescale: 600)
    )
    clock.advance(byNanoseconds: 10_000_000)
    processor.submit(
        try makePixelBuffer(width: 2, height: 2),
        presentationTime: CMTime(seconds: 0.01, preferredTimescale: 600)
    )

    #expect(client.waitForCompletedCallCount(1))
    #expect(!client.waitForStartedCallCount(2, timeout: .now() + .milliseconds(50)))
    #expect(client.presentationSeconds == [0])
}

@Test
func presenterSegmentationRejectsStaleLatestMatte() throws {
    let clock = TestSegmentationClock()
    let client = FakePresenterSegmentationClient()
    client.enqueue(.matte(try makePixelBuffer(width: 2, height: 2, pixelFormat: kCVPixelFormatType_OneComponent8)))
    let processor = PresenterSegmentationProcessor(client: client, clock: clock.processorClock)

    processor.submit(
        try makePixelBuffer(width: 2, height: 2),
        presentationTime: CMTime(seconds: 2, preferredTimescale: 600)
    )

    #expect(client.waitForCompletedCallCount(1))
    #expect(processor.latestMatte(maximumAge: .milliseconds(250)) != nil)

    clock.advance(byNanoseconds: 251_000_000)

    #expect(processor.latestMatte(maximumAge: .milliseconds(250)) == nil)
}

@Test
func presenterSegmentationRejectsFreshMatteForDistantCameraFrame() throws {
    let clock = TestSegmentationClock()
    let client = FakePresenterSegmentationClient()
    client.enqueue(.matte(try makePixelBuffer(width: 2, height: 2, pixelFormat: kCVPixelFormatType_OneComponent8)))
    let processor = PresenterSegmentationProcessor(client: client, clock: clock.processorClock)

    processor.submit(
        try makePixelBuffer(width: 2, height: 2),
        presentationTime: CMTime(seconds: 4, preferredTimescale: 600)
    )

    #expect(client.waitForCompletedCallCount(1))
    #expect(processor.latestMatte(
        matching: CMTime(seconds: 4.25, preferredTimescale: 600),
        maximumPresentationTimeDelta: .milliseconds(300)
    ) != nil)
    #expect(processor.latestMatte(
        matching: CMTime(seconds: 4.31, preferredTimescale: 600),
        maximumPresentationTimeDelta: .milliseconds(300)
    ) == nil)
}

@Test
func presenterSegmentationTreatsClientFailureAsNoMatte() throws {
    let clock = TestSegmentationClock()
    let client = FakePresenterSegmentationClient()
    client.enqueue(.matte(try makePixelBuffer(width: 2, height: 2, pixelFormat: kCVPixelFormatType_OneComponent8)))
    client.enqueue(.failure)
    let processor = PresenterSegmentationProcessor(client: client, clock: clock.processorClock)

    processor.submit(
        try makePixelBuffer(width: 2, height: 2),
        presentationTime: CMTime(seconds: 1, preferredTimescale: 600)
    )
    #expect(client.waitForCompletedCallCount(1))
    #expect(processor.latestMatte() != nil)

    clock.advance(byNanoseconds: 100_000_000)
    processor.submit(
        try makePixelBuffer(width: 2, height: 2),
        presentationTime: CMTime(seconds: 1.1, preferredTimescale: 600)
    )

    #expect(client.waitForCompletedCallCount(2))
    #expect(processor.latestMatte() == nil)
}

@Test
func presenterSegmentationResetClearsStateAndIgnoresInFlightResult() throws {
    let clock = TestSegmentationClock()
    let client = FakePresenterSegmentationClient()
    let release = DispatchSemaphore(value: 0)
    client.enqueue(.blocked(
        release: release,
        matte: try makePixelBuffer(width: 2, height: 2, pixelFormat: kCVPixelFormatType_OneComponent8)
    ))
    client.enqueue(.matte(try makePixelBuffer(width: 2, height: 2, pixelFormat: kCVPixelFormatType_OneComponent8)))
    let processor = PresenterSegmentationProcessor(client: client, clock: clock.processorClock)

    processor.submit(
        try makePixelBuffer(width: 2, height: 2),
        presentationTime: CMTime(seconds: 3, preferredTimescale: 600)
    )
    #expect(client.waitForStartedCallCount(1))

    processor.reset()
    release.signal()

    #expect(client.waitForCompletedCallCount(1))
    #expect(processor.latestMatte() == nil)

    processor.submit(
        try makePixelBuffer(width: 2, height: 2),
        presentationTime: CMTime(seconds: 4, preferredTimescale: 600)
    )

    #expect(client.waitForCompletedCallCount(2))
    #expect(processor.latestMatte()?.presentationTime.seconds == 4)
}

private final class FakePresenterSegmentationClient: PresenterSegmentationClient, @unchecked Sendable {
    enum Response {
        case matte(CVPixelBuffer?)
        case blocked(release: DispatchSemaphore, matte: CVPixelBuffer?)
        case failure
    }

    private let lock = NSLock()
    private let startedSemaphore = DispatchSemaphore(value: 0)
    private let completedSemaphore = DispatchSemaphore(value: 0)
    private var responses: [Response] = []
    private var startedCalls = 0
    private var completedCalls = 0
    private var presentationTimes: [CMTime] = []

    var presentationSeconds: [Double] {
        lock.withLock {
            presentationTimes.map(CMTimeGetSeconds)
        }
    }

    func enqueue(_ response: Response) {
        lock.withLock {
            responses.append(response)
        }
    }

    func makePersonSegmentationMatte(for frame: PresenterSegmentationFrame) throws -> CVPixelBuffer? {
        let response = lock.withLock {
            startedCalls += 1
            presentationTimes.append(frame.presentationTime)
            return responses.isEmpty ? .matte(nil) : responses.removeFirst()
        }
        startedSemaphore.signal()
        defer {
            lock.withLock {
                completedCalls += 1
            }
            completedSemaphore.signal()
        }

        switch response {
        case .matte(let matte):
            return matte
        case .blocked(let release, let matte):
            release.wait()
            return matte
        case .failure:
            throw FakeSegmentationError.failed
        }
    }

    func waitForStartedCallCount(
        _ count: Int,
        timeout: DispatchTime = .now() + .seconds(1)
    ) -> Bool {
        waitForCount(count, timeout: timeout, semaphore: startedSemaphore) { startedCalls }
    }

    func waitForCompletedCallCount(
        _ count: Int,
        timeout: DispatchTime = .now() + .seconds(1)
    ) -> Bool {
        waitForCount(count, timeout: timeout, semaphore: completedSemaphore) { completedCalls }
    }

    private func waitForCount(
        _ count: Int,
        timeout: DispatchTime,
        semaphore: DispatchSemaphore,
        read: () -> Int
    ) -> Bool {
        while lock.withLock(read) < count {
            if semaphore.wait(timeout: timeout) == .timedOut {
                return lock.withLock(read) >= count
            }
        }
        return true
    }
}

private final class TestSegmentationClock: @unchecked Sendable {
    private let lock = NSLock()
    private var now: UInt64 = 0

    var processorClock: PresenterSegmentationProcessor.Clock {
        PresenterSegmentationProcessor.Clock { [weak self] in
            self?.uptimeNanoseconds ?? 0
        }
    }

    func advance(byNanoseconds nanoseconds: UInt64) {
        lock.withLock {
            now += nanoseconds
        }
    }

    private var uptimeNanoseconds: UInt64 {
        lock.withLock { now }
    }
}

private enum FakeSegmentationError: Error {
    case failed
}

private func makePixelBuffer(
    width: Int,
    height: Int,
    pixelFormat: OSType = kCVPixelFormatType_32BGRA
) throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        pixelFormat,
        nil,
        &pixelBuffer
    )
    guard status == kCVReturnSuccess, let pixelBuffer else {
        throw PixelBufferCreationError.failed
    }
    return pixelBuffer
}

private enum PixelBufferCreationError: Error {
    case failed
}
