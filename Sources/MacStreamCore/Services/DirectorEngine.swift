import Foundation

public struct DirectorEngine: Sendable {
    public private(set) var profile: DirectorProfile
    private var lastAcceptedSwitchAt: Date?
    private var lastRecommendedTarget: SceneKind?
    private var heldCue: HeldCue?

    public init(profile: DirectorProfile = .balanced) {
        self.profile = profile
    }

    public mutating func apply(profile: DirectorProfile) {
        self.profile = profile
        lastRecommendedTarget = nil
        heldCue = nil
    }

    public mutating func evaluate(
        snapshot: SignalSnapshot,
        currentScene: SceneKind,
        mode: DirectorMode
    ) -> DirectorRecommendation? {
        guard mode != .paused else { return nil }

        if let recommendation = safetyRecommendation(from: snapshot, currentScene: currentScene) {
            lastRecommendedTarget = recommendation.target
            return recommendation
        }

        guard canRecommend(at: snapshot.timestamp) else {
            return nil
        }

        let desired = desiredScene(from: snapshot)
        if isHeld(desired, at: snapshot.timestamp) {
            lastRecommendedTarget = nil
            return nil
        }

        guard desired.target != currentScene else {
            lastRecommendedTarget = nil
            return nil
        }

        if lastRecommendedTarget == desired.target {
            return desired
        }

        lastRecommendedTarget = desired.target
        return desired
    }

    public mutating func markSwitchAccepted(at date: Date = Date()) {
        lastAcceptedSwitchAt = date
        lastRecommendedTarget = nil
        heldCue = nil
    }

    public mutating func markCueHeld(
        _ recommendation: DirectorRecommendation,
        at date: Date = Date(),
        duration: TimeInterval? = nil
    ) {
        let holdDuration = max(1, duration ?? profile.minimumSwitchInterval)
        heldCue = HeldCue(
            target: recommendation.target,
            until: date.addingTimeInterval(holdDuration)
        )
        lastRecommendedTarget = nil
    }

    private func canRecommend(at date: Date) -> Bool {
        guard let lastAcceptedSwitchAt else { return true }
        return date.timeIntervalSince(lastAcceptedSwitchAt) >= profile.minimumSwitchInterval
    }

    private mutating func isHeld(_ recommendation: DirectorRecommendation, at date: Date) -> Bool {
        guard let heldCue else { return false }
        guard date < heldCue.until else {
            self.heldCue = nil
            return false
        }

        return heldCue.target == recommendation.target
    }

    private func safetyRecommendation(
        from snapshot: SignalSnapshot,
        currentScene: SceneKind
    ) -> DirectorRecommendation? {
        if snapshot.isMicMuted && snapshot.speechLevel > 0.35 {
            return DirectorRecommendation(
                target: currentScene,
                confidence: 0.96,
                reason: "Mic looks muted while speech is detected.",
                urgency: .immediate,
                delaySeconds: 0
            )
        }

        if snapshot.isScreenFrozen && currentScene != .face {
            return DirectorRecommendation(
                target: .face,
                confidence: 0.88,
                reason: "Screen capture appears frozen, so Face is safer.",
                urgency: .immediate,
                delaySeconds: 0
            )
        }

        return nil
    }

    private func desiredScene(from snapshot: SignalSnapshot) -> DirectorRecommendation {
        if snapshot.idleSeconds > profile.idleToBRBSeconds
            && !snapshot.isSpeaking
            && snapshot.screenMotion < profile.quietScreenMotionThreshold {
            return DirectorRecommendation(
                target: .brb,
                confidence: 0.84,
                reason: "You have been quiet and idle for a while.",
                urgency: .soon,
                delaySeconds: 3
            )
        }

        if snapshot.isSpeaking
            && profile.prefersFaceWhenSpeaking
            && snapshot.screenMotion < profile.quietScreenMotionThreshold {
            return DirectorRecommendation(
                target: .face,
                confidence: 0.78,
                reason: "You are talking and the screen is quiet.",
                urgency: .soon,
                delaySeconds: 2
            )
        }

        if snapshot.isSpeaking {
            return DirectorRecommendation(
                target: .screenAndFace,
                confidence: 0.82,
                reason: "You are talking while \(snapshot.activeApplication) is active.",
                urgency: .soon,
                delaySeconds: 2
            )
        }

        if snapshot.screenMotion > profile.activeScreenMotionThreshold {
            return DirectorRecommendation(
                target: .screenOnly,
                confidence: 0.8,
                reason: "Screen activity is carrying the moment.",
                urgency: .soon,
                delaySeconds: 2
            )
        }

        if !snapshot.hasFace {
            return DirectorRecommendation(
                target: .screenOnly,
                confidence: 0.72,
                reason: "No face is visible, so keep attention on the screen.",
                urgency: .calm,
                delaySeconds: 3
            )
        }

        return DirectorRecommendation(
            target: profile.defaultScene,
            confidence: 0.64,
            reason: "Balanced camera and screen view is the safest default.",
            urgency: .calm,
            delaySeconds: 3
        )
    }
}

private struct HeldCue: Sendable {
    var target: SceneKind
    var until: Date
}
