import Foundation
@preconcurrency import AVFoundation
import CoreGraphics
@preconcurrency import CoreMedia
import Network
@preconcurrency import ScreenCaptureKit
#if OPEN_CUE_HAS_HAISHINKIT
import HaishinKit
import RTMPHaishinKit
#endif

public protocol MediaPipeline: Sendable {
    var streamTransport: StreamTransportKind { get }
    var currentHealth: StreamHealth? { get }
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

public struct StreamDestination: Equatable, Sendable {
    public var mode: StreamDestinationMode
    public var name: String
    public var rtmpURL: String

    public init(
        mode: StreamDestinationMode? = nil,
        name: String = "Preview Session",
        rtmpURL: String = "preview"
    ) {
        self.mode = mode ?? Self.inferMode(from: rtmpURL)
        self.name = name
        self.rtmpURL = rtmpURL
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

    public var safeDisplayDetail: String {
        guard !isPreviewSession else {
            return "Local preview session"
        }

        guard let target = try? rtmpPublishTarget() else {
            return "Invalid RTMP endpoint"
        }

        return "\(target.connectionURL)/****"
    }

    public var usesPreviewSentinelURL: Bool {
        let trimmed = rtmpURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let lowered = trimmed.lowercased()
        if lowered == "preview" || lowered == "opencue-preview" {
            return true
        }

        return URLComponents(string: trimmed)?.scheme?.lowercased() == "opencue-preview"
    }

    public func rtmpPublishTarget() throws -> RTMPPublishTarget {
        guard !isPreviewSession else {
            throw MediaPipelineError.unavailable("Enter an RTMP or RTMPS URL to publish.")
        }

        guard let components = URLComponents(string: rtmpURL),
              let scheme = components.scheme?.lowercased(),
              scheme == "rtmp" || scheme == "rtmps",
              let host = components.host,
              !host.isEmpty
        else {
            throw MediaPipelineError.unavailable("Enter a valid RTMP or RTMPS URL.")
        }

        let pathParts = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard pathParts.count >= 2, let rawStreamName = pathParts.last, !rawStreamName.isEmpty else {
            throw MediaPipelineError.unavailable("RTMP URL must include an app path and stream key.")
        }

        var streamName = rawStreamName
        if let query = components.percentEncodedQuery, !query.isEmpty {
            streamName += "?\(query)"
        }
        if let fragment = components.percentEncodedFragment, !fragment.isEmpty {
            streamName += "#\(fragment)"
        }

        var connectionComponents = components
        connectionComponents.path = "/" + pathParts.dropLast().joined(separator: "/")
        connectionComponents.query = nil
        connectionComponents.fragment = nil

        guard let connectionURL = connectionComponents.string else {
            throw MediaPipelineError.unavailable("Cannot build RTMP connection URL.")
        }

        return RTMPPublishTarget(connectionURL: connectionURL, streamName: streamName)
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
            .appendingPathComponent("OpenCue-preview.mov")
    }

    public func stopRecording() async {
    }
}

public final class SystemMediaPipeline: NSObject, MediaPipeline, SCStreamOutput, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.opencue.media.recording", qos: .userInitiated)
    private let rtmpPublisherFactory: @Sendable (RTMPPublishTarget) -> any RTMPPublisher
    private var mediaConfiguration = MediaPipelineConfiguration()
    private var stream: SCStream?
    private var publishingStream: SCStream?
    private var recordingCaptureGeometry: MediaCaptureGeometry?
    private var publishingCaptureGeometry: MediaCaptureGeometry?
    private var microphoneSession: AVCaptureSession?
    private var publishingMicrophoneSession: AVCaptureSession?
    private var microphoneOutput: AVCaptureAudioDataOutput?
    private var publishingMicrophoneOutput: AVCaptureAudioDataOutput?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?
    private var rtmpPublisher: RTMPPublisher?
    private var didStartSession = false
    private var currentURL: URL?
    private var publishingOwnsMicrophoneSession = false
    private var recordingUsesPublishingMicrophoneSession = false
    private var mediaHealth = StreamHealth()
    private var frameWindowStartedAt = Date()
    private var frameWindowCount = 0

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
        Self.capturesMediaForStreamTransport ? [.screenOnly] : Set(SceneKind.allCases)
    }

    public var supportedSceneKindsForRecording: Set<SceneKind> {
        [.screenOnly]
    }

    static var capturesMediaForStreamTransport: Bool {
        #if OPEN_CUE_HAS_HAISHINKIT
        true
        #else
        false
        #endif
    }

    static let sharesMicrophoneCaptureBetweenStreamAndRecording = true

    public func update(configuration: MediaPipelineConfiguration) {
        let streamUpdates: [ActiveStreamConfigurationUpdate] = queue.sync {
            let previousConfiguration = self.mediaConfiguration
            self.mediaConfiguration = configuration
            guard Self.shouldUpdateActiveStreamConfiguration(
                from: previousConfiguration,
                to: configuration
            ) else {
                return []
            }
            return self.activeStreamConfigurationUpdates(for: configuration)
        }
        queue.async {
            self.applyActiveMicrophoneCaptureState()
        }
        for update in streamUpdates {
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
            await publisher.close()
            throw error
        }
    }

    public func stopStream() async {
        let state = queue.sync {
            let publisher = rtmpPublisher
            let stream = publishingStream
            let microphoneSession = publishingMicrophoneSession
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
            publishingStream = nil
            publishingCaptureGeometry = nil
            publishingMicrophoneSession = nil
            publishingMicrophoneOutput = nil
            publishingOwnsMicrophoneSession = false
            if self.stream == nil, self.writer == nil {
                self.mediaHealth = StreamHealth()
            }
            return PublishingCaptureState(
                stream: stream,
                microphoneSession: microphoneSession,
                shouldStopMicrophoneSession: shouldStopMicrophoneSession,
                publisher: publisher
            )
        }

        try? await state.stream?.stopCapture()
        if state.shouldStopMicrophoneSession, state.microphoneSession?.isRunning == true {
            state.microphoneSession?.stopRunning()
        }
        await state.publisher?.close()
    }

    public func startRecording() async throws -> URL {
        if await isRecording {
            throw MediaPipelineError.alreadyRecording
        }

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
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: selection.geometry.width(for: mediaConfiguration.maxVideoWidth),
                AVVideoHeightKey: selection.geometry.height(for: mediaConfiguration.maxVideoWidth),
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
            : (mediaConfiguration.capturesMicrophone ? await makeMicrophoneCaptureIfAvailable() : nil)
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
                microphoneInput = nil
            }
        } else {
            microphoneInput = nil
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
            try? stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
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
            self.audioInput = audioInput
            self.microphoneInput = microphoneInput
            self.microphoneSession = microphoneCapture?.session
            self.microphoneOutput = microphoneCapture?.output
            self.recordingUsesPublishingMicrophoneSession = usesPublishingMicrophoneSession
            self.didStartSession = false
            self.currentURL = outputURL
            self.resetHealth(using: mediaConfiguration)
        }

        do {
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
            let writer = writer
            let videoInput = videoInput
            let audioInput = audioInput
            let microphoneInput = microphoneInput
            let publishingUsesRecordingMicrophone = microphoneSession != nil && publishingMicrophoneSession === microphoneSession
            self.stream = nil
            self.recordingCaptureGeometry = nil
            self.microphoneSession = nil
            self.microphoneOutput = nil
            self.writer = nil
            self.videoInput = nil
            self.audioInput = nil
            self.microphoneInput = nil
            recordingUsesPublishingMicrophoneSession = false
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
            state.videoInput?.markAsFinished()
            state.audioInput?.markAsFinished()
            state.microphoneInput?.markAsFinished()

            guard let writer = state.writer else {
                continuation.resume()
                return
            }

            if writer.status == .writing {
                writer.finishWriting {
                    continuation.resume()
                }
                return
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

    private var isRecording: Bool {
        get async {
            queue.sync { stream != nil || writer != nil }
        }
    }

    private func makeRecordingURL() throws -> URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        let directory = (movies ?? FileManager.default.temporaryDirectory).appendingPathComponent("OpenCue", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return OpenCueArtifactFileNamer.uniqueURL(
            in: directory,
            prefix: "OpenCue",
            fileExtension: "mov"
        )
    }

    private func makeMicrophoneCaptureIfAvailable() async -> MicrophoneCapture? {
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
              let device = AVCaptureDevice.default(for: .audio),
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
        let configuration = SCStreamConfiguration()
        Self.configureStream(
            configuration,
            geometry: selection.geometry,
            mediaConfiguration: mediaConfiguration
        )

        let stream = SCStream(filter: selection.filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if mediaConfiguration.capturesSystemAudio {
            try? stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
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
            let microphoneCapture = await makeMicrophoneCaptureIfAvailable()
            microphoneSession = microphoneCapture?.session
            microphoneOutput = microphoneCapture?.output
            ownsMicrophoneSession = microphoneCapture != nil
        } else {
            microphoneSession = nil
            microphoneOutput = nil
            ownsMicrophoneSession = false
        }

        try Task.checkCancellation()

        queue.sync {
            self.publishingStream = stream
            self.publishingCaptureGeometry = selection.geometry
            self.publishingMicrophoneSession = microphoneSession
            self.publishingMicrophoneOutput = microphoneOutput
            self.publishingOwnsMicrophoneSession = ownsMicrophoneSession
            self.resetHealth(using: mediaConfiguration)
        }

        do {
            try await stream.startCapture()
            try Task.checkCancellation()
            startMicrophoneSession(microphoneSession)
        } catch {
            queue.sync {
                if self.publishingStream === stream {
                    self.publishingStream = nil
                    self.publishingCaptureGeometry = nil
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
            throw error
        }
    }

    private func startMicrophoneSession(_ session: AVCaptureSession?) {
        queue.async {
            self.startMicrophoneSessionIfNeeded(session)
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
                configuration: Self.streamConfiguration(
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

    private func startMicrophoneSessionIfNeeded(_ session: AVCaptureSession?) {
        guard let session,
              Self.shouldProcessMicrophoneAudioSample(configuration: mediaConfiguration),
              !session.isRunning
        else {
            return
        }

        session.startRunning()
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
                if Self.shouldPublishStreamSample(isPublishingStream: isPublishingStream, hasPublisher: rtmpPublisher != nil),
                   !publish(sampleBuffer) {
                    recordDroppedFrameIfNeeded(outputType)
                }
            case .audio:
                guard Self.shouldProcessSystemAudioSample(configuration: mediaConfiguration) else { return }
                if Self.shouldPublishStreamSample(isPublishingStream: isPublishingStream, hasPublisher: rtmpPublisher != nil) {
                    _ = publish(sampleBuffer)
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
            guard writer.startWriting() else { return }
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
            videoInput.append(sampleBuffer)
        case .audio:
            guard Self.shouldProcessSystemAudioSample(configuration: mediaConfiguration) else {
                return
            }
            guard let audioInput,
                  audioInput.isReadyForMoreMediaData
            else {
                return
            }
            audioInput.append(sampleBuffer)
        case .microphone:
            break
        @unknown default:
            break
        }
    }

    private func publish(_ sampleBuffer: CMSampleBuffer) -> Bool {
        rtmpPublisher?.append(sampleBuffer) ?? true
    }

    private func resetHealth(using configuration: MediaPipelineConfiguration) {
        mediaHealth = StreamHealth(
            bitrateKbps: configuration.videoBitrate / 1_000,
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
            filter: SCContentFilter(display: display, excludingWindows: []),
            geometry: geometry
        )
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

    private static var preferredStreamTransport: StreamTransportKind {
        #if OPEN_CUE_HAS_HAISHINKIT
        .rtmpPublish
        #else
        .endpointValidation
        #endif
    }

    private static func makeRTMPPublisher(target: RTMPPublishTarget) -> any RTMPPublisher {
        #if OPEN_CUE_HAS_HAISHINKIT
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
        guard Self.shouldProcessMicrophoneOutputSample(
            isActiveOutput: isActiveMicrophoneOutput(output),
            configuration: mediaConfiguration
        ) else { return }

        if Self.shouldPublishMicrophoneOutputSample(
            isPublishingOutput: isPublishingMicrophoneOutput(output),
            hasPublisher: rtmpPublisher != nil
        ) {
            _ = publish(sampleBuffer)
        }

        guard let writer,
              let microphoneInput,
              didStartSession,
              writer.status == .writing,
              microphoneInput.isReadyForMoreMediaData
        else { return }

        microphoneInput.append(sampleBuffer)
    }

    static func shouldProcessSystemAudioSample(configuration: MediaPipelineConfiguration) -> Bool {
        configuration.capturesSystemAudio && configuration.systemAudioLevel > 0
    }

    static func shouldProcessMicrophoneAudioSample(configuration: MediaPipelineConfiguration) -> Bool {
        configuration.capturesMicrophone && configuration.microphoneLevel > 0
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
            || previous.capturesSystemAudio != next.capturesSystemAudio
            || previous.screenCaptureTarget != next.screenCaptureTarget
    }
}

private struct PublishingCaptureState {
    var stream: SCStream?
    var microphoneSession: AVCaptureSession?
    var shouldStopMicrophoneSession: Bool
    var publisher: (any RTMPPublisher)?
}

private struct RecordingWriterState {
    var stream: SCStream?
    var microphoneSession: AVCaptureSession?
    var writer: AVAssetWriter?
    var videoInput: AVAssetWriterInput?
    var audioInput: AVAssetWriterInput?
    var microphoneInput: AVAssetWriterInput?
    var shouldStopMicrophoneSession: Bool
}

private struct MicrophoneCapture {
    var session: AVCaptureSession
    var output: AVCaptureAudioDataOutput
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

protocol RTMPPublisher: AnyObject, Sendable {
    func connect() async throws
    func append(_ sampleBuffer: CMSampleBuffer) -> Bool
    func close() async
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

#if OPEN_CUE_HAS_HAISHINKIT
private final class HaishinKitRTMPPublisher: RTMPPublisher, @unchecked Sendable {
    private let target: RTMPPublishTarget
    private let connection = RTMPConnection()
    private let stream: RTMPStream
    private let appendGate = RTMPAppendBackpressureGate()

    init(target: RTMPPublishTarget) {
        self.target = target
        self.stream = RTMPStream(connection: connection)
    }

    func connect() async throws {
        _ = try await connection.connect(target.connectionURL)
        _ = try await stream.publish(target.streamName)
    }

    func append(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard appendGate.tryBeginAppend() else { return false }
        Task {
            defer { appendGate.finishAppend() }
            await stream.append(sampleBuffer)
        }
        return true
    }

    func close() async {
        _ = try? await stream.close()
        _ = try? await connection.close()
    }
}
#endif

private final class ConnectivityRTMPPublisher: RTMPPublisher, @unchecked Sendable {
    private let target: RTMPPublishTarget
    private let timeout: TimeInterval
    private let connectionQueue = DispatchQueue(label: "com.opencue.rtmp.connect", qos: .userInitiated)
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

    func append(_ sampleBuffer: CMSampleBuffer) -> Bool {
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
