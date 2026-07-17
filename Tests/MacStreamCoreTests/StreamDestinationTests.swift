import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import Network
import Testing
@testable import MacStreamCore

@Test
func rtmpDestinationSplitsConnectionAndStreamName() throws {
    let destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_123"
    )

    #expect(destination.mode == .rtmp)

    let target = try destination.rtmpPublishTarget()

    #expect(target.connectionURL == "rtmps://live.example.com/app/")
    #expect(target.streamName == "sk_live_123")
}

@Test
func facebookPresetPreservesTrailingSlashForRTMPConnectURL() throws {
    var destination = StreamDestination(mode: .rtmp, name: "Facebook")
    destination.setRTMPServerURL(StreamPlatformPreset.facebook.ingestURL ?? "")
    destination.setRTMPStreamKey("fb_live_key")

    let target = try destination.rtmpPublishTarget()

    #expect(target.connectionURL == "rtmps://live-api-s.facebook.com:443/rtmp/")
    #expect(target.streamName == "fb_live_key")
    #expect(destination.safeDisplayDetail == "rtmps://live-api-s.facebook.com:443/rtmp/****")
}

@Test
func rtmpDestinationExposesEditableServerURLAndStreamKey() throws {
    var destination = StreamDestination(
        name: "Facebook",
        rtmpURL: "rtmps://live-api-s.facebook.com:443/rtmp/facebook_secret_key"
    )

    #expect(destination.rtmpServerURL == "rtmps://live-api-s.facebook.com:443/rtmp/")
    #expect(destination.rtmpStreamKey == "facebook_secret_key")

    destination.setRTMPStreamKey("new_secret")

    #expect(destination.rtmpURL == "rtmps://live-api-s.facebook.com:443/rtmp/new_secret")
    #expect(try destination.rtmpPublishTarget().streamName == "new_secret")

    destination.setRTMPServerURL("rtmps://backup.example.com/live")

    #expect(destination.rtmpURL == "rtmps://backup.example.com/live/new_secret")
}

@Test
func fullPublishURLPastedIntoServerFieldMovesSecretIntoStreamKey() throws {
    var destination = StreamDestination(mode: .rtmp, name: "YouTube", rtmpURL: "")

    destination.setRTMPServerURL("rtmps://live.example.com/app/sk_live_secret?token=abc")

    #expect(destination.rtmpServerURL == "rtmps://live.example.com/app/")
    #expect(destination.rtmpStreamKey == "sk_live_secret?token=abc")
    #expect(destination.safeDisplayDetail == "rtmps://live.example.com/app/****")
    #expect(!destination.rtmpServerURL.contains("sk_live_secret"))
}

@Test
func rtmpDestinationPreservesStreamNameQueryTokens() throws {
    let destination = StreamDestination(
        name: "Token RTMP",
        rtmpURL: "rtmps://live.example.com/app/sk_live_123?token=abc123&expires=60"
    )

    let target = try destination.rtmpPublishTarget()

    #expect(target.connectionURL == "rtmps://live.example.com/app/")
    #expect(target.streamName == "sk_live_123?token=abc123&expires=60")
    #expect(destination.safeDisplayDetail == "rtmps://live.example.com/app/****")
}

@Test
func defaultDestinationUsesPreviewSession() {
    let destination = StreamDestination()

    #expect(destination.isPreviewSession)
    #expect(destination.mode == .preview)
    #expect(destination.streamTransport(using: .endpointValidation) == .preview)
    #expect(destination.safeDisplayDetail == "Local preview session")
    #expect(throws: MediaPipelineError.self) {
        try destination.rtmpPublishTarget()
    }
}

@Test
func explicitRTMPDestinationDoesNotFallBackToPreviewForBlankURL() {
    let destination = StreamDestination(mode: .rtmp, name: "Twitch", rtmpURL: "")

    #expect(!destination.isPreviewSession)
    #expect(destination.mode == .rtmp)
    #expect(destination.safeDisplayDetail == "Invalid RTMP endpoint")
    #expect(!destination.isReadyToStart)
    #expect(destination.validationError == "Enter a valid RTMP or RTMPS URL.")
    #expect(throws: MediaPipelineError.self) {
        try destination.rtmpPublishTarget()
    }
}

@Test
func rtmpDestinationRedactsStreamKeyForDisplay() {
    let destination = StreamDestination(
        name: "Twitch",
        rtmpURL: "rtmps://live.example.com/app/sk_live_secret"
    )

    #expect(!destination.isPreviewSession)
    #expect(destination.isReadyToStart)
    #expect(destination.validationError == nil)
    #expect(destination.safeDisplayDetail == "rtmps://live.example.com/app/****")
    #expect(!destination.safeDisplayDetail.contains("sk_live_secret"))
}

@Test
func streamDestinationKeepsStableIdentityAcrossEdits() {
    let id = UUID()
    var destination = StreamDestination(
        id: id,
        isEnabled: false,
        mode: .rtmp,
        name: "Backup",
        rtmpURL: "rtmps://live.example.com/app/secret"
    )

    destination.name = "Backup ingest"
    destination.setRTMPStreamKey("new-secret")

    #expect(destination.id == id)
    #expect(!destination.isEnabled)
    #expect(!destination.safeDisplayDetail.contains("new-secret"))
}

@Test
func destinationStatusDoesNotContainEndpointSecrets() {
    let status = StreamDestinationStatus(
        id: UUID(),
        name: "YouTube",
        state: .failed,
        failureDetail: "Connection timed out"
    )

    #expect(status.state == .failed)
    #expect(status.failureDetail == "Connection timed out")
    #expect(!String(describing: status).contains("stream-key"))
}

@Test
func rtmpDestinationRejectsMissingStreamKey() {
    let destination = StreamDestination(
        name: "Bad RTMP",
        rtmpURL: "rtmp://live.example.com/app"
    )

    #expect(throws: MediaPipelineError.self) {
        try destination.rtmpPublishTarget()
    }
}

@Test
func streamStateUsesEndpointValidationCopy() {
    #expect(StreamState.connecting.detail == "Validating RTMP endpoint")
    #expect(StreamState.live.detail == "Endpoint reachable")
}

@Test
func failedStreamStateIsNotLive() {
    #expect(!StreamState.failed("Bad endpoint").isLive)
    #expect(StreamState.failed("Bad endpoint").title == "Failed")
    #expect(StreamState.failed("Bad endpoint").detail == "Bad endpoint")
}

@Test
func recordingStateExposesFailureDetail() {
    let state = RecordingState.failed("Disk full")

    #expect(state.title == "Failed")
    #expect(state.detail == "Disk full")
    #expect(state.isFailed)
    #expect(!RecordingState.recording.isFailed)
}
