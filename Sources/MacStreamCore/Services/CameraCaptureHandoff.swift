import Foundation

public final class CameraCaptureHandoff: @unchecked Sendable {
    public static let shared = CameraCaptureHandoff()

    private let lock = NSLock()
    private var idlePreviewOwners = Set<UUID>()
    private var lastIdlePreviewRelease: ContinuousClock.Instant?

    public init() {}

    public func claimIdlePreview(ownerID: UUID) {
        _ = lock.withLock {
            idlePreviewOwners.insert(ownerID)
        }
    }

    public func releaseIdlePreview(ownerID: UUID) {
        lock.withLock {
            guard idlePreviewOwners.remove(ownerID) != nil else { return }
            if idlePreviewOwners.isEmpty {
                lastIdlePreviewRelease = ContinuousClock().now
            }
        }
    }

    public func waitForIdlePreviewRelease(
        timeout: Duration = .seconds(3),
        pollInterval: Duration = .milliseconds(10),
        settleDelay: Duration = .milliseconds(500)
    ) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while true {
            try Task.checkCancellation()
            let state = idlePreviewState
            if state.hasOwner {
                guard clock.now < deadline else { return false }
                try await Task.sleep(for: pollInterval)
                continue
            }

            if let lastRelease = state.lastRelease {
                let settledAt = lastRelease.advanced(by: settleDelay)
                if clock.now < settledAt {
                    try await Task.sleep(until: settledAt, clock: clock)
                }
            }
            return true
        }
    }

    private var idlePreviewState: (hasOwner: Bool, lastRelease: ContinuousClock.Instant?) {
        lock.withLock {
            (!idlePreviewOwners.isEmpty, lastIdlePreviewRelease)
        }
    }
}
