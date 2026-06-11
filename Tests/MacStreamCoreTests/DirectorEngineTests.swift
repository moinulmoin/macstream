import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import Network
import Testing
@testable import MacStreamCore

@Test
func speakingOverQuietScreenCuesFace() {
    var engine = DirectorEngine()
    let snapshot = SignalSnapshot(
        isSpeaking: true,
        speechLevel: 0.72,
        screenMotion: 0.08,
        hasFace: true,
        activeApplication: "Notes"
    )

    let recommendation = engine.evaluate(snapshot: snapshot, currentScene: .screenAndFace, mode: .suggest)

    #expect(recommendation?.target == .face)
}

@Test
func activeScreenWithoutSpeechCuesScreenOnly() {
    var engine = DirectorEngine()
    let snapshot = SignalSnapshot(
        isSpeaking: false,
        speechLevel: 0.05,
        screenMotion: 0.7,
        hasFace: true,
        activeApplication: "Xcode"
    )

    let recommendation = engine.evaluate(snapshot: snapshot, currentScene: .face, mode: .suggest)

    #expect(recommendation?.target == .screenOnly)
}

@Test
func codingProfileKeepsSpeakingOverCodeInScreenAndFace() {
    var engine = DirectorEngine(profile: .coding)
    let snapshot = SignalSnapshot(
        isSpeaking: true,
        speechLevel: 0.68,
        screenMotion: 0.1,
        hasFace: true,
        activeApplication: "Xcode"
    )

    let recommendation = engine.evaluate(snapshot: snapshot, currentScene: .face, mode: .suggest)

    #expect(recommendation?.target == .screenAndFace)
}

@Test
func teachingProfileDefaultsBackToFace() {
    var engine = DirectorEngine(profile: .teaching)
    let snapshot = SignalSnapshot(
        isSpeaking: false,
        speechLevel: 0.04,
        screenMotion: 0.12,
        hasFace: true,
        activeApplication: "Keynote",
        idleSeconds: 5
    )

    let recommendation = engine.evaluate(snapshot: snapshot, currentScene: .screenOnly, mode: .suggest)

    #expect(recommendation?.target == .face)
}

@Test
func mutedMicWarningDoesNotForceSceneChange() {
    var engine = DirectorEngine()
    let snapshot = SignalSnapshot(
        isSpeaking: true,
        speechLevel: 0.8,
        screenMotion: 0.4,
        hasFace: true,
        activeApplication: "Xcode",
        isMicMuted: true
    )

    let recommendation = engine.evaluate(snapshot: snapshot, currentScene: .screenAndFace, mode: .suggest)

    #expect(recommendation?.target == .screenAndFace)
    #expect(recommendation?.urgency == .immediate)
}

@Test
func heldDirectorCueIsSuppressedUntilHoldExpires() {
    var engine = DirectorEngine()
    let now = Date()
    let snapshot = SignalSnapshot(
        timestamp: now,
        isSpeaking: true,
        speechLevel: 0.72,
        screenMotion: 0.08,
        hasFace: true,
        activeApplication: "Notes"
    )

    let recommendation = engine.evaluate(snapshot: snapshot, currentScene: .screenAndFace, mode: .suggest)

    #expect(recommendation?.target == .face)

    engine.markCueHeld(recommendation!, at: now, duration: 5)

    let heldSnapshot = SignalSnapshot(
        timestamp: now.addingTimeInterval(2),
        isSpeaking: true,
        speechLevel: 0.72,
        screenMotion: 0.08,
        hasFace: true,
        activeApplication: "Notes"
    )

    #expect(engine.evaluate(snapshot: heldSnapshot, currentScene: .screenAndFace, mode: .suggest) == nil)

    let expiredSnapshot = SignalSnapshot(
        timestamp: now.addingTimeInterval(6),
        isSpeaking: true,
        speechLevel: 0.72,
        screenMotion: 0.08,
        hasFace: true,
        activeApplication: "Notes"
    )

    #expect(engine.evaluate(snapshot: expiredSnapshot, currentScene: .screenAndFace, mode: .suggest)?.target == .face)
}

@Test
func safetyCueBypassesHeldDirectorCue() {
    var engine = DirectorEngine()
    let now = Date()
    let recommendation = DirectorRecommendation(
        target: .face,
        confidence: 0.78,
        reason: "You are talking and the screen is quiet."
    )
    engine.markCueHeld(recommendation, at: now, duration: 30)

    let safetySnapshot = SignalSnapshot(
        timestamp: now.addingTimeInterval(2),
        isSpeaking: false,
        speechLevel: 0.04,
        screenMotion: 0.1,
        hasFace: true,
        activeApplication: "Keynote",
        isScreenFrozen: true
    )

    let safetyCue = engine.evaluate(snapshot: safetySnapshot, currentScene: .screenOnly, mode: .suggest)

    #expect(safetyCue?.target == .face)
    #expect(safetyCue?.urgency == .immediate)
}
