import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import Network
import Testing
@testable import MacStreamCore


final class FixedSignalProvider: SignalProvider, @unchecked Sendable {
    private let fixedSnapshot: SignalSnapshot

    init(snapshot: SignalSnapshot) {
        self.fixedSnapshot = snapshot
    }

    func start() {}

    func stop() {}

    func snapshot() -> SignalSnapshot {
        fixedSnapshot
    }
}

final class ConfigurableMediaPipeline: MediaPipeline, @unchecked Sendable {
    let streamTransport: StreamTransportKind
    var currentHealth: StreamHealth?
    var lastConfiguration: MediaPipelineConfiguration?
    var configurationAtStartStream: MediaPipelineConfiguration?
    var updateCount = 0

    init(streamTransport: StreamTransportKind = .endpointValidation) {
        self.streamTransport = streamTransport
    }

    func update(configuration: MediaPipelineConfiguration) {
        updateCount += 1
        lastConfiguration = configuration
    }

    func startStream(destination: StreamDestination) async throws {
        configurationAtStartStream = lastConfiguration
    }

    func stopStream() async {}

    func startRecording() async throws -> URL {
        URL(fileURLWithPath: "/tmp/macstream-configurable.mov")
    }

    func stopRecording() async {}
}

final class TransportCountingMediaPipeline: MediaPipeline, @unchecked Sendable {
    var transportReadCount = 0

    var streamTransport: StreamTransportKind {
        transportReadCount += 1
        return .rtmpPublish
    }

    func startStream(destination: StreamDestination) async throws {}

    func stopStream() async {}

    func startRecording() async throws -> URL {
        URL(fileURLWithPath: "/tmp/macstream-transport-counting.mov")
    }

    func stopRecording() async {}
}

final class ReadinessGatedMediaPipeline: MediaPipeline, @unchecked Sendable {
    var requiresCaptureReadinessForStart: Bool {
        true
    }

    func startStream(destination: StreamDestination) async throws {}

    func stopStream() async {}

    func startRecording() async throws -> URL {
        URL(fileURLWithPath: "/tmp/macstream-readiness-gated.mov")
    }

    func stopRecording() async {}
}

final class ScreenVideoGatedMediaPipeline: MediaPipeline, @unchecked Sendable {
    let streamTransport: StreamTransportKind

    init(streamTransport: StreamTransportKind = .rtmpPublish) {
        self.streamTransport = streamTransport
    }

    var requiresCaptureReadinessForStart: Bool {
        true
    }

    var requiresScreenCaptureVideoForStream: Bool {
        true
    }

    var requiresScreenCaptureVideoForRecording: Bool {
        true
    }

    var supportedSceneKindsForStream: Set<SceneKind> {
        [.screenOnly]
    }

    var supportedSceneKindsForRecording: Set<SceneKind> {
        [.screenOnly, .screenAndFace]
    }

    func startStream(destination: StreamDestination) async throws {}

    func stopStream() async {}

    func startRecording() async throws -> URL {
        URL(fileURLWithPath: "/tmp/macstream-screen-video-gated.mov")
    }

    func stopRecording() async {}
}

final class ComposedScreenVideoMediaPipeline: MediaPipeline, @unchecked Sendable {
    let streamTransport: StreamTransportKind
    var lastConfiguration: MediaPipelineConfiguration?
    var configurationAtStartStream: MediaPipelineConfiguration?
    var startCount = 0

    init(streamTransport: StreamTransportKind = .rtmpPublish) {
        self.streamTransport = streamTransport
    }

    var requiresCaptureReadinessForStart: Bool {
        true
    }

    var requiresScreenCaptureVideoForStream: Bool {
        true
    }

    var requiresScreenCaptureVideoForRecording: Bool {
        true
    }

    var supportedSceneKindsForStream: Set<SceneKind> {
        [.screenOnly, .screenAndFace]
    }

    var supportedSceneKindsForRecording: Set<SceneKind> {
        [.screenOnly, .screenAndFace]
    }

    func update(configuration: MediaPipelineConfiguration) {
        lastConfiguration = configuration
    }

    func startStream(destination: StreamDestination) async throws {
        startCount += 1
        configurationAtStartStream = lastConfiguration
    }

    func stopStream() async {}

    func startRecording() async throws -> URL {
        URL(fileURLWithPath: "/tmp/macstream-composed-screen-video.mov")
    }

    func stopRecording() async {}
}

actor DelayedSuccessfulRTMPPublisher: RTMPPublisher {
    private var hasStartedConnect = false
    private var shouldFinishConnect = false
    private var connectStartedContinuation: CheckedContinuation<Void, Never>?
    private var finishConnectContinuation: CheckedContinuation<Void, Never>?
    private(set) var closeCount = 0

    func connect() async throws {
        hasStartedConnect = true
        connectStartedContinuation?.resume()
        connectStartedContinuation = nil

        guard !shouldFinishConnect else { return }

        await withCheckedContinuation { continuation in
            finishConnectContinuation = continuation
        }
    }

    func waitUntilConnectStarted() async {
        guard !hasStartedConnect else { return }

        await withCheckedContinuation { continuation in
            connectStartedContinuation = continuation
        }
    }

    func finishConnect() {
        shouldFinishConnect = true
        finishConnectContinuation?.resume()
        finishConnectContinuation = nil
    }

    nonisolated func append(_ sampleBuffer: CMSampleBuffer, track: UInt8) -> Bool {
        true
    }

    func close() {
        closeCount += 1
    }
}

final class RecoveringMediaPipeline: MediaPipeline, @unchecked Sendable {
    var streamTransport: StreamTransportKind = .rtmpPublish
    var errorToThrow: (any Error)?
    var startCount = 0

    func startStream(destination: StreamDestination) async throws {
        startCount += 1
        if let errorToThrow {
            throw errorToThrow
        }
    }

    func stopStream() async {}

    func startRecording() async throws -> URL {
        URL(fileURLWithPath: "/tmp/macstream-recovering.mov")
    }

    func stopRecording() async {}
}

final class FlakyStartMediaPipeline: MediaPipeline, @unchecked Sendable {
    let streamTransport: StreamTransportKind
    private let failuresBeforeSuccess: Int
    var startCount = 0

    init(failuresBeforeSuccess: Int, streamTransport: StreamTransportKind = .rtmpPublish) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
        self.streamTransport = streamTransport
    }

    func startStream(destination: StreamDestination) async throws {
        startCount += 1
        if startCount <= failuresBeforeSuccess {
            throw TestStreamError(message: "Transient start failure \(startCount)")
        }
    }

    func stopStream() async {}

    func startRecording() async throws -> URL {
        URL(fileURLWithPath: "/tmp/macstream-flaky.mov")
    }

    func stopRecording() async {}
}

final class DelayedStartMediaPipeline: MediaPipeline, @unchecked Sendable {
    var streamTransport: StreamTransportKind = .preview
    var startCount = 0
    var startRecordingCount = 0

    func startStream(destination: StreamDestination) async throws {
        startCount += 1
        try await Task.sleep(for: .milliseconds(70))
    }

    func stopStream() async {}

    func startRecording() async throws -> URL {
        startRecordingCount += 1
        return URL(fileURLWithPath: "/tmp/macstream-delayed.mov")
    }

    func stopRecording() async {}
}

final class DelayedStopMediaPipeline: MediaPipeline, @unchecked Sendable {
    var streamTransport: StreamTransportKind = .preview
    var stopCount = 0

    func startStream(destination: StreamDestination) async throws {}

    func stopStream() async {
        stopCount += 1
        try? await Task.sleep(for: .milliseconds(70))
    }

    func startRecording() async throws -> URL {
        URL(fileURLWithPath: "/tmp/macstream-delayed-stop.mov")
    }

    func stopRecording() async {}
}

final class DelayedStopRecordingPipeline: MediaPipeline, @unchecked Sendable {
    var streamTransport: StreamTransportKind = .preview
    var stopRecordingCount = 0

    func startStream(destination: StreamDestination) async throws {}

    func stopStream() async {}

    func startRecording() async throws -> URL {
        URL(fileURLWithPath: "/tmp/macstream-delayed-stop-recording.mov")
    }

    func stopRecording() async {
        stopRecordingCount += 1
        try? await Task.sleep(for: .milliseconds(70))
    }
}

final class NonCancellableDelayedStartMediaPipeline: MediaPipeline, @unchecked Sendable {
    var streamTransport: StreamTransportKind = .preview
    var startCount = 0
    var stopCount = 0

    func startStream(destination: StreamDestination) async throws {
        startCount += 1
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.06) {
                continuation.resume()
            }
        }
    }

    func stopStream() async {
        stopCount += 1
    }

    func startRecording() async throws -> URL {
        URL(fileURLWithPath: "/tmp/macstream-noncancellable.mov")
    }

    func stopRecording() async {}
}

final class NonCancellableDelayedRecordingPipeline: MediaPipeline, @unchecked Sendable {
    var streamTransport: StreamTransportKind = .preview
    var startStreamCount = 0
    var startRecordingCount = 0
    var stopRecordingCount = 0

    func startStream(destination: StreamDestination) async throws {
        startStreamCount += 1
    }

    func stopStream() async {}

    func startRecording() async throws -> URL {
        startRecordingCount += 1
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.06) {
                continuation.resume()
            }
        }
        return URL(fileURLWithPath: "/tmp/macstream-delayed-recording.mov")
    }

    func stopRecording() async {
        stopRecordingCount += 1
    }
}

struct TestStreamError: LocalizedError {
    var message: String

    var errorDescription: String? {
        message
    }
}

final class ConfigurableSignalProvider: SignalProvider, @unchecked Sendable {
    var lastConfiguration: SignalSamplingConfiguration?
    var updateCount = 0
    var startCount = 0
    var stopCount = 0

    func update(configuration: SignalSamplingConfiguration) {
        updateCount += 1
        lastConfiguration = configuration
    }

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func snapshot() -> SignalSnapshot {
        SignalSnapshot()
    }
}

struct FixedCaptureDeviceProvider: CaptureDeviceProvider {
    var report: CapturePreflightReport

    func scan() async -> CapturePreflightReport {
        report
    }
}

actor CountingScreenCaptureContentListing: ScreenCaptureContentListing {
    private var count = 0

    func devices(permission: CapturePermissionState) async throws -> [CaptureDeviceInfo] {
        count += 1
        return [
            CaptureDeviceInfo(
                id: "display-7",
                kind: .display,
                name: "Studio Display",
                detail: "3024x1964",
                permission: permission
            )
        ]
    }

    func deviceLoadCount() -> Int {
        count
    }
}

actor DelayedCountingCaptureDeviceProvider: CaptureDeviceProvider {
    private var count = 0
    private let report: CapturePreflightReport

    init(report: CapturePreflightReport) {
        self.report = report
    }

    func scan() async -> CapturePreflightReport {
        count += 1
        try? await Task.sleep(for: .milliseconds(40))
        return report
    }

    func scanCount() -> Int {
        count
    }
}

actor SequencedCaptureDeviceProvider: CaptureDeviceProvider {
    private var reports: [CapturePreflightReport]
    private var index = 0

    init(reports: [CapturePreflightReport]) {
        self.reports = reports
    }

    func scan() async -> CapturePreflightReport {
        guard !reports.isEmpty else { return CapturePreflightReport() }

        let report = reports[min(index, reports.count - 1)]
        index += 1
        return report
    }

    func scanCount() -> Int {
        index
    }
}

struct DelayedSetupProvider: LocalIntelligenceProvider {
    let status: LocalIntelligenceStatus
    let plan: SetupPlan

    func generateSetupPlan(for prompt: String) async throws -> SetupPlan {
        try await Task.sleep(for: .milliseconds(30))
        return plan
    }

    func explain(_ recommendation: DirectorRecommendation, snapshot: SignalSnapshot) async throws -> String {
        "test explanation"
    }
}

actor CancellableDelayedSetupProvider: LocalIntelligenceProvider {
    nonisolated let status = LocalIntelligenceStatus(
        provider: .mlx,
        availability: .available,
        detail: "test model"
    )
    nonisolated let plan = SetupPlan(
        title: "Cancelled Demo",
        scenes: [.face, .screenAndFace, .screenOnly, .brb],
        directorProfile: .demo,
        directorRuleSummary: "cancelled rules"
    )
    private var started = 0
    private var completed = 0
    private var cancelled = 0

    func generateSetupPlan(for prompt: String) async throws -> SetupPlan {
        started += 1
        do {
            try await Task.sleep(for: .milliseconds(250))
        } catch is CancellationError {
            cancelled += 1
            throw CancellationError()
        }
        completed += 1
        return plan
    }

    func explain(_ recommendation: DirectorRecommendation, snapshot: SignalSnapshot) async throws -> String {
        "test explanation"
    }

    func startedCount() -> Int {
        started
    }

    func completedCount() -> Int {
        completed
    }

    func cancelledCount() -> Int {
        cancelled
    }
}

func expectedMediaConfiguration(
    _ mode: StudioPerformanceMode,
    sceneKind: SceneKind = .brb,
    capturesSystemAudio: Bool = false,
    capturesMicrophone: Bool = true,
    systemAudioLevel: Double = 0.72,
    microphoneLevel: Double = 1,
    screenCaptureTarget: ScreenCaptureTarget? = nil
) -> MediaPipelineConfiguration {
    var configuration = mode.mediaConfiguration
    configuration.sceneKind = sceneKind
    configuration.capturesSystemAudio = capturesSystemAudio
    configuration.capturesMicrophone = capturesMicrophone
    configuration.systemAudioLevel = systemAudioLevel
    configuration.microphoneLevel = microphoneLevel
    configuration.screenCaptureTarget = screenCaptureTarget
    return configuration
}

actor CountingSetupProvider: LocalIntelligenceProvider {
    nonisolated let status = LocalIntelligenceStatus(
        provider: .mlx,
        availability: .fallback,
        detail: "test fallback"
    )
    nonisolated let plan = SetupPlan(
        title: "Counted",
        scenes: [.face, .screenAndFace, .screenOnly, .brb],
        directorProfile: .coding,
        directorRuleSummary: "counted rules"
    )
    private var callCount = 0

    func generateSetupPlan(for prompt: String) async throws -> SetupPlan {
        callCount += 1
        return plan
    }

    func explain(_ recommendation: DirectorRecommendation, snapshot: SignalSnapshot) async throws -> String {
        "test explanation"
    }

    func generatedCount() -> Int {
        callCount
    }
}

actor PromptCapturingSetupProvider: LocalIntelligenceProvider {
    nonisolated let status = LocalIntelligenceStatus(
        provider: .mlx,
        availability: .fallback,
        detail: "test fallback"
    )
    nonisolated let plan = SetupPlan(
        title: "Captured",
        scenes: [.face, .screenAndFace, .screenOnly, .brb],
        directorProfile: .balanced,
        directorRuleSummary: "captured rules"
    )
    private var prompt: String?

    func generateSetupPlan(for prompt: String) async throws -> SetupPlan {
        self.prompt = prompt
        return plan
    }

    func explain(_ recommendation: DirectorRecommendation, snapshot: SignalSnapshot) async throws -> String {
        "test explanation"
    }

    func receivedPrompt() -> String? {
        prompt
    }
}

@MainActor
final class SpyMediaPipeline: MediaPipeline, @unchecked Sendable {
    var didStartStream = false
    var didStartRecording = false
    var didStopRecording = false

    func startStream(destination: StreamDestination) async throws {
        didStartStream = true
    }

    func stopStream() async {}

    func startRecording() async throws -> URL {
        didStartRecording = true
        return URL(fileURLWithPath: "/tmp/macstream-test.mov")
    }

    func stopRecording() async {
        didStopRecording = true
    }
}
