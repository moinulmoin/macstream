import Foundation
import OSLog
@preconcurrency import AVFoundation
import CoreGraphics
import CoreImage
@preconcurrency import CoreMedia
import Network
@preconcurrency import ScreenCaptureKit
#if MAC_STREAM_HAS_HAISHINKIT
import HaishinKit
import RTMPHaishinKit
import VideoToolbox
#endif

public protocol MediaPipeline: Sendable {
    var streamTransport: StreamTransportKind { get }
    var currentHealth: StreamHealth? { get }
    var recordingFailureDetail: String? { get }
    var streamFailureDetail: String? { get }
    var captureSetupWarnings: [String] { get }
    var requiresCaptureReadinessForStart: Bool { get }
    var requiresScreenCaptureVideoForStream: Bool { get }
    var requiresScreenCaptureVideoForRecording: Bool { get }
    var supportedSceneKindsForStream: Set<SceneKind> { get }
    var supportedSceneKindsForRecording: Set<SceneKind> { get }

    func update(configuration: MediaPipelineConfiguration)
    func startStream(destination: StreamDestination) async throws
    func stopStream() async
    func startRecording() async throws -> URL
    func stopRecording() async
}

public extension MediaPipeline {
    var streamTransport: StreamTransportKind { .endpointValidation }
    var currentHealth: StreamHealth? { nil }
    var recordingFailureDetail: String? { nil }
    var streamFailureDetail: String? { nil }
    var captureSetupWarnings: [String] { [] }
    var requiresCaptureReadinessForStart: Bool { false }
    var requiresScreenCaptureVideoForStream: Bool { false }
    var requiresScreenCaptureVideoForRecording: Bool { false }
    var supportedSceneKindsForStream: Set<SceneKind> { Set(SceneKind.allCases) }
    var supportedSceneKindsForRecording: Set<SceneKind> { Set(SceneKind.allCases) }

    func update(configuration: MediaPipelineConfiguration) {}
}

public enum StreamTransportKind: String, Codable, Equatable, Sendable {
    case preview
    case endpointValidation
    case rtmpPublish

    public var title: String {
        switch self {
        case .preview: "Preview"
        case .endpointValidation: "Endpoint Check"
        case .rtmpPublish: "RTMP Publish"
        }
    }

    public var detail: String {
        switch self {
        case .preview:
            "Simulated stream session"
        case .endpointValidation:
            "Validates RTMP reachability; media publish adapter is not linked"
        case .rtmpPublish:
            "Publishes media samples through the RTMP adapter"
        }
    }
}

public enum StreamDestinationMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case preview
    case rtmp

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .preview: "Preview"
        case .rtmp: "RTMP"
        }
    }

    public var symbolName: String {
        switch self {
        case .preview: "play.circle"
        case .rtmp: "antenna.radiowaves.left.and.right"
        }
    }
}

public enum StreamPlatformPreset: String, CaseIterable, Identifiable, Sendable {
    case twitch
    case youtube
    case facebook
    case x
    case kick
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .twitch: "Twitch"
        case .youtube: "YouTube"
        case .facebook: "Facebook"
        case .x: "X"
        case .kick: "Kick"
        case .custom: "Custom"
        }
    }

    public var symbolName: String {
        switch self {
        case .twitch: "gamecontroller.fill"
        case .youtube: "play.rectangle.fill"
        case .facebook: "person.2.fill"
        case .x: "bubble.left.and.bubble.right.fill"
        case .kick: "bolt.fill"
        case .custom: "link"
        }
    }

    /// Prefilled RTMP/RTMPS server URL. The stream key is entered separately.
    /// `nil` when the server is account- or broadcast-specific and must be pasted.
    public var ingestURL: String? {
        switch self {
        case .twitch: "rtmp://live.twitch.tv/app/"
        case .youtube: "rtmp://a.rtmp.youtube.com/live2/"
        case .facebook: "rtmps://live-api-s.facebook.com:443/rtmp/"
        case .x, .kick, .custom: nil
        }
    }

    /// Where to find the stream key (and any per-account server URL).
    public var keyHint: String {
        switch self {
        case .twitch: "Creator Dashboard › Settings › Stream. Paste the server URL and stream key separately."
        case .youtube: "YouTube Studio › Go Live. Paste the stream URL and stream key separately."
        case .facebook: "facebook.com/live/producer › Streaming software. Paste the Facebook stream key."
        case .kick: "Kick Creator Dashboard › paste the Server URL and Stream Key separately."
        case .x: "Create a broadcast in X Media Studio Producer, then paste its server URL and stream key."
        case .custom: "Paste the RTMP/RTMPS server URL and stream key separately."
        }
    }
}

public struct StreamDestination: Equatable, Sendable {
    public var mode: StreamDestinationMode
    public var name: String
    public var rtmpServerURL: String
    public var rtmpStreamKey: String

    public var rtmpURL: String {
        get {
            Self.combinedRTMPURL(serverURL: rtmpServerURL, streamKey: rtmpStreamKey)
        }
        set {
            let splitURL = Self.splitRTMPURL(newValue)
            rtmpServerURL = splitURL.serverURL
            rtmpStreamKey = splitURL.streamKey
        }
    }

    public init(
        mode: StreamDestinationMode? = nil,
        name: String = "Preview Session",
        rtmpURL: String = "preview"
    ) {
        let splitURL = Self.splitRTMPURL(rtmpURL)
        self.mode = mode ?? Self.inferMode(from: rtmpURL)
        self.name = name
        self.rtmpServerURL = splitURL.serverURL
        self.rtmpStreamKey = splitURL.streamKey
    }

    public var isPreviewSession: Bool {
        mode == .preview
    }

    public func streamTransport(using pipelineTransport: StreamTransportKind) -> StreamTransportKind {
        isPreviewSession ? .preview : pipelineTransport
    }

    public var validationError: String? {
        guard !isPreviewSession else { return nil }

        do {
            _ = try rtmpPublishTarget()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    public var isReadyToStart: Bool {
        validationError == nil
    }

    /// A complete, valid RTMP endpoint worth persisting. Excludes preview sessions and
    /// draft values (preset bases with no stream key yet, or otherwise invalid URLs).
    public var isPersistableEndpoint: Bool {
        !isPreviewSession && isReadyToStart
    }

    public var safeDisplayDetail: String {
        guard !isPreviewSession else {
            return "Local preview session"
        }

        guard let target = try? rtmpPublishTarget() else {
            return "Invalid RTMP endpoint"
        }

        let connectionPrefix = target.connectionURL.hasSuffix("/")
            ? target.connectionURL
            : "\(target.connectionURL)/"
        return "\(connectionPrefix)****"
    }

    public var usesPreviewSentinelURL: Bool {
        let trimmed = rtmpURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let lowered = trimmed.lowercased()
        if lowered == "preview" || lowered == "macstream-preview" {
            return true
        }

        return URLComponents(string: trimmed)?.scheme?.lowercased() == "macstream-preview"
    }

    public mutating func setRTMPServerURL(_ serverURL: String) {
        mode = .rtmp
        rtmpServerURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public mutating func setRTMPStreamKey(_ streamKey: String) {
        mode = .rtmp
        rtmpStreamKey = Self.normalizedStreamKey(streamKey)
    }

    public static func combinedRTMPURL(serverURL: String, streamKey: String) -> String {
        let trimmedServerURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStreamKey = normalizedStreamKey(streamKey)
        guard !trimmedServerURL.isEmpty, !trimmedStreamKey.isEmpty else {
            return trimmedServerURL
        }
        return trimmedServerURL.hasSuffix("/")
            ? "\(trimmedServerURL)\(trimmedStreamKey)"
            : "\(trimmedServerURL)/\(trimmedStreamKey)"
    }

    private static func splitRTMPURL(_ rtmpURL: String) -> (serverURL: String, streamKey: String) {
        let trimmedURL = rtmpURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmedURL),
              let scheme = components.scheme?.lowercased(),
              scheme == "rtmp" || scheme == "rtmps",
              components.host?.isEmpty == false
        else {
            return (trimmedURL, "")
        }

        let pathParts = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard pathParts.count >= 2, let rawStreamKey = pathParts.last, !rawStreamKey.isEmpty else {
            return (trimmedURL, "")
        }

        var streamKey = rawStreamKey
        if let query = components.percentEncodedQuery, !query.isEmpty {
            streamKey += "?\(query)"
        }
        if let fragment = components.percentEncodedFragment, !fragment.isEmpty {
            streamKey += "#\(fragment)"
        }

        var serverComponents = components
        serverComponents.path = "/" + pathParts.dropLast().joined(separator: "/")
        serverComponents.query = nil
        serverComponents.fragment = nil
        guard let serverURL = serverComponents.string else {
            return (trimmedURL, "")
        }

        return (serverURL.hasSuffix("/") ? serverURL : "\(serverURL)/", streamKey)
    }

    private static func normalizedStreamKey(_ streamKey: String) -> String {
        streamKey.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    public func rtmpPublishTarget() throws -> RTMPPublishTarget {
        guard !isPreviewSession else {
            throw MediaPipelineError.unavailable("Enter an RTMP or RTMPS URL to publish.")
        }

        let trimmedServerURL = rtmpServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmedServerURL),
              let scheme = components.scheme?.lowercased(),
              scheme == "rtmp" || scheme == "rtmps",
              let host = components.host,
              !host.isEmpty
        else {
            throw MediaPipelineError.unavailable("Enter a valid RTMP or RTMPS URL.")
        }

        let pathParts = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
        guard !pathParts.isEmpty else {
            throw MediaPipelineError.unavailable("RTMP server URL must include an app path.")
        }

        let streamName = Self.normalizedStreamKey(rtmpStreamKey)
        guard !streamName.isEmpty else {
            throw MediaPipelineError.unavailable("RTMP stream key is required.")
        }

        return RTMPPublishTarget(connectionURL: trimmedServerURL, streamName: streamName)
    }

    private static func inferMode(from rtmpURL: String) -> StreamDestinationMode {
        let destination = StreamDestination(mode: .preview, rtmpURL: rtmpURL)
        return destination.usesPreviewSentinelURL ? .preview : .rtmp
    }
}

public struct RTMPPublishTarget: Equatable, Sendable {
    public var connectionURL: String
    public var streamName: String

    public init(connectionURL: String, streamName: String) {
        self.connectionURL = connectionURL
        self.streamName = streamName
    }
}

public enum MediaPipelineError: Error, LocalizedError {
    case unavailable(String)
    case alreadyRecording
    case notRecording
    case connectionTimedOut(TimeInterval)

    public var errorDescription: String? {
        switch self {
        case let .unavailable(reason): reason
        case .alreadyRecording: "A local recording is already running."
        case .notRecording: "No local recording is running."
        case let .connectionTimedOut(seconds): "RTMP endpoint did not respond within \(Int(seconds)) seconds."
        }
    }
}

public struct PreviewMediaPipeline: MediaPipeline {
    public init() {}

    public var streamTransport: StreamTransportKind {
        .preview
    }

    public func startStream(destination: StreamDestination) async throws {
    }

    public func stopStream() async {
    }

    public func startRecording() async throws -> URL {
        return URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MacStream-preview.mov")
    }

    public func stopRecording() async {
    }
}

public final class SystemMediaPipeline: NSObject, MediaPipeline, SCStreamOutput, AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.macstream.media.recording", qos: .userInitiated)
    private let rtmpPublisherFactory: @Sendable (RTMPPublishTarget) -> any RTMPPublisher
    private var mediaConfiguration = MediaPipelineConfiguration()
    private var stream: SCStream?
    private var publishingStream: SCStream?
    private var recordingCaptureGeometry: MediaCaptureGeometry?
    private var publishingCaptureGeometry: MediaCaptureGeometry?
    private var microphoneSession: AVCaptureSession?
    private var recordingCameraSession: AVCaptureSession?
    private var publishingCameraSession: AVCaptureSession?
    private var publishingMicrophoneSession: AVCaptureSession?
    private var microphoneOutput: AVCaptureAudioDataOutput?
    private var recordingCameraOutput: AVCaptureVideoDataOutput?
    private var publishingCameraOutput: AVCaptureVideoDataOutput?
    private var publishingMicrophoneOutput: AVCaptureAudioDataOutput?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var videoPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var audioInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?
    private var recordingFailureReason: String?
    private var streamFailureReason: String?
    private var setupWarnings: [String] = []
    private var rtmpPublisher: RTMPPublisher?
    private var videoCompositor: RecordingVideoCompositor?
    private var publishingVideoCompositor: RecordingVideoCompositor?
    private var publishingPixelBufferPool: CVPixelBufferPool?
    private var publishingVideoFormatDescriptionCache: VideoFormatDescriptionCache?
    private var latestCameraPixelBuffer: CVPixelBuffer?
    private var latestPublishingCameraPixelBuffer: CVPixelBuffer?
    private var didStartSession = false
    private var currentURL: URL?
    private var publishingOwnsMicrophoneSession = false
    private var recordingUsesPublishingMicrophoneSession = false
    private var mediaHealth = StreamHealth()
    private var frameWindowStartedAt = Date()
    private var frameWindowCount = 0
    private var firstPublishingVideoContinuation: CheckedContinuation<Void, any Error>?
    private var didPublishFirstVideoFrame = false
    private var rtmpPublisherEventTask: Task<Void, Never>?
    private var rtmpPublisherHealthTask: Task<Void, Never>?
    private var lastRTMPByteCount: Int64?
    private var lastRTMPByteSampledAt: Date?
    private var publishingAudioTrackPlan: (systemAudio: UInt8?, microphone: UInt8?, mainTrack: UInt8) = (nil, nil, 0)

    public override init() {
        self.rtmpPublisherFactory = Self.makeRTMPPublisher
        super.init()
    }

    init(rtmpPublisherFactory: @escaping @Sendable (RTMPPublishTarget) -> any RTMPPublisher) {
        self.rtmpPublisherFactory = rtmpPublisherFactory
        super.init()
    }

    public var streamTransport: StreamTransportKind {
        Self.preferredStreamTransport
    }

    public var currentHealth: StreamHealth? {
        queue.sync {
            guard publishingStream != nil || stream != nil || writer != nil else {
                return nil
            }

            return mediaHealth
        }
    }

    public var recordingFailureDetail: String? {
        queue.sync { recordingFailureReason }
    }
    public var streamFailureDetail: String? {
        queue.sync { streamFailureReason }
    }


    public var captureSetupWarnings: [String] {
        queue.sync { setupWarnings }
    }

    public var requiresCaptureReadinessForStart: Bool {
        true
    }

    public var requiresScreenCaptureVideoForStream: Bool {
        Self.capturesMediaForStreamTransport
    }

    public var requiresScreenCaptureVideoForRecording: Bool {
        true
    }

    public var supportedSceneKindsForStream: Set<SceneKind> {
        Self.capturesMediaForStreamTransport ? [.screenOnly, .screenAndFace] : Set(SceneKind.allCases)
    }

    public var supportedSceneKindsForRecording: Set<SceneKind> {
        [.screenOnly, .screenAndFace]
    }

    static var capturesMediaForStreamTransport: Bool {
        #if MAC_STREAM_HAS_HAISHINKIT
        true
        #else
        false
        #endif
    }

    private static let rtmpLogger = Logger(subsystem: "com.ideaplexa.macstream", category: "rtmp")
    private static let firstPublishingVideoFrameTimeout: Duration = .seconds(8)

    static let sharesMicrophoneCaptureBetweenStreamAndRecording = true

    public func update(configuration: MediaPipelineConfiguration) {
        let updateResult: (updates: [ActiveStreamConfigurationUpdate], shouldStartPublishingCamera: Bool) = queue.sync {
            let previousConfiguration = self.mediaConfiguration
            self.mediaConfiguration = configuration
            if self.stream != nil,
               configuration.sceneKind == .screenAndFace {
                self.updateRecordingVideoComposition(using: configuration)
            } else if configuration.sceneKind != .screenAndFace {
                self.videoCompositor = nil
            }
            if self.publishingStream != nil,
               Self.shouldPublishCompositedVideoSample(sceneKind: configuration.sceneKind) {
                self.updatePublishingVideoComposition(using: configuration)
            } else if self.publishingStream != nil {
                self.publishingVideoCompositor = nil
                self.publishingPixelBufferPool = nil
                self.publishingVideoFormatDescriptionCache = nil
                self.latestPublishingCameraPixelBuffer = nil
            }
            let shouldStartPublishingCamera = self.publishingStream != nil
                && Self.shouldPublishCompositedVideoSample(sceneKind: configuration.sceneKind)
                && self.publishingCameraSession == nil

            guard Self.shouldUpdateActiveStreamConfiguration(
                from: previousConfiguration,
                to: configuration
            ) else {
                return ([], shouldStartPublishingCamera)
            }
            return (self.activeStreamConfigurationUpdates(for: configuration), shouldStartPublishingCamera)
        }
        queue.async {
            self.applyActiveMicrophoneCaptureState()
            self.applyActivePublishingCameraCaptureState()
        }
        if updateResult.shouldStartPublishingCamera {
            Task {
                await self.startPublishingCameraCaptureIfNeeded(configuration: configuration)
            }
        }
        for update in updateResult.updates {
            Task {
                try? await update.stream.updateConfiguration(update.configuration)
            }
        }
    }

    public func startStream(destination: StreamDestination) async throws {
        if destination.isPreviewSession {
            return
        }

        let target = try destination.rtmpPublishTarget()
        let publisher = rtmpPublisherFactory(target)
        try await publisher.configure(configuration: mediaConfiguration)
        startRTMPPublisherObservation(for: publisher)

        do {
            try await publisher.connect()
            try Task.checkCancellation()
            queue.sync {
                self.rtmpPublisher = publisher
            }
            if Self.capturesMediaForStreamTransport {
                do {
                    try await startPublishingCapture()
                } catch {
                    await stopStream()
                    throw error
                }
            }
        } catch {
            stopRTMPPublisherObservation()
            await publisher.close()
            throw error
        }
    }

    public func stopStream() async {
        let state = queue.sync {
            let publisher = rtmpPublisher
            let stream = publishingStream
            let microphoneSession = publishingMicrophoneSession
            let cameraSession = publishingCameraSession
            let shouldStopMicrophoneSession: Bool

            if recordingUsesPublishingMicrophoneSession, let microphoneSession {
                self.microphoneSession = microphoneSession
                self.microphoneOutput = publishingMicrophoneOutput
                recordingUsesPublishingMicrophoneSession = false
                shouldStopMicrophoneSession = false
            } else {
                shouldStopMicrophoneSession = publishingOwnsMicrophoneSession
            }

            rtmpPublisher = nil
            publishingAudioTrackPlan = (nil, nil, 0)
            rtmpPublisherEventTask?.cancel()
            rtmpPublisherEventTask = nil
            rtmpPublisherHealthTask?.cancel()
            rtmpPublisherHealthTask = nil
            streamFailureReason = nil
            publishingStream = nil
            publishingCaptureGeometry = nil
            publishingCameraSession = nil
            publishingCameraOutput = nil
            publishingMicrophoneSession = nil
            publishingMicrophoneOutput = nil
            publishingVideoCompositor = nil
            publishingPixelBufferPool = nil
            publishingVideoFormatDescriptionCache = nil
            latestPublishingCameraPixelBuffer = nil
            publishingOwnsMicrophoneSession = false
            firstPublishingVideoContinuation?.resume(throwing: CancellationError())
            firstPublishingVideoContinuation = nil
            didPublishFirstVideoFrame = false
            lastRTMPByteCount = nil
            lastRTMPByteSampledAt = nil
            if self.stream == nil, self.writer == nil {
                self.mediaHealth = StreamHealth()
            } else {
                self.mediaHealth.publishState = .disconnected
                self.mediaHealth.outboundBytesPerSecond = 0
                self.mediaHealth.bitrateKbps = 0
            }
            return PublishingCaptureState(
                stream: stream,
                microphoneSession: microphoneSession,
                cameraSession: cameraSession,
                shouldStopMicrophoneSession: shouldStopMicrophoneSession,
                publisher: publisher
            )
        }

        try? await state.stream?.stopCapture()
        if state.shouldStopMicrophoneSession, state.microphoneSession?.isRunning == true {
            state.microphoneSession?.stopRunning()
        }
        if state.cameraSession?.isRunning == true {
            state.cameraSession?.stopRunning()
        }
        await state.publisher?.close()
    }

    public func startRecording() async throws -> URL {
        if await isRecording {
            throw MediaPipelineError.alreadyRecording
        }

        queue.sync {
            self.recordingFailureReason = nil
            self.setupWarnings = []
        }
        var setupWarnings: [String] = []

        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw MediaPipelineError.unavailable("Screen recording permission is required.")
        }

        let mediaConfiguration = queue.sync {
            self.mediaConfiguration
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let selection = try Self.captureSelection(
            from: content,
            target: mediaConfiguration.screenCaptureTarget,
            maxWidth: mediaConfiguration.maxVideoWidth,
            unavailableReason: "No display or window is available for recording."
        )
        try Task.checkCancellation()

        let outputURL = try makeRecordingURL()
        let outputWidth = selection.geometry.width(for: mediaConfiguration.maxVideoWidth)
        let outputHeight = selection.geometry.height(for: mediaConfiguration.maxVideoWidth)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: outputWidth,
                AVVideoHeightKey: outputHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: mediaConfiguration.videoBitrate,
                    AVVideoExpectedSourceFrameRateKey: mediaConfiguration.framesPerSecond,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
        )
        videoInput.expectsMediaDataInRealTime = true

        guard writer.canAdd(videoInput) else {
            throw MediaPipelineError.unavailable("Cannot add video input to local recorder.")
        }
        writer.add(videoInput)

        let videoPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
        let videoCompositor: RecordingVideoCompositor?
        if mediaConfiguration.sceneKind == .screenAndFace {
            videoPixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: outputWidth,
                    kCVPixelBufferHeightKey as String: outputHeight,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:]
                ]
            )
            videoCompositor = RecordingVideoCompositor(
                outputWidth: outputWidth,
                outputHeight: outputHeight,
                cameraEnhancements: mediaConfiguration.cameraEnhancements,
                layoutSettings: mediaConfiguration.layoutSettings
            )
        } else {
            videoPixelBufferAdaptor = nil
            videoCompositor = nil
        }

        let audioInput: AVAssetWriterInput?
        if mediaConfiguration.capturesSystemAudio {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 128_000
                ]
            )
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            } else {
                setupWarnings.append("System audio could not be attached; this recording will not include system audio.")
                audioInput = nil
            }
        } else {
            audioInput = nil
        }

        let publishingMicrophoneCapture = queue.sync {
            activePublishingMicrophoneCapture
        }
        let usesPublishingMicrophoneSession = mediaConfiguration.capturesMicrophone && publishingMicrophoneCapture != nil
        let microphoneCapture = usesPublishingMicrophoneSession
            ? nil
            : (mediaConfiguration.capturesMicrophone ? await makeMicrophoneCaptureIfAvailable(deviceID: mediaConfiguration.microphoneDeviceID) : nil)
        if mediaConfiguration.capturesMicrophone,
           !usesPublishingMicrophoneSession,
           microphoneCapture == nil {
            setupWarnings.append("Microphone capture could not be attached; this recording will not include microphone audio.")
        }
        let hasMicrophoneCapture = usesPublishingMicrophoneSession || microphoneCapture != nil
        let microphoneInput: AVAssetWriterInput?
        if hasMicrophoneCapture {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: 96_000
                ]
            )
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                microphoneInput = input
            } else {
                setupWarnings.append("Microphone audio could not be attached; this recording will not include microphone audio.")
                microphoneInput = nil
            }
        } else {
            microphoneInput = nil
        }

        let cameraCapture = mediaConfiguration.sceneKind == .screenAndFace
            ? await makeCameraCaptureIfAvailable(configuration: mediaConfiguration)
            : nil
        if mediaConfiguration.sceneKind == .screenAndFace, cameraCapture == nil {
            writer.cancelWriting()
            throw MediaPipelineError.unavailable("Webcam capture is required for Screen + Webcam recording.")
        }

        do {
            try Task.checkCancellation()
        } catch {
            writer.cancelWriting()
            throw error
        }

        let configuration = SCStreamConfiguration()
        Self.configureStream(
            configuration,
            geometry: selection.geometry,
            mediaConfiguration: mediaConfiguration
        )

        let stream = SCStream(filter: selection.filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if mediaConfiguration.capturesSystemAudio {
            do {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            } catch {
                setupWarnings.append("System audio capture could not start; this recording will not include system audio.")
            }
        }

        do {
            try Task.checkCancellation()
        } catch {
            writer.cancelWriting()
            throw error
        }

        queue.sync {
            self.stream = stream
            self.recordingCaptureGeometry = selection.geometry
            self.writer = writer
            self.videoInput = videoInput
            self.videoPixelBufferAdaptor = videoPixelBufferAdaptor
            self.audioInput = audioInput
            self.microphoneInput = microphoneInput
            self.microphoneSession = microphoneCapture?.session
            self.microphoneOutput = microphoneCapture?.output
            self.recordingCameraSession = cameraCapture?.session
            self.recordingCameraOutput = cameraCapture?.output
            self.recordingUsesPublishingMicrophoneSession = usesPublishingMicrophoneSession
            self.videoCompositor = videoCompositor
            self.latestCameraPixelBuffer = nil
            self.didStartSession = false
            self.currentURL = outputURL
            self.setupWarnings = setupWarnings
            self.resetHealth(using: mediaConfiguration)
        }

        do {
            if let cameraCapture {
                startCameraSession(cameraCapture.session)
            }
            try await stream.startCapture()
            try Task.checkCancellation()
            if let microphoneCapture {
                startMicrophoneSession(microphoneCapture.session)
            }
            return outputURL
        } catch {
            await stopRecording()
            throw error
        }
    }

    public func stopRecording() async {
        let state = queue.sync {
            let stream = stream
            let microphoneSession = microphoneSession
            let recordingCameraSession = recordingCameraSession
            let writer = writer
            let videoInput = videoInput
            let audioInput = audioInput
            let microphoneInput = microphoneInput
            let publishingUsesRecordingMicrophone = microphoneSession != nil && publishingMicrophoneSession === microphoneSession
            self.stream = nil
            self.recordingCaptureGeometry = nil
            self.microphoneSession = nil
            self.microphoneOutput = nil
            self.recordingCameraSession = nil
            self.recordingCameraOutput = nil
            self.writer = nil
            self.videoInput = nil
            self.videoPixelBufferAdaptor = nil
            self.audioInput = nil
            self.microphoneInput = nil
            recordingUsesPublishingMicrophoneSession = false
            videoCompositor = nil
            latestCameraPixelBuffer = nil
            if publishingUsesRecordingMicrophone {
                publishingOwnsMicrophoneSession = true
            }
            if publishingStream == nil {
                mediaHealth = StreamHealth()
            }
            didStartSession = false
            currentURL = nil
            return RecordingWriterState(
                stream: stream,
                microphoneSession: microphoneSession,
                recordingCameraSession: recordingCameraSession,
                writer: writer,
                videoInput: videoInput,
                audioInput: audioInput,
                microphoneInput: microphoneInput,
                shouldStopMicrophoneSession: !publishingUsesRecordingMicrophone
            )
        }

        try? await state.stream?.stopCapture()

        await withCheckedContinuation { continuation in
            if state.shouldStopMicrophoneSession, state.microphoneSession?.isRunning == true {
                state.microphoneSession?.stopRunning()
            }
            if state.recordingCameraSession?.isRunning == true {
                state.recordingCameraSession?.stopRunning()
            }
            state.videoInput?.markAsFinished()
            state.audioInput?.markAsFinished()
            state.microphoneInput?.markAsFinished()

            guard let writer = state.writer else {
                continuation.resume()
                return
            }

            if writer.status == .writing {
                let sendableWriter = SendableAssetWriter(writer)
                writer.finishWriting { [weak self, sendableWriter] in
                    if let detail = Self.writerFailureDetail(status: sendableWriter.status, errorDescription: sendableWriter.errorDescription) {
                        self?.queue.sync {
                            if self?.recordingFailureReason == nil {
                                self?.recordingFailureReason = detail
                            }
                        }
                    }
                    continuation.resume()
                }
                return
            }

            if let detail = Self.writerFailureDetail(status: writer.status, errorDescription: writer.error?.localizedDescription) {
                queue.sync {
                    if recordingFailureReason == nil {
                        recordingFailureReason = detail
                    }
                }
            }

            if Self.shouldCancelWriterOnStop(status: writer.status) {
                writer.cancelWriting()
            }

            continuation.resume()
        }
    }

    static func shouldCancelWriterOnStop(status: AVAssetWriter.Status) -> Bool {
        status == .unknown
    }

    static func writerFailureDetail(status: AVAssetWriter.Status, errorDescription: String?) -> String? {
        guard status == .failed else { return nil }
        if let errorDescription, !errorDescription.isEmpty {
            return "Recording failed: \(errorDescription)"
        }
        return "Recording failed because the local media writer failed."
    }

    private func recordWriterFailureIfNeeded(status: AVAssetWriter.Status, errorDescription: String?) {
        guard recordingFailureReason == nil,
              let detail = Self.writerFailureDetail(status: status, errorDescription: errorDescription)
        else { return }

        recordingFailureReason = detail
    }

    private var isRecording: Bool {
        get async {
            queue.sync { stream != nil || writer != nil }
        }
    }

    private func makeRecordingURL() throws -> URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        let directory = (movies ?? FileManager.default.temporaryDirectory).appendingPathComponent("MacStream", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return MacStreamArtifactFileNamer.uniqueURL(
            in: directory,
            prefix: "MacStream",
            fileExtension: "mov"
        )
    }

    private func makeMicrophoneCaptureIfAvailable(deviceID: String?) async -> MicrophoneCapture? {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        let isAllowed: Bool

        switch status {
        case .authorized:
            isAllowed = true
        case .notDetermined:
            isAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            isAllowed = false
        @unknown default:
            isAllowed = false
        }

        guard isAllowed,
              let device = Self.audioCaptureDevice(matching: deviceID),
              let input = try? AVCaptureDeviceInput(device: device)
        else {
            return nil
        }

        let session = AVCaptureSession()
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)

        session.beginConfiguration()
        if session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()

        return session.inputs.isEmpty || session.outputs.isEmpty
            ? nil
            : MicrophoneCapture(session: session, output: output)
    }

    private func makeCameraCaptureIfAvailable(configuration: MediaPipelineConfiguration) async -> CameraCapture? {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let isAllowed: Bool

        switch status {
        case .authorized:
            isAllowed = true
        case .notDetermined:
            isAllowed = await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            isAllowed = false
        @unknown default:
            isAllowed = false
        }

        guard isAllowed,
              let device = Self.videoCaptureDevice(matching: configuration.cameraDeviceID),
              let input = try? AVCaptureDeviceInput(device: device)
        else {
            return nil
        }

        let session = AVCaptureSession()
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)

        session.beginConfiguration()
        let preset = Self.cameraSessionPreset(for: configuration)
        if session.canSetSessionPreset(preset) {
            session.sessionPreset = preset
        }
        if session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()

        applyCameraTuning(to: device, configuration: configuration)

        return session.inputs.isEmpty || session.outputs.isEmpty
            ? nil
            : CameraCapture(session: session, output: output)
    }

    private static func videoCaptureDevice(matching id: String?) -> AVCaptureDevice? {
        if let id {
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .external],
                mediaType: .video,
                position: .unspecified
            )
            if let match = discovery.devices.first(where: { CaptureDeviceInfo.cameraID(uniqueID: $0.uniqueID) == id }) {
                return match
            }
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
            ?? AVCaptureDevice.default(for: .video)
    }

    private static func audioCaptureDevice(matching id: String?) -> AVCaptureDevice? {
        if let id {
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone],
                mediaType: .audio,
                position: .unspecified
            )
            if let match = discovery.devices.first(where: { CaptureDeviceInfo.microphoneID(uniqueID: $0.uniqueID) == id }) {
                return match
            }
        }
        return AVCaptureDevice.default(for: .audio)
    }

    private func startPublishingCapture() async throws {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw MediaPipelineError.unavailable("Screen recording permission is required for RTMP publishing.")
        }

        let mediaConfiguration = queue.sync {
            self.mediaConfiguration
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let selection = try Self.captureSelection(
            from: content,
            target: mediaConfiguration.screenCaptureTarget,
            maxWidth: mediaConfiguration.maxVideoWidth,
            unavailableReason: "No display or window is available for RTMP publishing."
        )
        let configuration = Self.publishingStreamConfiguration(
            geometry: selection.geometry,
            mediaConfiguration: mediaConfiguration
        )

        let stream = SCStream(filter: selection.filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if mediaConfiguration.capturesSystemAudio {
            do {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            } catch {
                // Publishing can continue without system audio; recording reports this degradation separately.
            }
        }
        let usesCompositedPublishing = Self.shouldPublishCompositedVideoSample(sceneKind: mediaConfiguration.sceneKind)
        let publishingOutputWidth = selection.geometry.width(for: mediaConfiguration.maxVideoWidth)
        let publishingOutputHeight = selection.geometry.height(for: mediaConfiguration.maxVideoWidth)
        let publishingPixelBufferPool = usesCompositedPublishing
            ? Self.makePixelBufferPool(width: publishingOutputWidth, height: publishingOutputHeight)
            : nil
        let publishingVideoCompositor = usesCompositedPublishing
            ? RecordingVideoCompositor(
                outputWidth: publishingOutputWidth,
                outputHeight: publishingOutputHeight,
                cameraEnhancements: mediaConfiguration.cameraEnhancements,
                layoutSettings: mediaConfiguration.layoutSettings
            )
            : nil
        if usesCompositedPublishing, publishingPixelBufferPool == nil {
            throw MediaPipelineError.unavailable("Cannot allocate composed RTMP video buffers.")
        }
        let cameraCapture = usesCompositedPublishing
            ? await makeCameraCaptureIfAvailable(configuration: mediaConfiguration)
            : nil
        if usesCompositedPublishing, cameraCapture == nil {
            throw MediaPipelineError.unavailable("Webcam capture is required for Screen + Webcam RTMP publishing.")
        }


        let recordingMicrophoneCapture = queue.sync {
            activeRecordingMicrophoneCapture
        }
        let microphoneSession: AVCaptureSession?
        let microphoneOutput: AVCaptureAudioDataOutput?
        let ownsMicrophoneSession: Bool
        if mediaConfiguration.capturesMicrophone, let recordingMicrophoneCapture {
            microphoneSession = recordingMicrophoneCapture.session
            microphoneOutput = recordingMicrophoneCapture.output
            ownsMicrophoneSession = false
        } else if mediaConfiguration.capturesMicrophone {
            let microphoneCapture = await makeMicrophoneCaptureIfAvailable(deviceID: mediaConfiguration.microphoneDeviceID)
            microphoneSession = microphoneCapture?.session
            microphoneOutput = microphoneCapture?.output
            ownsMicrophoneSession = microphoneCapture != nil
        } else {
            microphoneSession = nil
            microphoneOutput = nil
            ownsMicrophoneSession = false
        }

        let audioTrackPlan = Self.publishingAudioTrackPlan(configuration: mediaConfiguration)

        try Task.checkCancellation()

        queue.sync {
            self.publishingStream = stream
            self.publishingCaptureGeometry = selection.geometry
            self.publishingCameraSession = cameraCapture?.session
            self.publishingCameraOutput = cameraCapture?.output
            self.publishingMicrophoneSession = microphoneSession
            self.publishingMicrophoneOutput = microphoneOutput
            self.publishingAudioTrackPlan = audioTrackPlan
            self.publishingVideoCompositor = publishingVideoCompositor
            self.publishingPixelBufferPool = publishingPixelBufferPool
            self.publishingVideoFormatDescriptionCache = nil
            self.latestPublishingCameraPixelBuffer = nil
            self.publishingOwnsMicrophoneSession = ownsMicrophoneSession
            self.firstPublishingVideoContinuation = nil
            self.didPublishFirstVideoFrame = false
            self.resetHealth(using: mediaConfiguration)
        }

        do {
            if let cameraCapture {
                startCameraSession(cameraCapture.session)
            }
            try await stream.startCapture()
            try Task.checkCancellation()
            startMicrophoneSession(microphoneSession)
            try await waitForFirstPublishingVideoFrame()
        } catch {
            queue.sync {
                if self.publishingStream === stream {
                    self.publishingStream = nil
                    self.publishingCaptureGeometry = nil
                    self.publishingCameraSession = nil
                    self.publishingCameraOutput = nil
                    self.publishingVideoCompositor = nil
                    self.publishingPixelBufferPool = nil
                    self.publishingVideoFormatDescriptionCache = nil
                    self.latestPublishingCameraPixelBuffer = nil
                    self.publishingAudioTrackPlan = (nil, nil, 0)
                }
                if self.publishingMicrophoneSession === microphoneSession {
                    self.publishingMicrophoneSession = nil
                    self.publishingMicrophoneOutput = nil
                    self.publishingOwnsMicrophoneSession = false
                }
                if self.stream == nil {
                    self.mediaHealth = StreamHealth()
                }
            }
            if ownsMicrophoneSession, microphoneSession?.isRunning == true {
                microphoneSession?.stopRunning()
            }
            if cameraCapture?.session.isRunning == true {
                cameraCapture?.session.stopRunning()
            }
            throw error
        }
    }

    private func startMicrophoneSession(_ session: AVCaptureSession?) {
        queue.async {
            self.startMicrophoneSessionIfNeeded(session)
        }
    }

    private func startCameraSession(_ session: AVCaptureSession?) {
        queue.async {
            self.startCameraSessionIfNeeded(session)
        }
    }

    private func applyActiveMicrophoneCaptureState() {
        let shouldRun = Self.shouldProcessMicrophoneAudioSample(configuration: mediaConfiguration)
        for session in activeMicrophoneSessions() {
            if shouldRun {
                startMicrophoneSessionIfNeeded(session)
            } else if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func activeStreamConfigurationUpdates(
        for configuration: MediaPipelineConfiguration
    ) -> [ActiveStreamConfigurationUpdate] {
        var updates: [ActiveStreamConfigurationUpdate] = []
        if let stream, let recordingCaptureGeometry {
            updates.append(ActiveStreamConfigurationUpdate(
                stream: stream,
                configuration: Self.streamConfiguration(
                    geometry: recordingCaptureGeometry,
                    mediaConfiguration: configuration
                )
            ))
        }
        if let publishingStream, let publishingCaptureGeometry {
            updates.append(ActiveStreamConfigurationUpdate(
                stream: publishingStream,
                configuration: Self.publishingStreamConfiguration(
                    geometry: publishingCaptureGeometry,
                    mediaConfiguration: configuration
                )
            ))
        }
        return updates
    }

    private func activeMicrophoneSessions() -> [AVCaptureSession] {
        var seen = Set<ObjectIdentifier>()
        return [microphoneSession, publishingMicrophoneSession].compactMap { session in
            guard let session else { return nil }
            let identifier = ObjectIdentifier(session)
            guard seen.insert(identifier).inserted else { return nil }
            return session
        }
    }

    private var activeRecordingMicrophoneCapture: MicrophoneCapture? {
        guard let microphoneSession, let microphoneOutput else { return nil }
        return MicrophoneCapture(session: microphoneSession, output: microphoneOutput)
    }

    private var activePublishingMicrophoneCapture: MicrophoneCapture? {
        guard let publishingMicrophoneSession, let publishingMicrophoneOutput else { return nil }
        return MicrophoneCapture(session: publishingMicrophoneSession, output: publishingMicrophoneOutput)
    }

    private func isActiveMicrophoneOutput(_ output: AVCaptureOutput) -> Bool {
        microphoneOutput === output || publishingMicrophoneOutput === output
    }

    private func isPublishingMicrophoneOutput(_ output: AVCaptureOutput) -> Bool {
        publishingMicrophoneOutput === output
    }

    private func isRecordingCameraOutput(_ output: AVCaptureOutput) -> Bool {
        recordingCameraOutput === output
    }

    private func isPublishingCameraOutput(_ output: AVCaptureOutput) -> Bool {
        publishingCameraOutput === output
    }

    private func startMicrophoneSessionIfNeeded(_ session: AVCaptureSession?) {
        guard let session,
              Self.shouldProcessMicrophoneAudioSample(configuration: mediaConfiguration),
              !session.isRunning
        else {
            return
        }

        session.startRunning()
    }

    private func startCameraSessionIfNeeded(_ session: AVCaptureSession?) {
        guard let session,
              mediaConfiguration.sceneKind == .screenAndFace,
              !session.isRunning
        else {
            return
        }

        session.startRunning()
    }

    private func applyActivePublishingCameraCaptureState() {
        guard let publishingCameraSession else { return }
        if Self.shouldPublishCompositedVideoSample(sceneKind: mediaConfiguration.sceneKind) {
            startCameraSessionIfNeeded(publishingCameraSession)
        } else if publishingCameraSession.isRunning {
            latestPublishingCameraPixelBuffer = nil
            publishingCameraSession.stopRunning()
        }
    }

    private func startPublishingCameraCaptureIfNeeded(configuration: MediaPipelineConfiguration) async {
        guard Self.shouldPublishCompositedVideoSample(sceneKind: configuration.sceneKind) else { return }
        let shouldCreateCapture = queue.sync {
            publishingStream != nil
                && publishingCameraSession == nil
                && Self.shouldPublishCompositedVideoSample(sceneKind: mediaConfiguration.sceneKind)
        }
        guard shouldCreateCapture,
              let cameraCapture = await makeCameraCaptureIfAvailable(configuration: configuration)
        else {
            return
        }

        let shouldStart = queue.sync {
            guard publishingStream != nil,
                  publishingCameraSession == nil,
                  Self.shouldPublishCompositedVideoSample(sceneKind: mediaConfiguration.sceneKind)
            else {
                return false
            }

            publishingCameraSession = cameraCapture.session
            publishingCameraOutput = cameraCapture.output
            latestPublishingCameraPixelBuffer = nil
            configurePublishingVideoComposition(using: mediaConfiguration)
            return true
        }
        if shouldStart {
            startCameraSession(cameraCapture.session)
        }
    }

    public nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard sampleBuffer.isValid,
              let presentationTime = sampleBuffer.presentationTimeStampIfValid
        else {
            return
        }

        let isPublishingStream = publishingStream === stream
        if isPublishingStream {
            switch outputType {
            case .screen:
                recordVideoSampleIfNeeded(outputType, isPublishingStream: true)
                guard Self.shouldPublishScreenStreamSample(
                    isPublishingStream: isPublishingStream,
                    hasPublisher: rtmpPublisher != nil,
                    hasImageBuffer: sampleBuffer.imageBuffer != nil
                ) else {
                    return
                }
                let didPublish = Self.shouldPublishCompositedVideoSample(sceneKind: mediaConfiguration.sceneKind)
                    ? publishCompositedVideoSample(sampleBuffer, presentationTime: presentationTime)
                    : publish(sampleBuffer)
                if didPublish {
                    markFirstPublishingVideoFrameIfNeeded()
                } else {
                    recordDroppedFrameIfNeeded(outputType)
                }
            case .audio:
                guard Self.shouldProcessSystemAudioSample(configuration: mediaConfiguration),
                      let track = publishingAudioTrackPlan.systemAudio
                else { return }
                if Self.shouldPublishStreamSample(isPublishingStream: isPublishingStream, hasPublisher: rtmpPublisher != nil) {
                    _ = publish(sampleBuffer, track: track)
                }
            case .microphone:
                break
            @unknown default:
                break
            }
            return
        }

        guard Self.shouldProcessRecordingStreamSample(
                  isRecordingStream: self.stream === stream,
                  hasWriter: writer != nil
              ),
              let writer,
              writer.status != .failed,
              writer.status != .cancelled
        else {
            return
        }

        if outputType == .screen, writer.status == .unknown {
            guard writer.startWriting() else {
                recordWriterFailureIfNeeded(status: writer.status, errorDescription: writer.error?.localizedDescription)
                return
            }
            writer.startSession(atSourceTime: presentationTime)
            didStartSession = true
        }

        guard didStartSession, writer.status == .writing else {
            return
        }

        switch outputType {
        case .screen:
            recordVideoSampleIfNeeded(outputType, isPublishingStream: false)
            guard sampleBuffer.imageBuffer != nil,
                  let videoInput,
                  videoInput.isReadyForMoreMediaData
            else {
                recordDroppedFrameIfNeeded(outputType)
                return
            }
            if mediaConfiguration.sceneKind == .screenAndFace {
                guard appendCompositedVideoSample(sampleBuffer, presentationTime: presentationTime) else {
                    recordDroppedFrameIfNeeded(outputType)
                    recordWriterFailureIfNeeded(status: writer.status, errorDescription: writer.error?.localizedDescription)
                    return
                }
                return
            }
            if !videoInput.append(sampleBuffer) {
                recordDroppedFrameIfNeeded(outputType)
                recordWriterFailureIfNeeded(status: writer.status, errorDescription: writer.error?.localizedDescription)
            }
        case .audio:
            guard Self.shouldProcessSystemAudioSample(configuration: mediaConfiguration) else {
                return
            }
            guard let audioInput,
                  audioInput.isReadyForMoreMediaData
            else {
                return
            }
            if !audioInput.append(sampleBuffer) {
                recordWriterFailureIfNeeded(status: writer.status, errorDescription: writer.error?.localizedDescription)
            }
        case .microphone:
            break
        @unknown default:
            break
        }
    }

    private func startRTMPPublisherObservation(for publisher: any RTMPPublisher) {
        let events = publisher.events
        let eventTask = Task { [weak self] in
            for await event in events {
                Self.rtmpLogger.info("RTMP status \(event.statusCode, privacy: .public)")
                self?.handleRTMPPublisherEvent(event, publisher: publisher)
            }
        }
        let healthTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sampleRTMPThroughput(from: publisher)
                try? await Task.sleep(for: .seconds(1))
            }
        }

        queue.sync {
            self.rtmpPublisherEventTask?.cancel()
            self.rtmpPublisherHealthTask?.cancel()
            self.rtmpPublisherEventTask = eventTask
            self.rtmpPublisherHealthTask = healthTask
            self.streamFailureReason = nil
            self.lastRTMPByteCount = nil
            self.lastRTMPByteSampledAt = nil
            self.mediaHealth.publishState = .handshaking
            self.mediaHealth.outboundBytesPerSecond = 0
            self.mediaHealth.bitrateKbps = 0
        }
    }

    private func stopRTMPPublisherObservation() {
        queue.sync {
            self.rtmpPublisherEventTask?.cancel()
            self.rtmpPublisherEventTask = nil
            self.rtmpPublisherHealthTask?.cancel()
            self.rtmpPublisherHealthTask = nil
            self.lastRTMPByteCount = nil
            self.lastRTMPByteSampledAt = nil
            self.mediaHealth.publishState = .disconnected
            self.mediaHealth.outboundBytesPerSecond = 0
            self.mediaHealth.bitrateKbps = 0
        }
    }

    private func handleRTMPPublisherEvent(_ event: RTMPPublisherEvent, publisher: any RTMPPublisher) {
        queue.sync {
            if let publishState = event.publishState {
                self.mediaHealth.publishState = publishState
            }
            guard self.rtmpPublisher === publisher || self.rtmpPublisher == nil else {
                return
            }
            if let failureReason = event.failureReason {
                self.streamFailureReason = failureReason
                self.mediaHealth.publishState = .disconnected
            }
        }
    }

    private func sampleRTMPThroughput(from publisher: any RTMPPublisher) async {
        let byteCount = await publisher.currentByteCount()
        let sampledAt = Date()
        queue.sync {
            guard self.rtmpPublisher === publisher else { return }

            if let previousByteCount = self.lastRTMPByteCount,
               let previousSampledAt = self.lastRTMPByteSampledAt {
                let byteDelta = max(0, byteCount - previousByteCount)
                let elapsed = sampledAt.timeIntervalSince(previousSampledAt)
                let bytesPerSecond = Self.outboundBytesPerSecond(byteDelta: byteDelta, elapsed: elapsed)
                self.mediaHealth.outboundBytesPerSecond = bytesPerSecond
                self.mediaHealth.bitrateKbps = Self.outboundBitrateKbps(bytesPerSecond: bytesPerSecond)
            }

            self.lastRTMPByteCount = byteCount
            self.lastRTMPByteSampledAt = sampledAt
        }
    }

    static func outboundBytesPerSecond(byteDelta: Int64, elapsed: TimeInterval) -> Int64 {
        guard byteDelta > 0, elapsed > 0 else { return 0 }
        return Int64((Double(byteDelta) / elapsed).rounded())
    }

    static func outboundBitrateKbps(bytesPerSecond: Int64) -> Int {
        guard bytesPerSecond > 0 else { return 0 }
        return Int((Double(bytesPerSecond) * 8 / 1_000).rounded())
    }

    private func waitForFirstPublishingVideoFrame() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    self.queue.async {
                        if self.didPublishFirstVideoFrame {
                            continuation.resume()
                        } else {
                            self.firstPublishingVideoContinuation = continuation
                        }
                    }
                }
            }

            group.addTask {
                try await Task.sleep(for: Self.firstPublishingVideoFrameTimeout)
                throw MediaPipelineError.unavailable("RTMP publisher did not receive video frames.")
            }

            do {
                try await group.next()
                group.cancelAll()
            } catch {
                group.cancelAll()
                queue.async {
                    self.firstPublishingVideoContinuation = nil
                }
                throw error
            }
        }
    }

    private func markFirstPublishingVideoFrameIfNeeded() {
        queue.async {
            guard !self.didPublishFirstVideoFrame else { return }
            self.didPublishFirstVideoFrame = true
            self.firstPublishingVideoContinuation?.resume()
            self.firstPublishingVideoContinuation = nil
        }
    }

    private func publish(_ sampleBuffer: CMSampleBuffer, track: UInt8 = 0) -> Bool {
        rtmpPublisher?.append(sampleBuffer, track: track) ?? true
    }

    private func publishCompositedVideoSample(
        _ sampleBuffer: CMSampleBuffer,
        presentationTime: CMTime
    ) -> Bool {
        guard let outputPixelBuffer = makeCompositedPixelBuffer(
            sampleBuffer,
            pixelBufferPool: publishingPixelBufferPool,
            videoCompositor: publishingVideoCompositor,
            cameraPixelBuffer: latestPublishingCameraPixelBuffer
        ) else {
            return false
        }

        let formatDescription: CMVideoFormatDescription
        if let cache = publishingVideoFormatDescriptionCache, cache.matches(outputPixelBuffer) {
            formatDescription = cache.formatDescription
        } else {
            guard let created = Self.makeVideoFormatDescription(for: outputPixelBuffer) else {
                return false
            }
            publishingVideoFormatDescriptionCache = VideoFormatDescriptionCache(
                width: CVPixelBufferGetWidth(outputPixelBuffer),
                height: CVPixelBufferGetHeight(outputPixelBuffer),
                pixelFormat: CVPixelBufferGetPixelFormatType(outputPixelBuffer),
                formatDescription: created
            )
            formatDescription = created
        }

        var timing = CMSampleTimingInfo(
            duration: sampleBuffer.duration.isValid ? sampleBuffer.duration : .invalid,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var compositedSampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: outputPixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &compositedSampleBuffer
        ) == noErr,
              let compositedSampleBuffer
        else {
            return false
        }

        return publish(compositedSampleBuffer)
    }

    private static func makeVideoFormatDescription(
        for pixelBuffer: CVPixelBuffer
    ) -> CMVideoFormatDescription? {
        var formatDescription: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        ) == noErr else {
            return nil
        }
        return formatDescription
    }

    private func appendCompositedVideoSample(
        _ sampleBuffer: CMSampleBuffer,
        presentationTime: CMTime
    ) -> Bool {
        guard let videoInput,
              videoInput.isReadyForMoreMediaData,
              let videoPixelBufferAdaptor,
              let outputPixelBuffer = makeCompositedPixelBuffer(
                sampleBuffer,
                pixelBufferPool: videoPixelBufferAdaptor.pixelBufferPool,
                videoCompositor: videoCompositor,
                cameraPixelBuffer: latestCameraPixelBuffer
              )
        else {
            return false
        }

        return videoPixelBufferAdaptor.append(outputPixelBuffer, withPresentationTime: presentationTime)
    }

    private func makeCompositedPixelBuffer(
        _ sampleBuffer: CMSampleBuffer,
        pixelBufferPool: CVPixelBufferPool?,
        videoCompositor: RecordingVideoCompositor?,
        cameraPixelBuffer: CVPixelBuffer?
    ) -> CVPixelBuffer? {
        guard let screenPixelBuffer = sampleBuffer.imageBuffer,
              let pixelBufferPool,
              let videoCompositor
        else {
            return nil
        }

        var outputPixelBuffer: CVPixelBuffer?
        let creationStatus = CVPixelBufferPoolCreatePixelBuffer(
            nil,
            pixelBufferPool,
            &outputPixelBuffer
        )
        guard creationStatus == kCVReturnSuccess,
              let outputPixelBuffer
        else {
            return nil
        }

        videoCompositor.render(
            screenPixelBuffer: screenPixelBuffer,
            cameraPixelBuffer: cameraPixelBuffer,
            to: outputPixelBuffer
        )
        return outputPixelBuffer
    }

    private func resetHealth(using configuration: MediaPipelineConfiguration) {
        mediaHealth = StreamHealth(
            bitrateKbps: 0,
            publishState: .handshaking,
            captureFPS: 0
        )
        frameWindowStartedAt = Date()
        frameWindowCount = 0
    }

    private func recordVideoSampleIfNeeded(_ outputType: SCStreamOutputType, isPublishingStream: Bool) {
        guard Self.shouldRecordVideoSampleForHealth(
            isScreenOutput: outputType == .screen,
            isPublishingStream: isPublishingStream,
            hasDedicatedPublishingStream: publishingStream != nil
        ) else {
            return
        }

        frameWindowCount += 1
        let now = Date()
        let elapsed = now.timeIntervalSince(frameWindowStartedAt)
        guard elapsed >= 1 else { return }

        mediaHealth.captureFPS = max(1, Int((Double(frameWindowCount) / elapsed).rounded()))
        frameWindowStartedAt = now
        frameWindowCount = 0
    }

    private func recordDroppedFrameIfNeeded(_ outputType: SCStreamOutputType) {
        guard outputType == .screen else { return }

        mediaHealth.droppedFrames += 1
    }

    static func shouldPublishScreenStreamSample(
        isPublishingStream: Bool,
        hasPublisher: Bool,
        hasImageBuffer: Bool
    ) -> Bool {
        hasImageBuffer && shouldPublishStreamSample(
            isPublishingStream: isPublishingStream,
            hasPublisher: hasPublisher
        )
    }

    static func shouldPublishCompositedVideoSample(sceneKind: SceneKind) -> Bool {
        sceneKind == .screenAndFace
    }

    static func shouldRecordVideoSampleForHealth(
        isScreenOutput: Bool,
        isPublishingStream: Bool,
        hasDedicatedPublishingStream: Bool
    ) -> Bool {
        guard isScreenOutput else { return false }
        return isPublishingStream || !hasDedicatedPublishingStream
    }

    static func shouldProcessRecordingStreamSample(
        isRecordingStream: Bool,
        hasWriter: Bool
    ) -> Bool {
        isRecordingStream && hasWriter
    }

    private static func captureSelection(
        from content: SCShareableContent,
        target: ScreenCaptureTarget?,
        maxWidth: Int,
        unavailableReason: String
    ) throws -> ScreenCaptureSelection {
        if target?.kind == .window,
           let window = content.windows.first(where: { "window-\($0.windowID)" == target?.id }) {
            let sourceWidth = max(Int(window.frame.width.rounded()), 1)
            let sourceHeight = max(Int(window.frame.height.rounded()), 1)
            let geometry = MediaCaptureGeometry(
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight,
                maxVideoWidth: maxWidth
            )
            return ScreenCaptureSelection(
                filter: SCContentFilter(desktopIndependentWindow: window),
                geometry: geometry
            )
        }

        let display = content.displays.first { "display-\($0.displayID)" == target?.id } ?? content.displays.first
        guard let display else {
            throw MediaPipelineError.unavailable(unavailableReason)
        }

        let geometry = MediaCaptureGeometry(
            sourceWidth: display.width,
            sourceHeight: display.height,
            maxVideoWidth: maxWidth
        )
        return ScreenCaptureSelection(
            filter: SCContentFilter(display: display, excludingWindows: selfWindows(in: content)),
            geometry: geometry
        )
    }

    private static func selfWindows(in content: SCShareableContent) -> [SCWindow] {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return [] }
        return content.windows.filter { window in
            window.owningApplication?.bundleIdentifier == bundleIdentifier
        }
    }

    static func streamConfiguration(
        geometry: MediaCaptureGeometry,
        mediaConfiguration: MediaPipelineConfiguration
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configureStream(
            configuration,
            geometry: geometry,
            mediaConfiguration: mediaConfiguration
        )
        return configuration
    }

    static func publishingStreamConfiguration(
        geometry: MediaCaptureGeometry,
        mediaConfiguration: MediaPipelineConfiguration
    ) -> SCStreamConfiguration {
        streamConfiguration(
            geometry: geometry,
            mediaConfiguration: publishingCaptureMediaConfiguration(for: mediaConfiguration)
        )
    }

    static func publishingCaptureMediaConfiguration(
        for configuration: MediaPipelineConfiguration
    ) -> MediaPipelineConfiguration {
        var captureConfiguration = configuration
        captureConfiguration.framesPerSecond = min(configuration.framesPerSecond, 30)
        return captureConfiguration
    }

    private static func configureStream(
        _ configuration: SCStreamConfiguration,
        geometry: MediaCaptureGeometry,
        mediaConfiguration: MediaPipelineConfiguration
    ) {
        configuration.width = geometry.width(for: mediaConfiguration.maxVideoWidth)
        configuration.height = geometry.height(for: mediaConfiguration.maxVideoWidth)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(mediaConfiguration.framesPerSecond))
        configuration.queueDepth = mediaConfiguration.queueDepth
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        configuration.capturesAudio = mediaConfiguration.capturesSystemAudio
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
    }

    private func configureRecordingVideoComposition(using configuration: MediaPipelineConfiguration) {
        guard let recordingCaptureGeometry else {
            videoCompositor = nil
            return
        }

        videoCompositor = RecordingVideoCompositor(
            outputWidth: recordingCaptureGeometry.width(for: configuration.maxVideoWidth),
            outputHeight: recordingCaptureGeometry.height(for: configuration.maxVideoWidth),
            cameraEnhancements: configuration.cameraEnhancements,
            layoutSettings: configuration.layoutSettings
        )
    }

    private func updateRecordingVideoComposition(using configuration: MediaPipelineConfiguration) {
        guard videoCompositor != nil else {
            configureRecordingVideoComposition(using: configuration)
            return
        }

        videoCompositor?.update(
            cameraEnhancements: configuration.cameraEnhancements,
            layoutSettings: configuration.layoutSettings
        )
    }

    private func configurePublishingVideoComposition(using configuration: MediaPipelineConfiguration) {
        guard let publishingCaptureGeometry else {
            publishingVideoCompositor = nil
            publishingPixelBufferPool = nil
            publishingVideoFormatDescriptionCache = nil
            return
        }

        let outputWidth = publishingCaptureGeometry.width(for: configuration.maxVideoWidth)
        let outputHeight = publishingCaptureGeometry.height(for: configuration.maxVideoWidth)
        guard let pixelBufferPool = Self.makePixelBufferPool(width: outputWidth, height: outputHeight) else {
            publishingVideoCompositor = nil
            publishingPixelBufferPool = nil
            publishingVideoFormatDescriptionCache = nil
            return
        }

        publishingPixelBufferPool = pixelBufferPool
        publishingVideoFormatDescriptionCache = nil
        publishingVideoCompositor = RecordingVideoCompositor(
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            cameraEnhancements: configuration.cameraEnhancements,
            layoutSettings: configuration.layoutSettings
        )
    }

    private func updatePublishingVideoComposition(using configuration: MediaPipelineConfiguration) {
        guard publishingVideoCompositor != nil else {
            configurePublishingVideoComposition(using: configuration)
            return
        }

        publishingVideoCompositor?.update(
            cameraEnhancements: configuration.cameraEnhancements,
            layoutSettings: configuration.layoutSettings
        )
    }

    static func makePixelBufferPool(width: Int, height: Int) -> CVPixelBufferPool? {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: max(2, width),
            kCVPixelBufferHeightKey as String: max(2, height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            nil,
            attributes as CFDictionary,
            &pool
        )
        guard status == kCVReturnSuccess else { return nil }
        return pool
    }

    private static func cameraSessionPreset(for configuration: MediaPipelineConfiguration) -> AVCaptureSession.Preset {
        if configuration.framesPerSecond <= 24 || configuration.maxVideoWidth <= 1_280 {
            return .medium
        }

        return .high
    }

    private func applyCameraTuning(to device: AVCaptureDevice, configuration: MediaPipelineConfiguration) {
        guard configuration.cameraEnhancements.usesAutoLight else { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
        } catch {
            return
        }
    }

    private static var preferredStreamTransport: StreamTransportKind {
        #if MAC_STREAM_HAS_HAISHINKIT
        .rtmpPublish
        #else
        .endpointValidation
        #endif
    }

    private static func makeRTMPPublisher(target: RTMPPublishTarget) -> any RTMPPublisher {
        #if MAC_STREAM_HAS_HAISHINKIT
        HaishinKitRTMPPublisher(target: target)
        #else
        ConnectivityRTMPPublisher(target: target)
        #endif
    }

    public nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard sampleBuffer.isValid else { return }
        if isRecordingCameraOutput(output) {
            latestCameraPixelBuffer = sampleBuffer.imageBuffer
            return
        }
        if isPublishingCameraOutput(output) {
            latestPublishingCameraPixelBuffer = sampleBuffer.imageBuffer
            return
        }

        guard Self.shouldProcessMicrophoneOutputSample(
            isActiveOutput: isActiveMicrophoneOutput(output),
            configuration: mediaConfiguration
        ) else { return }

        if Self.shouldPublishMicrophoneOutputSample(
            isPublishingOutput: isPublishingMicrophoneOutput(output),
            hasPublisher: rtmpPublisher != nil
        ), let track = publishingAudioTrackPlan.microphone {
            _ = publish(sampleBuffer, track: track)
        }

        guard let writer,
              let microphoneInput,
              didStartSession,
              writer.status == .writing,
              microphoneInput.isReadyForMoreMediaData
        else { return }

        if !microphoneInput.append(sampleBuffer) {
            recordWriterFailureIfNeeded(status: writer.status, errorDescription: writer.error?.localizedDescription)
        }
    }

    static func shouldProcessSystemAudioSample(configuration: MediaPipelineConfiguration) -> Bool {
        configuration.capturesSystemAudio && configuration.systemAudioLevel > 0
    }

    static func shouldProcessMicrophoneAudioSample(configuration: MediaPipelineConfiguration) -> Bool {
        configuration.capturesMicrophone && configuration.microphoneLevel > 0
    }

    static func publishingVideoBitrateCeiling(configuration: MediaPipelineConfiguration) -> Int {
        let width = configuration.maxVideoWidth
        let frameRateFactor = Double(min(configuration.framesPerSecond, 30)) / 30.0
        let widthCeiling: Double

        if width >= 1_920 {
            widthCeiling = 4_000_000
        } else if width >= 1_280 {
            let interpolation = Double(width - 1_280) / Double(1_920 - 1_280)
            widthCeiling = 2_500_000 + (1_500_000 * interpolation)
        } else {
            widthCeiling = 2_500_000 * Double(width) / 1_280
        }

        return Int((widthCeiling * frameRateFactor).rounded(.down))
    }

    static func publishingVideoBitrate(configuration: MediaPipelineConfiguration) -> Int {
        min(configuration.videoBitrate, publishingVideoBitrateCeiling(configuration: configuration))
    }

    static func publishingAudioTrackPlan(
        capturesSystemAudio: Bool,
        capturesMicrophone: Bool
    ) -> (systemAudio: UInt8?, microphone: UInt8?, mainTrack: UInt8) {
        let systemAudioTrack: UInt8? = capturesSystemAudio ? 0 : nil
        let microphoneTrack: UInt8?
        if capturesMicrophone {
            microphoneTrack = capturesSystemAudio ? 1 : 0
        } else {
            microphoneTrack = nil
        }
        let mainTrack = systemAudioTrack ?? microphoneTrack ?? 0
        return (systemAudioTrack, microphoneTrack, mainTrack)
    }

    static func publishingAudioTrackPlan(
        configuration: MediaPipelineConfiguration
    ) -> (systemAudio: UInt8?, microphone: UInt8?, mainTrack: UInt8) {
        publishingAudioTrackPlan(
            capturesSystemAudio: shouldProcessSystemAudioSample(configuration: configuration),
            capturesMicrophone: shouldProcessMicrophoneAudioSample(configuration: configuration)
        )
    }

    static func shouldProcessMicrophoneOutputSample(
        isActiveOutput: Bool,
        configuration: MediaPipelineConfiguration
    ) -> Bool {
        isActiveOutput && shouldProcessMicrophoneAudioSample(configuration: configuration)
    }

    static func shouldPublishStreamSample(
        isPublishingStream: Bool,
        hasPublisher: Bool
    ) -> Bool {
        isPublishingStream && hasPublisher
    }

    static func shouldPublishMicrophoneOutputSample(
        isPublishingOutput: Bool,
        hasPublisher: Bool
    ) -> Bool {
        isPublishingOutput && hasPublisher
    }

    static func shouldUpdateActiveStreamConfiguration(
        from previous: MediaPipelineConfiguration,
        to next: MediaPipelineConfiguration
    ) -> Bool {
        previous.maxVideoWidth != next.maxVideoWidth
            || previous.framesPerSecond != next.framesPerSecond
            || previous.queueDepth != next.queueDepth
            || previous.sceneKind != next.sceneKind
            || previous.capturesSystemAudio != next.capturesSystemAudio
            || previous.cameraEnhancements != next.cameraEnhancements
            || previous.screenCaptureTarget != next.screenCaptureTarget
    }
}

private struct PublishingCaptureState {
    var stream: SCStream?
    var microphoneSession: AVCaptureSession?
    var cameraSession: AVCaptureSession?
    var shouldStopMicrophoneSession: Bool
    var publisher: (any RTMPPublisher)?
}

private struct RecordingWriterState {
    var stream: SCStream?
    var microphoneSession: AVCaptureSession?
    var recordingCameraSession: AVCaptureSession?
    var writer: AVAssetWriter?
    var videoInput: AVAssetWriterInput?
    var audioInput: AVAssetWriterInput?
    var microphoneInput: AVAssetWriterInput?
    var shouldStopMicrophoneSession: Bool
}

private struct SendableAssetWriter: @unchecked Sendable {
    private let writer: AVAssetWriter

    init(_ writer: AVAssetWriter) {
        self.writer = writer
    }

    var status: AVAssetWriter.Status {
        writer.status
    }

    var errorDescription: String? {
        writer.error?.localizedDescription
    }
}

private struct MicrophoneCapture {
    var session: AVCaptureSession
    var output: AVCaptureAudioDataOutput
}

private struct CameraCapture {
    var session: AVCaptureSession
    var output: AVCaptureVideoDataOutput
}

private struct VideoFormatDescriptionCache {
    var width: Int
    var height: Int
    var pixelFormat: OSType
    var formatDescription: CMVideoFormatDescription

    func matches(_ pixelBuffer: CVPixelBuffer) -> Bool {
        width == CVPixelBufferGetWidth(pixelBuffer)
            && height == CVPixelBufferGetHeight(pixelBuffer)
            && pixelFormat == CVPixelBufferGetPixelFormatType(pixelBuffer)
    }
}

private final class RecordingVideoCompositor {
    private let context = CIContext()
    private let outputRect: CGRect
    private var cameraEnhancements: CameraEnhancementSettings
    private var layoutSettings: StudioLayoutSettings
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var background: CIImage
    private lazy var colorControlsFilter: CIFilter? = CIFilter(name: "CIColorControls")

    init(
        outputWidth: Int,
        outputHeight: Int,
        cameraEnhancements: CameraEnhancementSettings,
        layoutSettings: StudioLayoutSettings
    ) {
        let outputRect = CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight)
        self.outputRect = outputRect
        self.cameraEnhancements = cameraEnhancements
        self.layoutSettings = layoutSettings
        self.background = CIImage(color: Self.backgroundColor(for: layoutSettings.backgroundStyle))
            .cropped(to: outputRect)
    }

    func update(
        cameraEnhancements: CameraEnhancementSettings,
        layoutSettings: StudioLayoutSettings
    ) {
        let shouldUpdateBackground = self.layoutSettings.backgroundStyle != layoutSettings.backgroundStyle
        self.cameraEnhancements = cameraEnhancements
        self.layoutSettings = layoutSettings
        if shouldUpdateBackground {
            background = CIImage(color: Self.backgroundColor(for: layoutSettings.backgroundStyle))
                .cropped(to: outputRect)
        }
    }

    func render(
        screenPixelBuffer: CVPixelBuffer,
        cameraPixelBuffer: CVPixelBuffer?,
        to outputPixelBuffer: CVPixelBuffer
    ) {
        let screenImage = normalized(CIImage(cvPixelBuffer: screenPixelBuffer))
        let cameraImage = cameraPixelBuffer.map { enhancedCameraImage(from: $0) }
        let canvasLayout = StudioCanvasLayout(size: outputRect.size, settings: layoutSettings)
        var composed = background

        if layoutSettings.preset.isSplit {
            let screenRect = canvasLayout.splitScreenRect.integral
            let webcamRect = canvasLayout.splitWebcamRect.integral
            composed = renderSource(screenImage, in: screenRect, zoom: layoutSettings.screenZoom)
                .composited(over: composed)
            composed = renderCamera(cameraImage, in: webcamRect)
                .composited(over: composed)
        } else {
            composed = renderSource(screenImage, in: canvasLayout.contentRect.integral, zoom: layoutSettings.screenZoom)
                .composited(over: composed)
            composed = renderCamera(cameraImage, in: canvasLayout.pictureInPictureRect.integral)
                .composited(over: composed)
        }

        context.render(
            composed.cropped(to: outputRect),
            to: outputPixelBuffer,
            bounds: outputRect,
            colorSpace: colorSpace
        )
    }

    private func renderCamera(_ cameraImage: CIImage?, in targetRect: CGRect) -> CIImage {
        guard let cameraImage else {
            return CIImage(color: CIColor(red: 0.02, green: 0.02, blue: 0.02))
                .cropped(to: targetRect)
        }

        return renderSource(cameraImage, in: targetRect, zoom: layoutSettings.webcamZoom)
    }

    private func renderSource(_ image: CIImage, in targetRect: CGRect, zoom: Double) -> CIImage {
        let targetRect = targetRect.integral
        guard !targetRect.isEmpty else {
            return CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: targetRect)
        }

        let normalizedZoom = StudioLayoutSettings.normalizedSourceZoom(zoom)
        let filledImage = aspectFill(image, in: targetRect)
        let transform = CGAffineTransform(translationX: targetRect.midX, y: targetRect.midY)
            .scaledBy(x: normalizedZoom, y: normalizedZoom)
            .translatedBy(x: -targetRect.midX, y: -targetRect.midY)
        return filledImage
            .transformed(by: transform)
            .cropped(to: targetRect)
    }

    private static func backgroundColor(for style: StudioBackgroundStyle) -> CIColor {
        switch style {
        case .black:
            CIColor(red: 0, green: 0, blue: 0)
        case .studio:
            CIColor(red: 0.06, green: 0.07, blue: 0.10)
        case .stage:
            CIColor(red: 0.08, green: 0.02, blue: 0.04)
        case .warm:
            CIColor(red: 0.14, green: 0.10, blue: 0.06)
        }
    }

    private func enhancedCameraImage(from pixelBuffer: CVPixelBuffer) -> CIImage {
        var image = normalized(CIImage(cvPixelBuffer: pixelBuffer))

        if cameraEnhancements.mirrorsPreview {
            image = image.transformed(by: CGAffineTransform(scaleX: -1, y: 1))
            image = normalized(image)
        }

        if cameraEnhancements.rotation != .degrees0 {
            image = image.transformed(by: CGAffineTransform(rotationAngle: cameraEnhancements.rotation.radians))
            image = normalized(image)
        }

        guard cameraEnhancements.usesAutoLight,
              let filter = colorControlsFilter
        else {
            return image
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(cameraEnhancements.autoLightAmount * 0.18, forKey: kCIInputBrightnessKey)
        filter.setValue(1 + cameraEnhancements.autoLightAmount * 0.08, forKey: kCIInputContrastKey)
        filter.setValue(1 + cameraEnhancements.autoLightAmount * 0.10, forKey: kCIInputSaturationKey)
        let outputImage = filter.outputImage.map(normalized) ?? image
        filter.setValue(nil, forKey: kCIInputImageKey)
        return outputImage
    }

    private func aspectFill(_ image: CIImage, in targetRect: CGRect) -> CIImage {
        guard !image.extent.isEmpty,
              targetRect.width > 0,
              targetRect.height > 0
        else {
            return CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: targetRect)
        }

        let scale = max(
            targetRect.width / image.extent.width,
            targetRect.height / image.extent.height
        )
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let translation = CGAffineTransform(
            translationX: targetRect.midX - scaled.extent.midX,
            y: targetRect.midY - scaled.extent.midY
        )
        return scaled
            .transformed(by: translation)
            .cropped(to: targetRect)
    }

    private func normalized(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(
            translationX: -image.extent.minX,
            y: -image.extent.minY
        ))
    }

}

private struct ActiveStreamConfigurationUpdate {
    var stream: SCStream
    var configuration: SCStreamConfiguration
}

struct MediaCaptureGeometry: Equatable, Sendable {
    var sourceWidth: Int
    var sourceHeight: Int
    var maxVideoWidth: Int

    init(sourceWidth: Int, sourceHeight: Int, maxVideoWidth: Int) {
        self.sourceWidth = max(1, sourceWidth)
        self.sourceHeight = max(1, sourceHeight)
        self.maxVideoWidth = max(320, maxVideoWidth)
    }

    func width(for updatedMaxVideoWidth: Int? = nil) -> Int {
        Self.evenDimension(min(sourceWidth, max(320, updatedMaxVideoWidth ?? maxVideoWidth)))
    }

    func height(for updatedMaxVideoWidth: Int? = nil) -> Int {
        Self.evenDimension(Int(Double(width(for: updatedMaxVideoWidth)) * Double(sourceHeight) / Double(sourceWidth)))
    }

    private static func evenDimension(_ value: Int) -> Int {
        let boundedValue = max(2, value)
        return boundedValue.isMultiple(of: 2) ? boundedValue : boundedValue - 1
    }
}

private struct ScreenCaptureSelection {
    var filter: SCContentFilter
    var geometry: MediaCaptureGeometry
}

private extension CMSampleBuffer {
    var presentationTimeStampIfValid: CMTime? {
        let time = presentationTimeStamp
        return time.isValid && !time.isIndefinite ? time : nil
    }
}

enum RTMPPublisherEvent: Equatable, Sendable {
    case connectionStatus(code: String, level: String)
    case streamStatus(code: String, level: String)

    var statusCode: String {
        switch self {
        case let .connectionStatus(code, _), let .streamStatus(code, _):
            code
        }
    }

    var publishState: RTMPPublishState? {
        switch statusCode {
        case "NetConnection.Connect.Success":
            .handshaking
        case "NetStream.Publish.Start":
            .publishing
        case "NetConnection.Connect.Closed",
             "NetConnection.Connect.Failed",
             "NetStream.Publish.BadName",
             "NetStream.Unpublish.Success":
            .disconnected
        default:
            nil
        }
    }

    var failureReason: String? {
        switch statusCode {
        case "NetConnection.Connect.Closed":
            "RTMP connection closed by the server."
        case "NetConnection.Connect.Failed":
            "RTMP connection failed."
        case "NetStream.Publish.BadName":
            "RTMP publish was rejected because the stream name or key is invalid."
        case "NetStream.Unpublish.Success":
            "RTMP publishing was unpublished by the server."
        default:
            nil
        }
    }
}

protocol RTMPPublisher: AnyObject, Sendable {
    var events: AsyncStream<RTMPPublisherEvent> { get }

    func configure(configuration: MediaPipelineConfiguration) async throws
    func connect() async throws
    func append(_ sampleBuffer: CMSampleBuffer, track: UInt8) -> Bool
    func currentByteCount() async -> Int64
    func close() async
}

extension RTMPPublisher {
    var events: AsyncStream<RTMPPublisherEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func configure(configuration: MediaPipelineConfiguration) async throws {}

    func append(_ sampleBuffer: CMSampleBuffer) -> Bool {
        append(sampleBuffer, track: 0)
    }

    func currentByteCount() async -> Int64 { 0 }
}

final class RTMPAppendBackpressureGate: @unchecked Sendable {
    private let lock = NSLock()
    private let maxPendingAppends: Int
    private var pendingAppends = 0

    init(maxPendingAppends: Int = 3) {
        self.maxPendingAppends = max(1, maxPendingAppends)
    }

    func tryBeginAppend() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard pendingAppends < maxPendingAppends else { return false }
        pendingAppends += 1
        return true
    }

    func finishAppend() {
        lock.lock()
        pendingAppends = max(0, pendingAppends - 1)
        lock.unlock()
    }
}

final class OrderedMediaAppendQueue<Element: Sendable>: @unchecked Sendable {
    typealias Handler = @Sendable (Element) async -> Void

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        let gate: RTMPAppendBackpressureGate
        var isClosed = false

        init(maxPendingAppends: Int) {
            self.gate = RTMPAppendBackpressureGate(maxPendingAppends: maxPendingAppends)
        }

        var hasStartedClose: Bool {
            lock.lock()
            defer { lock.unlock() }
            return isClosed
        }

        func startClose() -> Bool {
            lock.lock()
            defer { lock.unlock() }

            guard !isClosed else { return false }
            isClosed = true
            return true
        }
    }

    private let state: State
    private let continuation: AsyncStream<Element>.Continuation
    private let consumerTask: Task<Void, Never>

    init(maxPendingAppends: Int = 3, handler: @escaping Handler) {
        let state = State(maxPendingAppends: maxPendingAppends)
        let streamAndContinuation = AsyncStream<Element>.makeStream(
            of: Element.self,
            bufferingPolicy: .unbounded
        )

        self.state = state
        self.continuation = streamAndContinuation.continuation
        self.consumerTask = Task {
            for await item in streamAndContinuation.stream {
                await handler(item)
                state.gate.finishAppend()
            }
        }
    }

    func enqueue(_ item: Element) -> Bool {
        state.lock.lock()
        defer { state.lock.unlock() }

        guard !state.isClosed, state.gate.tryBeginAppend() else {
            return false
        }

        switch continuation.yield(item) {
        case .enqueued:
            return true
        case .dropped, .terminated:
            state.gate.finishAppend()
            return false
        @unknown default:
            state.gate.finishAppend()
            return false
        }
    }

    var isClosed: Bool {
        state.hasStartedClose
    }

    func closeAndWait() async {
        if state.startClose() {
            continuation.finish()
        }
        await consumerTask.value
    }
}

#if MAC_STREAM_HAS_HAISHINKIT
private final class HaishinKitRTMPPublisher: RTMPPublisher, @unchecked Sendable {
    private let target: RTMPPublishTarget
    private let connection = RTMPConnection(
        fourCcList: nil,
        videoFourCcInfoMap: nil,
        audioFourCcInfoMap: nil,
        capsEx: 0
    )
    private let stream: RTMPStream
    private let mixer = MediaMixer(captureSessionMode: .manual, multiTrackAudioMixingEnabled: true)
    private let eventStream: AsyncStream<RTMPPublisherEvent>
    private let eventContinuation: AsyncStream<RTMPPublisherEvent>.Continuation
    private var statusTasks: [Task<Void, Never>] = []

    private struct PendingMediaAppend: @unchecked Sendable {
        var sampleBuffer: CMSampleBuffer
        var track: UInt8
    }

    private lazy var appendQueue = OrderedMediaAppendQueue<PendingMediaAppend> { [mixer = self.mixer] pending in
        await mixer.append(pending.sampleBuffer, track: pending.track)
    }

    init(target: RTMPPublishTarget) {
        self.target = target
        let events = AsyncStream.makeStream(
            of: RTMPPublisherEvent.self,
            bufferingPolicy: .unbounded
        )
        self.eventStream = events.stream
        self.eventContinuation = events.continuation
        self.stream = RTMPStream(connection: connection, fcPublishName: target.streamName)
    }

    var events: AsyncStream<RTMPPublisherEvent> {
        eventStream
    }


    func configure(configuration: MediaPipelineConfiguration) async throws {
        let videoWidth = configuration.maxVideoWidth
        let videoHeight = Int((Double(videoWidth) * 9.0 / 16.0).rounded())
        let videoBitrate = SystemMediaPipeline.publishingVideoBitrate(configuration: configuration)
        try await stream.setVideoSettings(VideoCodecSettings(
            videoSize: CGSize(width: videoWidth, height: videoHeight),
            bitRate: videoBitrate,
            profileLevel: kVTProfileLevel_H264_Baseline_AutoLevel as String,
            scalingMode: .letterbox,
            bitRateMode: .average,
            maxKeyFrameIntervalDuration: 2,
            allowFrameReordering: false,
            dataRateLimits: [Double(videoBitrate) / 8, 1.0],
            isLowLatencyRateControlEnabled: true,
            isHardwareAcceleratedEnabled: true,
            expectedFrameRate: Double(configuration.framesPerSecond)
        ))
        try await stream.setAudioSettings(AudioCodecSettings(
            bitRate: 128_000,
            downmix: true,
            sampleRate: 48_000,
            format: .aac
        ))
        await stream.setVideoInputBufferCounts(configuration.queueDepth)

        var videoMixerSettings = await mixer.videoMixerSettings
        videoMixerSettings.mode = .passthrough
        videoMixerSettings.mainTrack = 0
        await mixer.setVideoMixerSettings(videoMixerSettings)

        let audioTrackPlan = SystemMediaPipeline.publishingAudioTrackPlan(configuration: configuration)
        var audioMixerSettings = AudioMixerSettings(sampleRate: 48_000, channels: 2)
        audioMixerSettings.mainTrack = audioTrackPlan.mainTrack
        if let systemAudioTrack = audioTrackPlan.systemAudio {
            audioMixerSettings.tracks[systemAudioTrack] = .default
        }
        if let microphoneTrack = audioTrackPlan.microphone {
            audioMixerSettings.tracks[microphoneTrack] = .default
        }
        await mixer.setAudioMixerSettings(audioMixerSettings)
        await mixer.addOutput(stream)
        await mixer.startRunning()
    }

    func connect() async throws {
        let connectionStatus = await connection.status
        let streamStatus = await stream.status
        startStatusTasks(connectionStatus: connectionStatus, streamStatus: streamStatus)
        _ = try await connection.connect(target.connectionURL)
        _ = try await stream.publish(target.streamName, type: .live)
    }

    func append(_ sampleBuffer: CMSampleBuffer, track: UInt8) -> Bool {
        appendQueue.enqueue(PendingMediaAppend(sampleBuffer: sampleBuffer, track: track))
    }
    func currentByteCount() async -> Int64 {
        await Int64(stream.info.byteCount)
    }

    private func startStatusTasks(
        connectionStatus: AsyncStream<RTMPStatus>,
        streamStatus: AsyncStream<RTMPStatus>
    ) {
        guard statusTasks.isEmpty else { return }
        statusTasks = [
            Task { [eventContinuation] in
                for await status in connectionStatus {
                    eventContinuation.yield(.connectionStatus(code: status.code, level: status.level))
                }
            },
            Task { [eventContinuation] in
                for await status in streamStatus {
                    eventContinuation.yield(.streamStatus(code: status.code, level: status.level))
                }
            }
        ]
    }


    func close() async {
        await appendQueue.closeAndWait()
        statusTasks.forEach { $0.cancel() }
        statusTasks.removeAll()
        await mixer.removeOutput(stream)
        await mixer.stopRunning()
        _ = try? await stream.close()
        _ = try? await connection.close()
        eventContinuation.finish()
    }
}
#endif

private final class ConnectivityRTMPPublisher: RTMPPublisher, @unchecked Sendable {
    private let target: RTMPPublishTarget
    private let timeout: TimeInterval
    private let connectionQueue = DispatchQueue(label: "com.macstream.rtmp.connect", qos: .userInitiated)
    private var connection: NWConnection?

    init(target: RTMPPublishTarget, timeout: TimeInterval = 5) {
        self.target = target
        self.timeout = timeout
    }

    func connect() async throws {
        let endpoint = try target.networkEndpoint()
        let connection = NWConnection(host: endpoint.host, port: endpoint.port, using: endpoint.parameters)
        let cancellation = RTMPConnectionCancellationBox()
        self.connection = connection

        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    let box = ConnectionContinuationBox(continuation)
                    let timeout = timeout

                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            box.resume(.success(()))
                        case let .failed(error):
                            box.resume(.failure(error))
                        case .cancelled:
                            box.resume(.failure(MediaPipelineError.unavailable("RTMP connection was cancelled.")))
                        default:
                            break
                        }
                    }
                    guard cancellation.install(connection: connection, continuation: box) else {
                        return
                    }
                    connectionQueue.asyncAfter(deadline: .now() + timeout) {
                        if box.resume(.failure(MediaPipelineError.connectionTimedOut(timeout))) {
                            connection.cancel()
                        }
                    }
                    connection.start(queue: connectionQueue)
                }
            } onCancel: {
                cancellation.cancel()
            }
            cancellation.clear()
        } catch {
            cancellation.cancel()
            connection.cancel()
            self.connection = nil
            throw error
        }
    }

    func append(_ sampleBuffer: CMSampleBuffer, track: UInt8) -> Bool {
        // This adapter intentionally only proves RTMP endpoint reachability.
        // Full RTMP mux/publish is isolated behind RTMPPublisher.
        true
    }

    func close() async {
        connection?.cancel()
        connection = nil
    }
}

final class RTMPConnectionCancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var connection: NWConnection?
    private var continuation: ConnectionContinuationBox?
    private var isCancelled = false

    func install(connection: NWConnection, continuation: ConnectionContinuationBox) -> Bool {
        lock.lock()
        if isCancelled {
            lock.unlock()
            connection.cancel()
            continuation.resume(.failure(CancellationError()))
            return false
        }

        self.connection = connection
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let connection = connection
        let continuation = continuation
        self.connection = nil
        self.continuation = nil
        lock.unlock()

        connection?.cancel()
        continuation?.resume(.failure(CancellationError()))
    }

    func clear() {
        lock.lock()
        connection = nil
        continuation = nil
        lock.unlock()
    }
}

final class ConnectionContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?

    init(_ continuation: CheckedContinuation<Void, any Error>) {
        self.continuation = continuation
    }

    @discardableResult
    func resume(_ result: Result<Void, any Error>) -> Bool {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        guard let continuation else { return false }

        switch result {
        case .success:
            continuation.resume()
        case let .failure(error):
            continuation.resume(throwing: error)
        }

        return true
    }
}

private struct RTMPNetworkEndpoint: Sendable {
    var host: NWEndpoint.Host
    var port: NWEndpoint.Port
    var parameters: NWParameters
}

private extension RTMPPublishTarget {
    func networkEndpoint() throws -> RTMPNetworkEndpoint {
        guard let components = URLComponents(string: connectionURL),
              let host = components.host,
              let scheme = components.scheme?.lowercased()
        else {
            throw MediaPipelineError.unavailable("Cannot parse RTMP endpoint.")
        }

        let defaultPort: UInt16 = scheme == "rtmps" ? 443 : 1935
        let port = NWEndpoint.Port(rawValue: UInt16(components.port ?? Int(defaultPort))) ?? .rtmp
        let parameters: NWParameters = scheme == "rtmps" ? .tls : .tcp

        return RTMPNetworkEndpoint(
            host: NWEndpoint.Host(host),
            port: port,
            parameters: parameters
        )
    }
}

private extension NWEndpoint.Port {
    static let rtmp = NWEndpoint.Port(rawValue: 1935)!
}
