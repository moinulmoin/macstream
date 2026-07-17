import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import Network
import Testing
@testable import MacStreamCore

@Test
func sessionReportExporterWritesJSONPayload() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("macstream-session-export-\(UUID().uuidString)", isDirectory: true)
    let report = SessionReportPayload(
        exportedAt: Date(timeIntervalSince1970: 30),
        destinations: [SessionDestinationState(id: UUID(), name: "Twitch", isEnabled: true, publishState: .publishing)],
        streamTransport: .endpointValidation,
        recordingPath: "/tmp/macstream.mov",
        sourceStates: [
            SessionSourceState(kind: .camera, title: "FaceTime Camera", isEnabled: true, level: 1),
            SessionSourceState(kind: .microphone, title: "Studio Mic", isEnabled: false, level: 0.4)
        ],
        screenCaptureTarget: ScreenCaptureTarget(id: "display-1", kind: .display, name: "Studio Display", detail: "3024x1964"),
        preferences: StudioPreferences(performanceMode: .efficiency),
        effectivePerformanceMode: .efficiency,
        health: StreamHealth(bitrateKbps: 4_000, captureFPS: 24),
        streamRecovery: StreamRecoveryMetrics(
            interruptionCount: 2,
            successfulRecoveryCount: 1,
            failedRecoveryCount: 1,
            lastDowntimeMilliseconds: 850,
            totalDowntimeMilliseconds: 2_400
        ),
        systemPressure: SystemPressureSnapshot(
            timestamp: Date(timeIntervalSince1970: 50),
            thermalPressure: .fair,
            memoryUsedMB: 512,
            physicalMemoryMB: 16_384
        ),
        latestSignals: SignalSnapshot(timestamp: Date(timeIntervalSince1970: 40), activeApplication: "Xcode"),
        clipMarkers: [],
        events: []
    )

    let url = try SessionReportExporter().export(report, to: directory)
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let payload = try decoder.decode(SessionReportPayload.self, from: data)

    #expect(payload == report)
}

@Test
func sessionReportExporterAvoidsSameSecondOverwrite() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("macstream-session-export-collision-\(UUID().uuidString)", isDirectory: true)
    let report = SessionReportPayload(
        exportedAt: Date(timeIntervalSince1970: 20),
        destinations: [SessionDestinationState(id: UUID(), name: "Preview", isEnabled: true)],
        streamTransport: .preview,
        recordingPath: nil,
        preferences: StudioPreferences(),
        effectivePerformanceMode: .balanced,
        health: StreamHealth(),
        latestSignals: SignalSnapshot(),
        clipMarkers: [],
        events: []
    )
    let exporter = SessionReportExporter()

    let firstURL = try exporter.export(report, to: directory)
    let secondURL = try exporter.export(report, to: directory)

    #expect(firstURL != secondURL)
    #expect(FileManager.default.fileExists(atPath: firstURL.path))
    #expect(FileManager.default.fileExists(atPath: secondURL.path))
}

@Test
@MainActor
func studioStoreExportsSessionReportWithoutSecretURL() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("macstream-session-store-\(UUID().uuidString)", isDirectory: true)
    let store = StudioStore(mediaPipeline: SpyMediaPipeline())
    store.destination = StreamDestination(name: "Twitch", rtmpURL: "rtmps://live.example.com/app/sk_live_secret")
    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.markClip(reason: "Worth review.")

    let url = try #require(store.exportSessionReport(to: directory))
    let data = try Data(contentsOf: url)
    let text = String(decoding: data, as: UTF8.self)

    #expect(store.latestSessionReportURL == url)
    #expect(store.events[0].title == "Report exported")
    #expect(text.contains("\"name\" : \"Twitch\""))
    #expect(!text.contains("sk_live_secret"))
    #expect(!text.contains("rtmps://live.example.com"))
}

@Test
@MainActor
func studioStoreRetainsExtendedCurrentSessionEventsForReport() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("macstream-session-events-\(UUID().uuidString)", isDirectory: true)
    let store = StudioStore(mediaPipeline: SpyMediaPipeline())

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    for index in 0..<12 {
        store.selectScene(store.scenes[index % store.scenes.count])
    }

    let url = try #require(store.exportSessionReport(to: directory))
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let payload = try decoder.decode(SessionReportPayload.self, from: data)

    #expect(payload.events.count > 8)
    #expect(payload.events.contains { $0.title == "Session started" })
}

@Test
@MainActor
func studioStoreExportsSourceAndCaptureTargetContextInSessionReport() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("macstream-session-context-\(UUID().uuidString)", isDirectory: true)
    let report = CapturePreflightReport(
        devices: [
            CaptureDeviceInfo(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964", permission: .granted),
            CaptureDeviceInfo(id: "window-42", kind: .window, name: "Slides", detail: "Keynote", permission: .granted)
        ],
        summary: "Capture sources are ready."
    )
    let store = StudioStore(
        mediaPipeline: SpyMediaPipeline(),
        captureDeviceProvider: FixedCaptureDeviceProvider(report: report)
    )
    store.scanCaptureDevices()
    try? await Task.sleep(for: .milliseconds(30))
    let microphone = store.sources.first { $0.kind == .microphone }!
    store.updateLevel(for: microphone, level: 0.35)
    store.toggleSource(microphone)

    let url = try #require(store.exportSessionReport(to: directory))
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let payload = try decoder.decode(SessionReportPayload.self, from: data)

    let microphoneState = try #require(payload.sourceStates.first { $0.kind == .microphone })
    #expect(microphoneState.title == "Studio Mic")
    #expect(!microphoneState.isEnabled)
    #expect(microphoneState.level == 0.35)
    #expect(payload.screenCaptureTarget == ScreenCaptureTarget(id: "display-7", kind: .display, name: "Studio Display", detail: "3024x1964"))
}

@Test
@MainActor
func disabledMicrophoneSuppressesSpeechSignal() {
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: true,
            speechLevel: 0.82,
            screenMotion: 0.1,
            hasFace: true,
            activeApplication: "Notes"
        )
    )
    let store = StudioStore(signalProvider: provider)
    let microphone = store.sources.first { $0.kind == .microphone }!

    store.toggleSource(microphone)
    store.advanceDirector()

    #expect(!store.latestSignals.isSpeaking)
    #expect(store.latestSignals.speechLevel == 0)
    #expect(store.latestSignals.isMicMuted)
}

@Test
@MainActor
func disabledScreenSuppressesMotionSignal() {
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: false,
            speechLevel: 0.02,
            screenMotion: 0.92,
            hasFace: true,
            activeApplication: "Xcode",
            isScreenFrozen: true
        )
    )
    let store = StudioStore(signalProvider: provider)
    let screen = store.sources.first { $0.kind == .screen }!

    store.toggleSource(screen)
    store.advanceDirector()

    #expect(store.latestSignals.screenMotion == 0)
    #expect(!store.latestSignals.isScreenFrozen)
}

@Test
@MainActor
func sourceLevelsScaleDirectorSignals() {
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: true,
            speechLevel: 0.8,
            screenMotion: 0.6,
            hasFace: true,
            activeApplication: "Xcode"
        )
    )
    let store = StudioStore(signalProvider: provider)
    let microphone = store.sources.first { $0.kind == .microphone }!
    let screen = store.sources.first { $0.kind == .screen }!

    store.updateLevel(for: microphone, level: 0.5)
    store.updateLevel(for: screen, level: 0.25)
    store.advanceDirector()

    #expect(abs(store.latestSignals.speechLevel - 0.4) < 0.000_001)
    #expect(store.latestSignals.isSpeaking)
    #expect(abs(store.latestSignals.screenMotion - 0.15) < 0.000_001)
}

@Test
@MainActor
func sourceLevelsAreClampedAndZeroLevelMutesSignal() {
    let provider = FixedSignalProvider(
        snapshot: SignalSnapshot(
            isSpeaking: true,
            speechLevel: 0.8,
            screenMotion: 0.6,
            hasFace: true,
            activeApplication: "Xcode",
            isScreenFrozen: true
        )
    )
    let store = StudioStore(signalProvider: provider)
    let microphone = store.sources.first { $0.kind == .microphone }!
    let screen = store.sources.first { $0.kind == .screen }!

    store.updateLevel(for: microphone, level: -1)
    store.updateLevel(for: screen, level: 2)
    store.advanceDirector()

    #expect(store.sourceLevel(.microphone) == 0)
    #expect(store.sourceLevel(.screen) == 1)
    #expect(store.latestSignals.speechLevel == 0)
    #expect(!store.latestSignals.isSpeaking)
    #expect(store.latestSignals.isMicMuted)
    #expect(store.latestSignals.screenMotion == 0.6)
    #expect(store.latestSignals.isScreenFrozen)
}

@Test
@MainActor
func launchSetupDefaultsApplySavedSceneAndPrompt() {
    let store = StudioStore()

    store.applyLaunchSetupDefaults(
        defaultSceneKind: .screenAndFace,
        setupPrompt: "Coding demo with a face camera"
    )

    #expect(store.selectedSceneKind == .screenAndFace)
    #expect(store.setupPrompt == "Coding demo with a face camera")
}

@Test
@MainActor
func savedSetupPromptIsBoundedForPersistence() {
    let store = StudioStore()
    let longPrompt = String(
        repeating: "a",
        count: SetupPlanPromptBuilder.maxStreamDescriptionCharacters + 25
    )

    store.applySavedSetupPrompt(longPrompt)

    #expect(store.setupPrompt.count == SetupPlanPromptBuilder.maxStreamDescriptionCharacters)
}

@Test
@MainActor
func setupRulesApplyCodingProfile() async {
    let store = StudioStore()
    store.setupPrompt = "I am doing coding streams in Xcode"

    store.generateSetupPlan()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(store.directorProfile.kind == .coding)
}

@Test
@MainActor
func setupRulesBoundPromptSentToProvider() async {
    let provider = PromptCapturingSetupProvider()
    let store = StudioStore(intelligenceProvider: provider)
    let prefix = String(repeating: "a", count: SetupPlanPromptBuilder.maxStreamDescriptionCharacters)
    let suffix = "SHOULD_NOT_REACH_PROVIDER"

    store.setupPrompt = prefix + suffix
    store.generateSetupPlan()
    try? await Task.sleep(for: .milliseconds(20))

    let prompt = await provider.receivedPrompt()
    #expect(prompt == prefix)
}

@Test
@MainActor
func setupRulesBlockBlankPromptBeforeProviderCall() async {
    let provider = CountingSetupProvider()
    let store = StudioStore(intelligenceProvider: provider)

    store.setupPrompt = " \n\t "

    #expect(!store.canGenerateSetupPlan)
    #expect(store.setupGenerationStatusDetail == "Describe the stream before generating setup rules.")

    store.generateSetupPlan()
    try? await Task.sleep(for: .milliseconds(20))

    #expect(await provider.generatedCount() == 0)
    #expect(store.setupSummary == "Describe the stream before generating setup rules.")
    #expect(store.events.contains { $0.title == "Setup paused" })
}

@Test
@MainActor
func setupRulesTrimPromptBeforeProviderCall() async {
    let provider = PromptCapturingSetupProvider()
    let store = StudioStore(intelligenceProvider: provider)

    store.setupPrompt = " \n coding stream in Xcode \t "
    store.generateSetupPlan()
    try? await Task.sleep(for: .milliseconds(20))

    let prompt = await provider.receivedPrompt()
    #expect(prompt == "coding stream in Xcode")
}

@Test
func mlxLocalProviderFallsBackWhenRuntimeIsNotLinked() async throws {
    let provider = MLXLocalIntelligenceProvider()

    let plan = try await provider.generateSetupPlan(for: "coding stream in xcode")

    #expect(provider.modelIdentifier == MLXLocalIntelligenceProvider.defaultModelIdentifier)
    #expect(provider.modelIdentifier == "LiquidAI/LFM2.5-8B-A1B-MLX-4bit")
    #expect(plan.directorProfile.kind == .coding)
    #if MAC_STREAM_HAS_MLX
    #expect(provider.status.availability == .available)
    #else
    #expect(provider.status.availability == .fallback)
    #endif
}

@Test
func openAICompatibleProviderDecodesChatCompletionSetupPlan() async throws {
    let spy = OpenAICompatibleTransportSpy(
        response: (
            try openAICompatibleChatCompletionData(
                content: #"{"title":"Product Demo","profile":"demo","summary":"Cut from face to screen when the product moves."}"#
            ),
            openAICompatibleHTTPResponse(statusCode: 200)
        )
    )
    let provider = OpenAICompatibleLocalIntelligenceProvider(
        configuration: OpenAICompatibleProviderConfiguration(model: "demo-model"),
        transport: spy.transport
    )

    let plan = try await provider.generateSetupPlan(for: "demo stream")

    #expect(plan.title == "Product Demo")
    #expect(plan.directorProfile.kind == .demo)
    #expect(plan.scenes == [.face, .screenAndFace, .screenOnly, .brb])
    #expect(plan.directorRuleSummary == "Cut from face to screen when the product moves.")
}

@Test
func openAICompatibleProviderSendsBoundedSetupPrompt() async throws {
    let spy = OpenAICompatibleTransportSpy(
        response: (
            try openAICompatibleChatCompletionData(
                content: #"{"title":"Coding","profile":"coding","summary":"Keep screen and face visible."}"#
            ),
            openAICompatibleHTTPResponse(statusCode: 200)
        )
    )
    let provider = OpenAICompatibleLocalIntelligenceProvider(
        configuration: OpenAICompatibleProviderConfiguration(
            baseURL: URL(string: "http://localhost:1234")!,
            model: "bounded-model"
        ),
        transport: spy.transport
    )
    let prefix = String(repeating: "a", count: SetupPlanPromptBuilder.maxStreamDescriptionCharacters)
    let suffix = "SHOULD_NOT_REACH_PROVIDER"

    _ = try await provider.generateSetupPlan(for: prefix + suffix)

    let request = try #require(await spy.capturedRequests().first)
    let body = try openAICompatibleJSONObject(request.body)
    let messages = try #require(body["messages"] as? [[String: String]])
    let userMessage = try #require(messages.last?["content"])
    #expect(userMessage.contains(prefix))
    #expect(!userMessage.contains(suffix))
    #expect(body["model"] as? String == "bounded-model")
    #expect(body["stream"] as? Bool == false)
    #expect(request.request.url?.path == "/v1/chat/completions")
}

@Test
func openAICompatibleProviderThrowsSetupPlanDecodingErrorForMalformedContent() async throws {
    let spy = OpenAICompatibleTransportSpy(
        response: (
            try openAICompatibleChatCompletionData(content: "no setup json here"),
            openAICompatibleHTTPResponse(statusCode: 200)
        )
    )
    let provider = OpenAICompatibleLocalIntelligenceProvider(
        configuration: OpenAICompatibleProviderConfiguration(model: "bad-model"),
        transport: spy.transport
    )

    do {
        _ = try await provider.generateSetupPlan(for: "demo stream")
        Issue.record("Expected setup plan decoding to fail")
    } catch is SetupPlanDecodingError {
    }
}

@Test
func openAICompatibleProviderThrowsForHTTPFailure() async throws {
    let spy = OpenAICompatibleTransportSpy(
        response: (
            try openAICompatibleChatCompletionData(
                content: #"{"title":"Fallback","profile":"balanced","summary":"Should not apply."}"#
            ),
            openAICompatibleHTTPResponse(statusCode: 500)
        )
    )
    let provider = OpenAICompatibleLocalIntelligenceProvider(
        configuration: OpenAICompatibleProviderConfiguration(model: "failing-model"),
        transport: spy.transport
    )

    await #expect(throws: Error.self) {
        _ = try await provider.generateSetupPlan(for: "coding stream")
    }
}

@Test
func openAICompatibleProviderAppliesAuthorizationHeaderOnlyWhenAPIKeyPresent() async throws {
    let response = (
        try openAICompatibleChatCompletionData(
            content: #"{"title":"Demo","profile":"demo","summary":"Show product motion."}"#
        ),
        openAICompatibleHTTPResponse(statusCode: 200)
    )
    let noKeySpy = OpenAICompatibleTransportSpy(response: response)
    let keyedSpy = OpenAICompatibleTransportSpy(response: response)

    _ = try await OpenAICompatibleLocalIntelligenceProvider(
        configuration: OpenAICompatibleProviderConfiguration(model: "demo", apiKey: "   "),
        transport: noKeySpy.transport
    ).generateSetupPlan(for: "demo")
    _ = try await OpenAICompatibleLocalIntelligenceProvider(
        configuration: OpenAICompatibleProviderConfiguration(model: "demo", apiKey: "dummy-local-key"),
        transport: keyedSpy.transport
    ).generateSetupPlan(for: "demo")

    #expect(try #require(await noKeySpy.capturedRequests().first).request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(try #require(await keyedSpy.capturedRequests().first).request.value(forHTTPHeaderField: "Authorization") == "Bearer dummy-local-key")
}

@Test
func openAICompatibleProviderAppliesRequestTimeout() async throws {
    let spy = OpenAICompatibleTransportSpy(
        response: (
            try openAICompatibleChatCompletionData(
                content: #"{"title":"Teaching","profile":"teaching","summary":"Keep face visible while explaining."}"#
            ),
            openAICompatibleHTTPResponse(statusCode: 200)
        )
    )
    let provider = OpenAICompatibleLocalIntelligenceProvider(
        configuration: OpenAICompatibleProviderConfiguration(model: "teaching", timeout: 17),
        transport: spy.transport
    )

    _ = try await provider.generateSetupPlan(for: "teaching")

    #expect(try #require(await spy.capturedRequests().first).request.timeoutInterval == 17)
}

@Test
func openAICompatibleProviderProbeReturnsAvailableForModelsSuccess() async throws {
    let spy = OpenAICompatibleTransportSpy(
        response: (Data(), openAICompatibleHTTPResponse(statusCode: 200, path: "/v1/models"))
    )
    let provider = OpenAICompatibleLocalIntelligenceProvider(
        configuration: OpenAICompatibleProviderConfiguration(
            baseURL: URL(string: "http://localhost:1234/v1")!,
            model: "probe-model",
            timeout: 30
        ),
        transport: spy.transport
    )

    let status = await provider.probeCapabilities()

    let request = try #require(await spy.capturedRequests().first)
    #expect(request.request.httpMethod == "GET")
    #expect(request.request.url?.path == "/v1/models")
    #expect(request.body.isEmpty)
    #expect(request.request.timeoutInterval == OpenAICompatibleLocalIntelligenceProvider.probeTimeout)
    #expect(status.provider == .openAICompatible)
    #expect(status.availability == .available)
}

@Test
func openAICompatibleProviderProbeReturnsUnavailableForModelsFailure() async {
    let spy = OpenAICompatibleTransportSpy(
        response: (Data(), openAICompatibleHTTPResponse(statusCode: 500, path: "/v1/models"))
    )
    let provider = OpenAICompatibleLocalIntelligenceProvider(
        configuration: OpenAICompatibleProviderConfiguration(model: "probe-model"),
        transport: spy.transport
    )

    let status = await provider.probeCapabilities()

    #expect(status.provider == .openAICompatible)
    #expect(status.availability == .unavailable)
    #expect(status.detail.contains("HTTP 500"))
}

@Test
@MainActor
func openAICompatibleProviderProbeStatusUpdatesStoreWhenProviderIsReplaced() async {
    let spy = OpenAICompatibleTransportSpy(
        response: (Data(), openAICompatibleHTTPResponse(statusCode: 200, path: "/v1/models"))
    )
    let provider = OpenAICompatibleLocalIntelligenceProvider(
        configuration: OpenAICompatibleProviderConfiguration(model: "store-model"),
        transport: spy.transport
    )
    let store = StudioStore(intelligenceProvider: provider)

    let status = await provider.probeCapabilities()
    let accepted = store.setIntelligenceProvider(provider.replacingProbedStatus(status))

    #expect(accepted)
    #expect(store.localIntelligenceStatus.provider == .openAICompatible)
    #expect(store.localIntelligenceStatus.availability == .available)
}

private struct CapturedRequest: Sendable {
    var request: URLRequest
    var body: Data
}

private actor OpenAICompatibleTransportSpy {
    private var requests: [CapturedRequest] = []
    private let response: (Data, URLResponse)

    init(response: (Data, URLResponse)) {
        self.response = response
    }

    func transport(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let body = request.httpBody ?? Data()
        requests.append(CapturedRequest(request: request, body: body))
        return response
    }

    func capturedRequests() -> [CapturedRequest] {
        requests
    }
}

private func openAICompatibleChatCompletionData(content: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "choices": [
            [
                "message": [
                    "content": content
                ]
            ]
        ]
    ])
}

private func openAICompatibleJSONObject(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func openAICompatibleHTTPResponse(statusCode: Int, path: String = "/v1/chat/completions") -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "http://localhost:1234\(path)")!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    )!
}

@Test
func setupPlanPromptConstrainsModelOutput() {
    let prompt = SetupPlanPromptBuilder().prompt(for: "I teach SwiftUI with screen and camera")

    #expect(prompt.contains("Return only compact JSON"))
    #expect(prompt.contains("balanced|coding|demo|teaching|podcast"))
    #expect(prompt.contains("do not ask for real-time LLM control"))
}

@Test
func setupPlanPromptBoundsStreamDescriptionForLocalModels() {
    let prefix = String(repeating: "a", count: SetupPlanPromptBuilder.maxStreamDescriptionCharacters)
    let suffix = "SHOULD_NOT_REACH_MODEL"
    let prompt = SetupPlanPromptBuilder().prompt(for: prefix + suffix)

    #expect(prompt.contains(prefix))
    #expect(!prompt.contains(suffix))
}

@Test
func setupPlanResponseDecoderBuildsTypedProfile() throws {
    let response = """
    {"title":"Swift Workshop","profile":"teaching","summary":"Keep the camera visible while explaining and cut to screen for demos."}
    """

    let plan = try SetupPlanResponseDecoder().decode(response)

    #expect(plan.title == "Swift Workshop")
    #expect(plan.directorProfile.kind == .teaching)
    #expect(plan.scenes == [.face, .screenAndFace, .screenOnly, .brb])
}

@Test
func setupPlanResponseDecoderUsesFirstCompleteJSONObject() throws {
    let response = """
    Here is the plan:
    {"title":"Product Demo","profile":"demo","summary":"Open on Face, then cut to Screen + Face for product motion."}
    Ignore this duplicate:
    {"title":"Podcast","profile":"podcast","summary":"Do not use this."}
    """

    let plan = try SetupPlanResponseDecoder().decode(response)

    #expect(plan.title == "Product Demo")
    #expect(plan.directorProfile.kind == .demo)
}

@Test
func setupPlanResponseDecoderIgnoresBracesInsideStrings() throws {
    let response = #"""
    ```json
    {"title":"Coding","profile":"coding","summary":"Treat {editor} motion as screen context and escaped \"quotes\" as text."}
    ```
    """#

    let plan = try SetupPlanResponseDecoder().decode(response)

    #expect(plan.directorProfile.kind == .coding)
    #expect(plan.directorRuleSummary.contains("{editor}"))
    #expect(plan.directorRuleSummary.contains(#""quotes""#))
}

@Test
func setupPlanResponseDecoderRejectsUnsupportedProfile() {
    let response = """
    {"title":"Bad","profile":"cinematic","summary":"Unsupported."}
    """

    #expect(throws: SetupPlanDecodingError.self) {
        try SetupPlanResponseDecoder().decode(response)
    }
}

@Test
func mlxLocalProviderExposesSetupPlanDecoder() throws {
    let provider = MLXLocalIntelligenceProvider()
    let plan = try provider.decodeSetupPlanResponse(
        #"{"title":"Product Demo","profile":"demo","summary":"Balance face and screen while showing the product."}"#
    )

    #expect(plan.directorProfile.kind == .demo)
}

@Test
func localModelStrategyDocumentsTextAndVisionModelBoundaries() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let architecture = try String(
        contentsOf: root.appendingPathComponent("docs/architecture.md"),
        encoding: .utf8
    )
    let risks = try String(
        contentsOf: root.appendingPathComponent("docs/technical-risks.md"),
        encoding: .utf8
    )

    #expect(architecture.contains(MLXLocalIntelligenceProvider.defaultModelIdentifier))
    #expect(architecture.contains("RuleBasedLocalIntelligenceProvider"))
    #expect(architecture.contains("OpenAI-compatible endpoints"))
    #expect(risks.contains("Provider-first beats managed runtime ownership"))
    #expect(risks.contains("Foundation Models and OpenAI-compatible providers"))
    #expect(risks.contains("Moondream"))
    #expect(risks.contains("sampled frames"))
    #expect(risks.contains("cloud vision"))
    #expect(risks.contains("hot path"))
}

@Test
@MainActor
func setupRulesTrackGenerationStateAndProviderStatus() async {
    let status = LocalIntelligenceStatus(
        provider: .mlx,
        availability: .fallback,
        detail: "test fallback"
    )
    let provider = DelayedSetupProvider(
        status: status,
        plan: SetupPlan(
            title: "Demo",
            scenes: [.face, .screenAndFace, .screenOnly, .brb],
            directorProfile: .demo,
            directorRuleSummary: "demo rules"
        )
    )
    let store = StudioStore(intelligenceProvider: provider)

    store.generateSetupPlan()

    #expect(store.isGeneratingSetupPlan)
    #expect(store.setupSummary == "Generating setup rules...")

    try? await Task.sleep(for: .milliseconds(80))

    #expect(!store.isGeneratingSetupPlan)
    #expect(store.localIntelligenceStatus == status)
    #expect(store.directorProfile.kind == .demo)
    #expect(store.setupSummary == "demo rules")
}

@Test
@MainActor
func setupRulesDoNotApplyFinishedPlanAfterStreamStarts() async {
    let status = LocalIntelligenceStatus(
        provider: .mlx,
        availability: .available,
        detail: "test model"
    )
    let provider = DelayedSetupProvider(
        status: status,
        plan: SetupPlan(
            title: "Demo",
            scenes: [.face, .screenAndFace, .screenOnly, .brb],
            directorProfile: .demo,
            directorRuleSummary: "demo rules"
        )
    )
    let store = StudioStore(
        mediaPipeline: SpyMediaPipeline(),
        intelligenceProvider: provider
    )

    store.generateSetupPlan()
    store.startStream()
    try? await Task.sleep(for: .milliseconds(80))

    #expect(!store.isGeneratingSetupPlan)
    #expect(store.localIntelligenceStatus == status)
    #expect(store.directorProfile.kind == .balanced)
    #expect(store.setupSummary == "Stop preview before generating local setup rules.")
    #expect(store.events.contains { $0.title == "Setup paused" })
    #expect(!store.events.contains { $0.title == "Demo" })
}

@Test
@MainActor
func setupRulesCancelInFlightGenerationWhenStreamStarts() async {
    let provider = CancellableDelayedSetupProvider()
    let store = StudioStore(
        mediaPipeline: SpyMediaPipeline(),
        intelligenceProvider: provider
    )

    store.generateSetupPlan()
    await provider.waitUntilStarted()

    #expect(store.isGeneratingSetupPlan)

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(!store.isGeneratingSetupPlan)
    #expect(store.directorProfile.kind == .balanced)
    #expect(store.setupSummary == "Stop preview before generating local setup rules.")
    #expect(store.events.contains { $0.title == "Setup paused" })
    #expect(!store.events.contains { $0.title == "Setup failed" })
    #expect(await provider.startedCount() == 1)
    #expect(await provider.completedCount() == 0)
    #expect(await provider.cancelledCount() == 1)
}

@Test
@MainActor
func setupRulesDoNotApplyFinishedPlanAfterPromptChanges() async {
    let provider = DelayedSetupProvider(
        status: LocalIntelligenceStatus(
            provider: .mlx,
            availability: .available,
            detail: "test model"
        ),
        plan: SetupPlan(
            title: "Demo",
            scenes: [.face, .screenAndFace, .screenOnly, .brb],
            directorProfile: .demo,
            directorRuleSummary: "demo rules"
        )
    )
    let store = StudioStore(intelligenceProvider: provider)

    store.setupPrompt = "coding stream in xcode"
    store.generateSetupPlan()
    store.setupPrompt = "podcast with guests"
    try? await Task.sleep(for: .milliseconds(80))

    #expect(!store.isGeneratingSetupPlan)
    #expect(store.directorProfile.kind == .balanced)
    #expect(store.setupSummary == "Setup prompt changed; generate rules again.")
    #expect(store.events.contains { $0.title == "Setup changed" })
    #expect(!store.events.contains { $0.title == "Demo" })
}

@Test
@MainActor
func setupRulesPauseGenerationWhileStreamIsLive() async {
    let provider = CountingSetupProvider()
    let store = StudioStore(
        mediaPipeline: SpyMediaPipeline(),
        intelligenceProvider: provider
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.generateSetupPlan()
    try? await Task.sleep(for: .milliseconds(20))

    #expect(!store.canGenerateSetupPlan)
    #expect(store.setupGenerationStatusDetail == "Stop preview before generating local setup rules.")
    #expect(store.setupSummary == "Stop preview before generating local setup rules.")
    #expect(await provider.generatedCount() == 0)
    #expect(store.events.contains { $0.title == "Setup paused" })
}

@Test
@MainActor
func repeatedBlockedSetupGenerationDoesNotSpamEvents() async {
    let provider = CountingSetupProvider()
    let store = StudioStore(
        mediaPipeline: SpyMediaPipeline(),
        intelligenceProvider: provider
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    store.generateSetupPlan()
    store.generateSetupPlan()
    try? await Task.sleep(for: .milliseconds(20))

    #expect(store.setupSummary == "Stop preview before generating local setup rules.")
    #expect(await provider.generatedCount() == 0)
    #expect(store.events.filter { $0.title == "Setup paused" }.count == 1)
}

@Test
@MainActor
func setupRulesPauseGenerationWhileStreamIsConnecting() async {
    let provider = CountingSetupProvider()
    let store = StudioStore(
        mediaPipeline: DelayedStartMediaPipeline(),
        intelligenceProvider: provider
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(10))
    store.generateSetupPlan()

    #expect(!store.canGenerateSetupPlan)
    #expect(store.setupGenerationStatusDetail == "Finish connecting before generating setup rules.")

    try? await Task.sleep(for: .milliseconds(20))

    #expect(await provider.generatedCount() == 0)
}

@Test
@MainActor
func setupRulesPauseGenerationWhileRecording() async {
    let provider = CountingSetupProvider()
    let store = StudioStore(
        mediaPipeline: SpyMediaPipeline(),
        intelligenceProvider: provider
    )

    store.startRecording()
    try? await Task.sleep(for: .milliseconds(50))
    store.generateSetupPlan()
    try? await Task.sleep(for: .milliseconds(20))

    #expect(!store.canGenerateSetupPlan)
    #expect(store.setupGenerationStatusDetail == "Stop recording before generating local setup rules.")
    #expect(await provider.generatedCount() == 0)
}

@Test
@MainActor
func defaultPreferencesKeepAutoRecordingOff() async {
    let pipeline = SpyMediaPipeline()
    let store = StudioStore(mediaPipeline: pipeline)

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(pipeline.didStartStream)
    #expect(!pipeline.didStartRecording)
    #expect(store.recordingState == .stopped)
}

@Test
@MainActor
func startStreamHonorsRecordWhileStreamingPreference() async {
    let pipeline = SpyMediaPipeline()
    let store = StudioStore(
        mediaPipeline: pipeline,
        preferences: StudioPreferences(recordWhileStreaming: false)
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(pipeline.didStartStream)
    #expect(!pipeline.didStartRecording)
    #expect(store.recordingState == .stopped)
}

@Test
@MainActor
func startStreamRecordsWhenPreferenceEnabled() async {
    let pipeline = SpyMediaPipeline()
    let store = StudioStore(
        mediaPipeline: pipeline,
        preferences: StudioPreferences(recordWhileStreaming: true)
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(pipeline.didStartStream)
    #expect(pipeline.didStartRecording)
}

@Test
@MainActor
func stopStreamStopsOnlyAutoStartedRecording() async {
    let pipeline = SpyMediaPipeline()
    let store = StudioStore(
        mediaPipeline: pipeline,
        preferences: StudioPreferences(recordWhileStreaming: true)
    )

    store.startStream()
    try? await Task.sleep(for: .milliseconds(80))
    store.stopStream()
    try? await Task.sleep(for: .milliseconds(80))

    #expect(pipeline.didStartRecording)
    #expect(pipeline.didStopRecording)
    #expect(store.recordingState == .stopped)
}

@Test
@MainActor
func stopStreamPreservesManualRecording() async {
    let pipeline = SpyMediaPipeline()
    let store = StudioStore(
        mediaPipeline: pipeline,
        preferences: StudioPreferences(recordWhileStreaming: true)
    )

    store.startRecording()
    try? await Task.sleep(for: .milliseconds(50))
    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))
    store.stopStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(pipeline.didStartStream)
    #expect(pipeline.didStartRecording)
    #expect(!pipeline.didStopRecording)
    #expect(store.recordingState == .recording)
}

@Test
@MainActor
func recordingStartCanBeCancelledAndSuppressesDuplicateStarts() async {
    let pipeline = NonCancellableDelayedRecordingPipeline()
    let store = StudioStore(mediaPipeline: pipeline)

    store.startRecording()
    try? await Task.sleep(for: .milliseconds(10))

    #expect(store.isRecordingStarting)
    #expect(!store.canStartRecording)
    #expect(store.canStopRecording)

    store.startRecording()

    #expect(pipeline.startRecordingCount == 1)

    store.stopRecording()
    for _ in 0..<200 {
        guard store.recordingState != .stopped || pipeline.stopRecordingCount < 1 else { break }
        try? await Task.sleep(for: .milliseconds(5))
    }

    #expect(store.recordingState == .stopped)
    #expect(store.canStartRecording)
    #expect(!store.canStopRecording)
    #expect(pipeline.startRecordingCount == 1)
    #expect(pipeline.stopRecordingCount >= 1)
}

@Test
@MainActor
func stopRecordingIsIdempotentWhilePipelineStops() async {
    let pipeline = DelayedStopRecordingPipeline()
    let store = StudioStore(mediaPipeline: pipeline)

    store.startRecording()
    try? await Task.sleep(for: .milliseconds(20))

    #expect(store.recordingState == .recording)

    store.stopRecording()

    #expect(store.isRecordingStopping)
    #expect(!store.canStopRecording)
    #expect(!store.canStartRecording)
    #expect(!store.canStartStream)
    #expect(store.recordingStatusDetail == "Stopping local archive")
    #expect(store.setupGenerationStatusDetail == "Finish recording stop before generating setup rules.")

    store.stopRecording()
    try? await Task.sleep(for: .milliseconds(20))

    #expect(pipeline.stopRecordingCount == 1)

    try? await Task.sleep(for: .milliseconds(100))

    #expect(!store.isRecordingStopping)
    #expect(store.recordingState == .stopped)
    #expect(store.canStartRecording)
    #expect(store.canStartStream)
    #expect(pipeline.stopRecordingCount == 1)
    #expect(store.events.filter { $0.title == "Recording stopped" }.count == 1)
}

@Test
@MainActor
func pendingRecordingStartupSuppressesStreamStart() async {
    let pipeline = NonCancellableDelayedRecordingPipeline()
    let store = StudioStore(mediaPipeline: pipeline)

    store.startRecording()
    try? await Task.sleep(for: .milliseconds(10))

    #expect(store.isRecordingStarting)
    #expect(!store.canStartStream)

    store.startStream()

    #expect(pipeline.startStreamCount == 0)

    try? await Task.sleep(for: .milliseconds(120))

    #expect(store.recordingState == .recording)
    #expect(store.canStartStream)

    store.startStream()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(pipeline.startStreamCount == 1)
}
