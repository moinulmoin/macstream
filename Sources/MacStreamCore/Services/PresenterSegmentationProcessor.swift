@preconcurrency import CoreMedia
@preconcurrency import CoreVideo
import Foundation
@preconcurrency import Vision

public struct PresenterSegmentationFrame: @unchecked Sendable {
    public let pixelBuffer: CVPixelBuffer
    public let presentationTime: CMTime

    public init(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        self.pixelBuffer = pixelBuffer
        self.presentationTime = presentationTime
    }
}

public struct PresenterSegmentationMatte: @unchecked Sendable {
    public let pixelBuffer: CVPixelBuffer
    public let presentationTime: CMTime
    public let processedAtUptimeNanoseconds: UInt64

    public init(
        pixelBuffer: CVPixelBuffer,
        presentationTime: CMTime,
        processedAtUptimeNanoseconds: UInt64
    ) {
        self.pixelBuffer = pixelBuffer
        self.presentationTime = presentationTime
        self.processedAtUptimeNanoseconds = processedAtUptimeNanoseconds
    }
}

public protocol PresenterSegmentationClient: Sendable {
    func makePersonSegmentationMatte(for frame: PresenterSegmentationFrame) throws -> CVPixelBuffer?
}

public final class VisionPresenterSegmentationClient: PresenterSegmentationClient, @unchecked Sendable {
    private let request: VNGeneratePersonSegmentationRequest
    private let sequenceHandler = VNSequenceRequestHandler()

    public init() {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .fast
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        self.request = request
    }

    public func makePersonSegmentationMatte(for frame: PresenterSegmentationFrame) throws -> CVPixelBuffer? {
        try sequenceHandler.perform([request], on: frame.pixelBuffer)
        return request.results?.first?.pixelBuffer
    }
}

public final class PresenterSegmentationProcessor: @unchecked Sendable {
    public struct Clock: Sendable {
        fileprivate let nowUptimeNanoseconds: @Sendable () -> UInt64

        public init(nowUptimeNanoseconds: @escaping @Sendable () -> UInt64) {
            self.nowUptimeNanoseconds = nowUptimeNanoseconds
        }

        public static let dispatchUptime = Clock {
            DispatchTime.now().uptimeNanoseconds
        }
    }

    private struct PendingFrame {
        var frame: PresenterSegmentationFrame
        var generation: UInt64
    }

    private let client: any PresenterSegmentationClient
    private let clock: Clock
    private let lock = NSLock()
    private let processingQueue: DispatchQueue
    private let minimumFrameIntervalNanoseconds: UInt64

    private var pendingFrame: PendingFrame?
    private var isProcessing = false
    private var generation: UInt64 = 0
    private var lastAcceptedAtUptimeNanoseconds: UInt64?
    private var latestMatteStorage: PresenterSegmentationMatte?

    public init(
        client: any PresenterSegmentationClient = VisionPresenterSegmentationClient(),
        maximumFramesPerSecond: Int = 12,
        clock: Clock = .dispatchUptime
    ) {
        self.client = client
        self.clock = clock
        self.processingQueue = DispatchQueue(label: "com.macstream.presenter-segmentation", qos: .userInitiated)
        self.minimumFrameIntervalNanoseconds = Self.minimumFrameIntervalNanoseconds(
            maximumFramesPerSecond: maximumFramesPerSecond
        )
    }

    public func submit(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        submit(
            pixelBuffer,
            presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        )
    }

    public func submit(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        let now = clock.nowUptimeNanoseconds()
        let shouldSchedule = lock.withLock {
            guard shouldAcceptFrameLocked(at: now) else { return false }
            lastAcceptedAtUptimeNanoseconds = now
            pendingFrame = PendingFrame(
                frame: PresenterSegmentationFrame(
                    pixelBuffer: pixelBuffer,
                    presentationTime: presentationTime
                ),
                generation: generation
            )

            guard !isProcessing else { return false }
            isProcessing = true
            return true
        }

        guard shouldSchedule else { return }
        processingQueue.async { [weak self] in
            self?.processPendingFrames()
        }
    }

    public func latestMatte(
        maximumAge: Duration = .milliseconds(250),
        matching presentationTime: CMTime? = nil,
        maximumPresentationTimeDelta: Duration = .milliseconds(300)
    ) -> PresenterSegmentationMatte? {
        let now = clock.nowUptimeNanoseconds()
        let maximumAgeNanoseconds = Self.nanoseconds(for: maximumAge)
        let maximumPresentationTimeDeltaSeconds = Double(Self.nanoseconds(for: maximumPresentationTimeDelta)) / 1_000_000_000
        return lock.withLock {
            guard let matte = latestMatteStorage,
                  now >= matte.processedAtUptimeNanoseconds,
                  now - matte.processedAtUptimeNanoseconds <= maximumAgeNanoseconds
            else {
                return nil
            }
            if let presentationTime {
                guard presentationTime.isNumeric,
                      matte.presentationTime.isNumeric
                else {
                    return nil
                }
                let delta = abs(CMTimeGetSeconds(presentationTime) - CMTimeGetSeconds(matte.presentationTime))
                guard delta.isFinite,
                      delta <= maximumPresentationTimeDeltaSeconds
                else {
                    return nil
                }
            }
            return matte
        }
    }

    public func reset() {
        lock.withLock {
            generation &+= 1
            pendingFrame = nil
            latestMatteStorage = nil
            lastAcceptedAtUptimeNanoseconds = nil
        }
    }

    private func processPendingFrames() {
        while true {
            guard let pending = lock.withLock({ nextPendingFrameLocked() }) else { return }

            let matte = Result {
                try client.makePersonSegmentationMatte(for: pending.frame)
            }.flatMap { pixelBuffer -> Result<PresenterSegmentationMatte?, Error> in
                guard let pixelBuffer else { return .success(nil) }
                return .success(
                    PresenterSegmentationMatte(
                        pixelBuffer: pixelBuffer,
                        presentationTime: pending.frame.presentationTime,
                        processedAtUptimeNanoseconds: clock.nowUptimeNanoseconds()
                    )
                )
            }

            lock.withLock {
                guard pending.generation == generation else { return }
                latestMatteStorage = try? matte.get()
            }
        }
    }

    private func nextPendingFrameLocked() -> PendingFrame? {
        guard let pendingFrame else {
            isProcessing = false
            return nil
        }
        self.pendingFrame = nil
        return pendingFrame
    }

    private func shouldAcceptFrameLocked(at now: UInt64) -> Bool {
        guard let lastAcceptedAtUptimeNanoseconds else { return true }
        guard now >= lastAcceptedAtUptimeNanoseconds else { return true }
        return now - lastAcceptedAtUptimeNanoseconds >= minimumFrameIntervalNanoseconds
    }

    private static func minimumFrameIntervalNanoseconds(maximumFramesPerSecond: Int) -> UInt64 {
        let frameRate = UInt64(min(max(maximumFramesPerSecond, 1), 60))
        return 1_000_000_000 / frameRate
    }

    private static func nanoseconds(for duration: Duration) -> UInt64 {
        let components = duration.components
        guard components.seconds > 0 || components.attoseconds > 0 else { return 0 }

        let secondNanoseconds: UInt64
        if components.seconds > Int64(UInt64.max / 1_000_000_000) {
            secondNanoseconds = UInt64.max
        } else {
            secondNanoseconds = UInt64(components.seconds) * 1_000_000_000
        }

        let attosecondNanoseconds = UInt64(max(components.attoseconds, 0)) / 1_000_000_000
        let (sum, overflow) = secondNanoseconds.addingReportingOverflow(attosecondNanoseconds)
        return overflow ? UInt64.max : sum
    }
}
