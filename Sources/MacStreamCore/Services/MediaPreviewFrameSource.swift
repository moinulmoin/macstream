@preconcurrency import CoreMedia
import Foundation

public struct MediaPreviewFrameSubscription: Equatable, Sendable {
    fileprivate let id: UUID
}

public final class MediaPreviewFrameSource: @unchecked Sendable {
    public typealias Consumer = @Sendable (CMSampleBuffer) -> Void

    private struct Subscription {
        var id: UUID
        var maximumFramesPerSecond: Int
        var consumer: Consumer
    }

    private let lock = NSLock()
    private let deliveryQueue = DispatchQueue(label: "com.macstream.preview-output", qos: .userInteractive)
    private var subscription: Subscription?
    private var lastPresentationTime = CMTime.invalid
    private var pendingSampleBuffer: CMSampleBuffer?
    private var isDeliveryScheduled = false

    public init() {}

    @discardableResult
    public func subscribe(
        maximumFramesPerSecond: Int,
        consumer: @escaping Consumer
    ) -> MediaPreviewFrameSubscription {
        let token = MediaPreviewFrameSubscription(id: UUID())
        lock.withLock {
            subscription = Subscription(
                id: token.id,
                maximumFramesPerSecond: Self.normalizedFrameRate(maximumFramesPerSecond),
                consumer: consumer
            )
            lastPresentationTime = .invalid
            pendingSampleBuffer = nil
        }
        return token
    }

    public func update(
        _ token: MediaPreviewFrameSubscription,
        maximumFramesPerSecond: Int
    ) {
        lock.withLock {
            guard subscription?.id == token.id else { return }
            subscription?.maximumFramesPerSecond = Self.normalizedFrameRate(maximumFramesPerSecond)
            lastPresentationTime = .invalid
        }
    }

    public func unsubscribe(_ token: MediaPreviewFrameSubscription) {
        lock.withLock {
            guard subscription?.id == token.id else { return }
            subscription = nil
            lastPresentationTime = .invalid
            pendingSampleBuffer = nil
        }
    }

    func publish(_ sampleBuffer: CMSampleBuffer) {
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        enqueueIfDue(sampleBuffer, at: presentationTime)
    }

    func publishIfDue(
        at presentationTime: CMTime,
        makeSampleBuffer: () -> CMSampleBuffer?
    ) {
        guard isDeliveryDue(at: presentationTime),
              let sampleBuffer = makeSampleBuffer()
        else { return }
        enqueueIfDue(sampleBuffer, at: presentationTime)
    }

    private func isDeliveryDue(at presentationTime: CMTime) -> Bool {
        lock.withLock {
            guard let subscription else { return false }
            return isDeliveryDueLocked(
                at: presentationTime,
                maximumFramesPerSecond: subscription.maximumFramesPerSecond
            )
        }
    }

    private func enqueueIfDue(_ sampleBuffer: CMSampleBuffer, at presentationTime: CMTime) {
        let shouldSchedule = lock.withLock {
            guard let subscription,
                  isDeliveryDueLocked(
                    at: presentationTime,
                    maximumFramesPerSecond: subscription.maximumFramesPerSecond
                  )
            else {
                return false
            }

            lastPresentationTime = presentationTime
            pendingSampleBuffer = sampleBuffer
            guard !isDeliveryScheduled else { return false }
            isDeliveryScheduled = true
            return true
        }
        guard shouldSchedule else { return }
        deliveryQueue.async { [weak self] in
            self?.drainPendingFrames()
        }
    }

    private func drainPendingFrames() {
        while true {
            let delivery: (CMSampleBuffer, Consumer)? = lock.withLock {
                guard let sampleBuffer = pendingSampleBuffer,
                      let consumer = subscription?.consumer
                else {
                    isDeliveryScheduled = false
                    return nil
                }
                pendingSampleBuffer = nil
                return (sampleBuffer, consumer)
            }
            guard let delivery else { return }
            delivery.1(delivery.0)
        }
    }

    private func isDeliveryDueLocked(
        at presentationTime: CMTime,
        maximumFramesPerSecond: Int
    ) -> Bool {
        guard presentationTime.isValid, presentationTime.isNumeric else { return true }
        guard lastPresentationTime.isValid, lastPresentationTime.isNumeric else { return true }

        let elapsed = CMTimeGetSeconds(presentationTime - lastPresentationTime)
        let minimumInterval = 1 / Double(maximumFramesPerSecond)
        return elapsed < 0 || elapsed >= minimumInterval
    }

    private static func normalizedFrameRate(_ frameRate: Int) -> Int {
        min(max(frameRate, 1), 30)
    }
}
