import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import Network
import Testing
@testable import MacStreamCore

@Test
@MainActor
func applyingDestinationPresetConfiguresRTMPEndpoint() {
    let store = StudioStore(captureDeviceProvider: FixedCaptureDeviceProvider(report: CapturePreflightReport()))

    store.applyDestinationPreset(.twitch)

    #expect(store.destination.mode == .rtmp)
    #expect(store.destination.name == "Twitch")
    #expect(store.destination.rtmpURL == StreamPlatformPreset.twitch.ingestURL)
    #expect(store.matchingDestinationPreset == .twitch)
    #expect(store.events.contains { $0.title == "Destination preset" && $0.detail == "Twitch" })
}


@Test
@MainActor
func editingDestinationServerURLAndStreamKeyBuildsCompleteRTMPEndpoint() {
    let store = StudioStore(captureDeviceProvider: FixedCaptureDeviceProvider(report: CapturePreflightReport()))

    store.applyDestinationPreset(.facebook)
    store.setRTMPStreamKey("fb_secret")

    #expect(store.destination.rtmpServerURL == StreamPlatformPreset.facebook.ingestURL)
    #expect(store.destination.rtmpStreamKey == "fb_secret")
    #expect(store.destination.rtmpURL == "rtmps://live-api-s.facebook.com:443/rtmp/fb_secret")
    #expect(store.destination.isReadyToStart)
}
@Test
@MainActor
func applyingPresetWithoutFixedIngestLeavesURLEditable() {
    let store = StudioStore(captureDeviceProvider: FixedCaptureDeviceProvider(report: CapturePreflightReport()))

    store.applyDestinationPreset(.x)

    #expect(store.destination.mode == .rtmp)
    #expect(store.destination.name == "X")
    #expect(store.destination.rtmpURL.isEmpty)
    #expect(store.matchingDestinationPreset == nil)
}

@Test
@MainActor
func matchingDestinationPresetDetectsConfiguredURL() {
    let store = StudioStore(captureDeviceProvider: FixedCaptureDeviceProvider(report: CapturePreflightReport()))

    store.destination = StreamDestination(
        mode: .rtmp,
        name: "Channel",
        rtmpURL: "rtmp://a.rtmp.youtube.com/live2/abcd-efgh"
    )

    #expect(store.matchingDestinationPreset == .youtube)
}

@Test
@MainActor
func destinationPresetCannotBeAppliedWhileStreamIsConnecting() async {
    let pipeline = DelayedStartMediaPipeline()
    let store = StudioStore(
        mediaPipeline: pipeline,
        captureDeviceProvider: FixedCaptureDeviceProvider(report: CapturePreflightReport())
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(10))

    #expect(store.isStreamConnecting)
    #expect(!store.canEditDestination)

    store.applyDestinationPreset(.twitch)

    #expect(store.destination.mode == .preview)
}

@Test
@MainActor
func reapplyingPresetPreservesEnteredStreamKey() {
    let store = StudioStore(captureDeviceProvider: FixedCaptureDeviceProvider(report: CapturePreflightReport()))
    store.applyDestinationPreset(.twitch)
    store.destination.rtmpURL = "rtmp://live.twitch.tv/app/live_123_secretkey"

    store.applyDestinationPreset(.twitch)

    #expect(store.destination.rtmpURL == "rtmp://live.twitch.tv/app/live_123_secretkey")
}

@Test
@MainActor
func switchingToAccountSpecificPresetClearsOtherPlatformURL() {
    let store = StudioStore(captureDeviceProvider: FixedCaptureDeviceProvider(report: CapturePreflightReport()))
    store.destination = StreamDestination(
        mode: .rtmp,
        name: "Twitch",
        rtmpURL: "rtmp://live.twitch.tv/app/live_123_secretkey"
    )

    store.applyDestinationPreset(.x)

    #expect(store.destination.name == "X")
    #expect(store.destination.rtmpURL.isEmpty)
}

@Test
@MainActor
func applyingCustomPresetKeepsUserTypedURL() {
    let store = StudioStore(captureDeviceProvider: FixedCaptureDeviceProvider(report: CapturePreflightReport()))
    store.destination = StreamDestination(
        mode: .rtmp,
        name: "My Server",
        rtmpURL: "rtmp://stream.example.com/live/streamkey"
    )

    store.applyDestinationPreset(.custom)

    #expect(store.destination.rtmpURL == "rtmp://stream.example.com/live/streamkey")
}

@Test
@MainActor
func kickPresetRequiresPastedEndpoint() {
    #expect(StreamPlatformPreset.kick.ingestURL == nil)
}

@Test
func presetBaseURLIsNotPersistableUntilStreamKeyAdded() {
    let draftBase = StreamDestination(mode: .rtmp, name: "Twitch", rtmpURL: StreamPlatformPreset.twitch.ingestURL ?? "")
    #expect(!draftBase.isPersistableEndpoint)

    let complete = StreamDestination(mode: .rtmp, name: "Twitch", rtmpURL: "rtmp://live.twitch.tv/app/live_key")
    #expect(complete.isPersistableEndpoint)

    #expect(!StreamDestination().isPersistableEndpoint)
}
