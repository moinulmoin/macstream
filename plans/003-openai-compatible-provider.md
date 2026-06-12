# Plan 003: Add the OpenAI-compatible local intelligence provider with settings and contract tests

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 03ae477..HEAD -- Sources/MacStreamCore/Services/LocalIntelligenceProvider.swift Sources/MacStreamCore/Services/OpenAICompatibleIntelligenceProvider.swift Sources/MacStreamCore/Stores/StudioStore.swift Sources/MacStream/Support/MacStreamProviderKeychain.swift Sources/MacStream/App/MacStreamApp.swift Sources/MacStream/Views/SettingsView.swift Tests/MacStreamCoreTests/SessionReportAndSetupTests.swift plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M/L
- **Risk**: MED
- **Depends on**: plans/001-split-test-monolith.md
- **Category**: direction / feature
- **Planned at**: commit `03ae477`, 2026-06-11

## Why this matters

MacStream's own AI roadmap names the OpenAI-compatible local server adapter as
the first AI build priority, but the code still only ships deterministic rules
and an MLX shell. Users running LM Studio, Ollama, llama.cpp server, MLX server,
or any other user-owned OpenAI-compatible endpoint cannot use the setup assistant
without this adapter. The existing provider seam, setup prompt builder, setup
JSON decoder, store cancellation guards, and setup UI are already mature; this
plan wires a real HTTP adapter into that seam without putting model calls on the
live capture path.

## Current state

- `docs/current-state.md` says this is the top AI implementation priority:

```markdown
// docs/current-state.md:50-57
## AI Build Priorities

1. Add `OpenAICompatibleLocalIntelligenceProvider` for LM Studio, Ollama, llama.cpp, MLX server, and other user-owned endpoints.
2. Add Foundation Models provider for macOS 26 Apple Intelligence systems.
3. Add provider settings: base URL, model, optional API key, timeout, and capability probe.
4. Add JSON setup-plan smoke test and visible provider fallback.
5. Keep setup generation disabled during streaming, connecting, recording, or stopping.
6. Only revisit managed MLX after benchmarking cold start, tokens/sec, memory pressure, GPU contention, unload reliability, model footprint, and crash isolation.
```

- `README.md` repeats that the runtime is rules-first only until adapters land,
  and that slow sampled-frame review must stay outside the live hot path:

```markdown
// README.md:132-152
## AI direction

MacStream's AI strategy is provider-first, but the current runtime is still
rules-first until the adapters land:

- **Rules** are available today and keep the app deterministic.
- **Foundation Models** are the planned native macOS 26 path where available.
- **OpenAI-compatible local servers** are the planned flexible path for LM Studio,
  Ollama, llama.cpp, MLX server, and other user-owned runtimes.
- **Managed MLX** is not part of the default app until cold start, tokens/sec,
  memory pressure, GPU contention, unload reliability, model footprint, and crash
  isolation are proven.

Good AI use cases for this app:
...
- slow sampled-frame review outside the live hot path.
```

- `Sources/MacStreamCore/Services/LocalIntelligenceProvider.swift` contains the
  provider seam. The new provider must conform to this protocol and must not add
  any model output path into live scene switching:

```swift
// Sources/MacStreamCore/Services/LocalIntelligenceProvider.swift:3-8
public protocol LocalIntelligenceProvider: Sendable {
    var status: LocalIntelligenceStatus { get }

    func generateSetupPlan(for prompt: String) async throws -> SetupPlan
    func explain(_ recommendation: DirectorRecommendation, snapshot: SignalSnapshot) async throws -> String
}
```

- The provider kind enum currently only exposes rules and MLX:

```swift
// Sources/MacStreamCore/Services/LocalIntelligenceProvider.swift:20-31
public enum LocalIntelligenceProviderKind: String, CaseIterable, Identifiable, Sendable {
    case rules
    case mlx

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .rules: "Rule Engine"
        case .mlx: "MLX Local Model"
        }
    }
}
```

- Status is already modeled as provider + availability + detail. Mirror this
  shape instead of inventing UI-specific state:

```swift
// Sources/MacStreamCore/Services/LocalIntelligenceProvider.swift:34-62
public enum LocalIntelligenceAvailability: String, Sendable {
    case available
    case fallback
    case unavailable
    ...
}

public struct LocalIntelligenceStatus: Equatable, Sendable {
    public var provider: LocalIntelligenceProviderKind
    public var availability: LocalIntelligenceAvailability
    public var detail: String
    ...
}
```

- Setup plan prompting and decoding are already centralized. The OpenAI adapter
  must reuse these exact types, not reimplement prompt text or JSON extraction:

```swift
// Sources/MacStreamCore/Services/LocalIntelligenceProvider.swift:95-118
public struct SetupPlanPromptBuilder: Sendable {
    public static let maxStreamDescriptionCharacters = 1_000
    ...
    public func prompt(for streamDescription: String) -> String {
        let streamDescription = Self.boundedStreamDescription(streamDescription)

        return """
        You are configuring MacStream, a local macOS streaming director.
        Return only compact JSON with this schema:
        {"title":"short stream title","profile":"balanced|coding|demo|teaching|podcast","summary":"one sentence switching rule"}

        The live director is deterministic, so do not ask for real-time LLM control.
        Stream description: \(streamDescription)
        """
    }
}
```

```swift
// Sources/MacStreamCore/Services/LocalIntelligenceProvider.swift:120-135
public struct SetupPlanResponseDecoder: Sendable {
    public init() {}

    public func decode(_ response: String) throws -> SetupPlan {
        guard let data = Self.firstJSONObject(in: response) else {
            throw SetupPlanDecodingError.missingJSON
        }

        let decoded = try JSONDecoder().decode(ModelSetupPlan.self, from: data)
        let profile = try Self.profile(for: decoded.profile)
        return SetupPlan(
            title: decoded.title.trimmingCharacters(in: .whitespacesAndNewlines),
            scenes: [.face, .screenAndFace, .screenOnly, .brb],
            directorProfile: profile,
            directorRuleSummary: decoded.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
```

- `RuleBasedLocalIntelligenceProvider` is the non-network fallback. `MLXLocalIntelligenceProvider`
  is the closest structural pattern: it owns a fallback, prompt builder, response
  decoder, and status that reports fallback when runtime support is absent:

```swift
// Sources/MacStreamCore/Services/LocalIntelligenceProvider.swift:254-285
public struct MLXLocalIntelligenceProvider: LocalIntelligenceProvider {
    public static let defaultModelIdentifier = "LiquidAI/LFM2.5-8B-A1B-MLX-4bit"

    public var modelIdentifier: String

    private let fallback: any LocalIntelligenceProvider
    private let promptBuilder = SetupPlanPromptBuilder()
    private let responseDecoder = SetupPlanResponseDecoder()
    ...
    public var status: LocalIntelligenceStatus {
        #if MAC_STREAM_HAS_MLX
        LocalIntelligenceStatus(
            provider: .mlx,
            availability: .available,
            detail: "\(modelIdentifier) setup adapter linked"
        )
        #else
        LocalIntelligenceStatus(
            provider: .mlx,
            availability: .fallback,
            detail: "MLX Swift LM not linked; using fast local rules"
        )
        #endif
    }
```

- `StudioStore` is `@MainActor @Observable` and currently stores the provider as
  an immutable private dependency injected at init:

```swift
// Sources/MacStreamCore/Stores/StudioStore.swift:67-120
private var director = DirectorEngine()
private let mediaPipeline: any MediaPipeline
private let intelligenceProvider: any LocalIntelligenceProvider
...
public init(
    mediaPipeline: any MediaPipeline = PreviewMediaPipeline(),
    intelligenceProvider: any LocalIntelligenceProvider = StubLocalIntelligenceProvider(),
    ...
) {
    ...
    self.mediaPipeline = mediaPipeline
    self.intelligenceProvider = intelligenceProvider
    ...
    self.localIntelligenceStatus = intelligenceProvider.status
```

  Because settings need to switch providers after launch, this plan changes the
  provider storage to mutable and adds a guarded setter; do not work around this
  by creating a second store.

- Setup generation is already guarded and cancellable. Reuse this behavior; do
  not duplicate stream/recording blocking checks in the provider:

```swift
// Sources/MacStreamCore/Stores/StudioStore.swift:1220-1272
public func generateSetupPlan() {
    guard canGenerateSetupPlan else {
        if let setupGenerationBlockedReason {
            setupSummary = setupGenerationBlockedReason
            addWarningEventIfNeeded(title: "Setup paused", detail: setupGenerationBlockedReason)
        }
        return
    }

    let prompt = SetupPlanPromptBuilder.boundedStreamDescription(setupPrompt)
    ...
    isGeneratingSetupPlan = true
    localIntelligenceStatus = intelligenceProvider.status
    setupSummary = "Generating setup rules..."
    ...
    let plan = try await intelligenceProvider.generateSetupPlan(for: prompt)
    ...
} catch {
    guard isCurrentSetupGeneration(generationID) else { return }
    setupSummary = "Setup failed."
    addEvent(kind: .warning, title: "Setup failed", detail: error.localizedDescription)
}
```

- Blocking covers connecting, live preview/streaming, recording start/stop,
  recording, and blank prompts:

```swift
// Sources/MacStreamCore/Stores/StudioStore.swift:2044-2071
private var setupGenerationBlockedReason: String? {
    if isStreamConnecting { return "Finish connecting before generating setup rules." }
    if streamState.isLive { ... }
    if isRecordingStarting { return "Finish recording startup before generating setup rules." }
    if isRecordingStopping { return "Finish recording stop before generating setup rules." }
    if recordingState == .recording { return "Stop recording before generating local setup rules." }
    if SetupPlanPromptBuilder.boundedStreamDescription(setupPrompt).isEmpty {
        return "Describe the stream before generating setup rules."
    }

    return nil
}
```

- The settings UI has the setup section where provider controls belong:

```swift
// Sources/MacStream/Views/SettingsView.swift:62-90
Section("Setup Rules") {
    TextField("Stream description", text: setupPromptBinding, axis: .vertical)
        .lineLimit(2...4)

    Button {
        store.generateSetupPlan()
    } label: {
        ...
        Label("Generate Rules", systemImage: "wand.and.stars")
    }
    .disabled(!store.canGenerateSetupPlan)
    .help(store.setupGenerationStatusDetail)

    LabeledContent("Local model") {
        Text(store.localIntelligenceStatus.availability.title)
            .foregroundStyle(statusTint(store.localIntelligenceStatus.availability))
    }

    LabeledContent("Profile") {
        Text(store.directorProfile.kind.title)
    }
}
```

- App persistence currently uses `@AppStorage` for non-secret preferences and
  Keychain for destination endpoint data. Follow this split: base URL, model,
  timeout, and selected provider kind may use `@AppStorage`; API key must go to
  Keychain only.

```swift
// Sources/MacStream/App/MacStreamApp.swift:16-33
@AppStorage("recordWhileStreaming") private var recordWhileStreaming = false
@AppStorage("directorCountdownSeconds") private var directorCountdownSeconds = 2.0
...
@AppStorage("destinationName") private var destinationName = "Preview Session"
...
@State private var store = StudioStore(
    mediaPipeline: SystemMediaPipeline(),
    intelligenceProvider: RuleBasedLocalIntelligenceProvider(),
    signalProvider: SystemSignalProvider(),
    performanceMonitor: MacSystemPerformanceMonitor()
)
```

```swift
// Sources/MacStream/App/MacStreamApp.swift:169-196
private func applySavedDestination() {
    let mode = StreamDestinationMode(rawValue: destinationModeRaw) ?? .preview
    let rtmpURL = MacStreamDestinationKeychain.loadRTMPURL() ?? (mode == .rtmp ? "" : "preview")
    ...
}

private func saveDestination(_ destination: StreamDestination) {
    destinationModeRaw = destination.mode.rawValue
    destinationName = destination.name

    if destination.isPersistableEndpoint {
        if !MacStreamDestinationKeychain.saveRTMPURL(destination.rtmpURL) {
            store.reportPersistenceFailure("RTMP destination could not be saved to Keychain.")
        }
    } else {
        if !MacStreamDestinationKeychain.deleteRTMPURL() {
            store.reportPersistenceFailure("RTMP destination could not be removed from Keychain.")
        }
    }
}
```

- The existing Keychain helper shape to copy is small and explicit:

```swift
// Sources/MacStream/Support/MacStreamDestinationKeychain.swift:4-62
enum MacStreamDestinationKeychain {
    private static let service = "com.ideaplexa.macstream.destination"
    private static let account = "rtmp-url"

    static func loadRTMPURL() -> String? { ... }

    @discardableResult
    static func saveRTMPURL(_ value: String) -> Bool { ... }

    @discardableResult
    static func deleteRTMPURL() -> Bool { ... }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
```

- Existing provider tests live in `Tests/MacStreamCoreTests/DirectorEngineTests.swift`
  at commit `03ae477`. After Plan 001, they live in
  `Tests/MacStreamCoreTests/SessionReportAndSetupTests.swift`, with shared fakes
  in `Tests/MacStreamCoreTests/TestSupport.swift` and `private` removed.
  Patterns to reuse:

```swift
// Tests/MacStreamCoreTests/DirectorEngineTests.swift:4917-4931
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
```

```swift
// Tests/MacStreamCoreTests/DirectorEngineTests.swift:4966-4979
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
```

```swift
// Tests/MacStreamCoreTests/DirectorEngineTests.swift:5014-5027
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
```

```swift
// Tests/MacStreamCoreTests/DirectorEngineTests.swift:5154-5179
@Test
@MainActor
func setupRulesCancelInFlightGenerationWhenStreamStarts() async {
    let provider = CancellableDelayedSetupProvider()
    let store = StudioStore(
        mediaPipeline: SpyMediaPipeline(),
        intelligenceProvider: provider
    )
    ...
    store.startStream()
    ...
    #expect(!store.isGeneratingSetupPlan)
    #expect(store.setupSummary == "Stop preview before generating local setup rules.")
    #expect(await provider.cancelledCount() == 1)
}
```

```swift
// Tests/MacStreamCoreTests/DirectorEngineTests.swift:5934-5946
private struct DelayedSetupProvider: LocalIntelligenceProvider {
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
```

```swift
// Tests/MacStreamCoreTests/DirectorEngineTests.swift:6040-6065
private actor PromptCapturingSetupProvider: LocalIntelligenceProvider {
    nonisolated let status = LocalIntelligenceStatus(
        provider: .mlx,
        availability: .fallback,
        detail: "test fallback"
    )
    ...
    func generateSetupPlan(for prompt: String) async throws -> SetupPlan {
        self.prompt = prompt
        return plan
    }
    ...
    func receivedPrompt() -> String? {
        prompt
    }
}
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift check | `git diff --stat 03ae477..HEAD -- Sources/MacStreamCore/Services/LocalIntelligenceProvider.swift Sources/MacStreamCore/Services/OpenAICompatibleIntelligenceProvider.swift Sources/MacStreamCore/Stores/StudioStore.swift Sources/MacStream/Support/MacStreamProviderKeychain.swift Sources/MacStream/App/MacStreamApp.swift Sources/MacStream/Views/SettingsView.swift Tests/MacStreamCoreTests/SessionReportAndSetupTests.swift plans/README.md` | no output, or only changes you have reconciled against this plan |
| Build | `swift build` | exit 0, `Build complete!` |
| Tests | `swift test` (from repo root) | final line contains `Test run with 242 tests in 0 suites passed` if Plan 001 preserved the baseline 233 and this plan adds 9 tests |
| Find provider kind | `grep -R "case openAICompatible" Sources/MacStreamCore/Services` | one match in `LocalIntelligenceProvider.swift` |
| Count new provider tests | `grep -c '^func openAICompatible' Tests/MacStreamCoreTests/SessionReportAndSetupTests.swift` | `9` |
| Check API key is not in defaults | `grep -R "AppStorage(.*apiKey\|UserDefaults.*apiKey\|providerAPIKey" Sources/MacStream` | no matches except non-secret UI/state names if you deliberately used `providerAPIKey` only as a transient `@State` value; no `@AppStorage` or `UserDefaults` secret write |
| Scope check | `git status --short` | only files listed in Scope are modified/created, plus `plans/README.md` status row |

## Scope

**In scope** (the only files you should modify or create):
- `Sources/MacStreamCore/Services/OpenAICompatibleIntelligenceProvider.swift` (create)
- `Tests/MacStreamCoreTests/SessionReportAndSetupTests.swift`
- `Sources/MacStreamCore/Services/LocalIntelligenceProvider.swift`
- `Sources/MacStream/Support/MacStreamProviderKeychain.swift` (create)
- `Sources/MacStream/Views/SettingsView.swift`
- `Sources/MacStream/App/MacStreamApp.swift`
- `Sources/MacStreamCore/Stores/StudioStore.swift`
- `plans/README.md` (status row only)

**Out of scope** (do NOT touch):
- Any live sample-buffer callback, `MediaPipeline`, capture, director-loop, or
  stream-publish code. This plan adds setup-generation networking only.
- `Package.swift` — SwiftPM discovers source and test files automatically.
- `Sources/MacStreamCore/Services/LocalIntelligenceProvider.swift` prompt text
  or decoder behavior, except adding the enum case/title.
- `README.md` and `docs/` — roadmap text already describes this work.
- Any secret migration into `@AppStorage`, `UserDefaults`, logs, plan files,
  events, or source-text tests.
- Auto-generating setup plans on launch, on setting changes, while streaming,
  while connecting, while recording, or without the user pressing Generate.

## Git workflow

- Commit directly on `main` (repo convention — no PRs unless asked).
- Message style follows the existing log (`feat:`, `fix:`, `refactor:`, `test:`,
  `ci:` prefixes), e.g. `feat: add openai-compatible setup provider`.
- Do NOT push unless the operator explicitly instructed it.

## Steps

### Step 1: Add the OpenAI-compatible provider and HTTP contract tests first

Create `Sources/MacStreamCore/Services/OpenAICompatibleIntelligenceProvider.swift`
with a public provider and configuration. Keep this in `MacStreamCore`; it must
not depend on SwiftUI, Keychain, AppKit, or app-level settings.

Required shape, adapt to surrounding code:

```swift
import Foundation

public struct OpenAICompatibleProviderConfiguration: Equatable, Sendable {
    public static let defaultBaseURL = URL(string: "http://127.0.0.1:1234/v1")!
    public static let defaultModel = "local-model"
    public static let defaultTimeout: TimeInterval = 30

    public var baseURL: URL
    public var model: String
    public var apiKey: String?
    public var timeout: TimeInterval

    public init(
        baseURL: URL = Self.defaultBaseURL,
        model: String = Self.defaultModel,
        apiKey: String? = nil,
        timeout: TimeInterval = Self.defaultTimeout
    ) { ... }
}

public struct OpenAICompatibleLocalIntelligenceProvider: LocalIntelligenceProvider {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public var configuration: OpenAICompatibleProviderConfiguration

    private let transport: Transport
    private let promptBuilder = SetupPlanPromptBuilder()
    private let responseDecoder = SetupPlanResponseDecoder()
    private let fallback: any LocalIntelligenceProvider
    private let probedStatus: LocalIntelligenceStatus?

    public init(
        configuration: OpenAICompatibleProviderConfiguration,
        fallback: any LocalIntelligenceProvider = RuleBasedLocalIntelligenceProvider(),
        probedStatus: LocalIntelligenceStatus? = nil,
        transport: @escaping Transport = { request in try await URLSession.shared.data(for: request) }
    ) { ... }

    public func probeCapabilities() async -> LocalIntelligenceStatus { ... }

    public func replacingProbedStatus(_ status: LocalIntelligenceStatus) -> Self { ... }
}
```

Connection probe contract:

- `probeCapabilities()` is the only network reachability probe. It performs
  `GET {baseURL}/models` using the same normalized base-URL helper as
  chat-completions, so both `http://host:1234` and `http://host:1234/v1` produce
  a single `/v1/models` path when appropriate and never double slashes.
- Probe request headers: `Accept: application/json` and `Authorization:
  Bearer <apiKey>` only when the trimmed API key is non-empty. Do not send a
  request body.
- `URLRequest.timeoutInterval == min(configuration.timeout, 10)` so the settings
  probe cannot hang the UI for a long generation timeout. Name the cap
  `public static let probeTimeout: TimeInterval = 10`; if you choose a different
  probe timeout, make it a named constant and test it.
- A probe succeeds only for HTTP status `200...299`; the response body may be
  ignored except that empty/non-JSON bodies should still be accepted if the HTTP
  status is successful, because some local servers return minimal model lists.
- Successful probe returns:
  `LocalIntelligenceStatus(provider: .openAICompatible, availability: .available, detail: "Local server reachable for \(configuration.model).")`
- HTTP failure status, transport error, invalid URL, empty model, or empty base
  URL returns a status with `.unavailable` and a concise user-visible detail.
  Include the HTTP status code in the detail for non-2xx responses; do not include
  API keys or request bodies.
- Before any successful probe, `status` must be `.fallback` for syntactically
  configured settings and `.unavailable` for missing/invalid settings. After a
  successful or failed probe, `status` must come from the probed status stored in
  the provider instance.
- Because `LocalIntelligenceProvider.status` is synchronous, do not add
  `store.refreshLocalIntelligenceStatus()` after a probe; it would read the old
  provider and can show stale status. SettingsView must call
  `let status = await provider.probeCapabilities()`, then replace the store's
  provider with `store.setIntelligenceProvider(provider.replacingProbedStatus(status))`.
  That setter immediately updates `store.localIntelligenceStatus` from the
  replacement provider.

Provider behavior:

- `status.provider == .openAICompatible` once Step 2 adds the enum case.
- If `configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)` is
  empty or `configuration.baseURL` cannot form request URLs, report `.unavailable`
  with a user-visible detail such as `Configure a local OpenAI-compatible model.`
- Otherwise report `.fallback` before a probe has succeeded, with a detail that
  makes clear rules are still available if the local server fails, e.g.
  `Local server configured; rules fallback available.`
- Do not call the fallback inside `generateSetupPlan` on network/decode failure.
  Throw the failure; `StudioStore.generateSetupPlan()` already catches and shows
  `Setup failed.` The fallback is for status/explanations and for future UI copy,
  mirroring the MLX provider's status shape.
- `explain(_:snapshot:)` should delegate to `fallback.explain(...)`. This plan
  only implements setup-plan HTTP calls.

HTTP behavior:

- `generateSetupPlan(for:)` builds the model prompt with
  `SetupPlanPromptBuilder().prompt(for: prompt)`.
- Non-streaming request: `POST {baseURL}/chat/completions`.
- Normalize endpoint construction so both `http://host:1234` and
  `http://host:1234/v1` work; do not produce double slashes.
- Request headers: `Content-Type: application/json`, `Accept: application/json`,
  and `Authorization: Bearer <apiKey>` only when the trimmed API key is non-empty.
- `URLRequest.timeoutInterval == configuration.timeout`.
- JSON body shape:

```json
{
  "model": "<configuration.model>",
  "messages": [
    { "role": "system", "content": "Return only the requested MacStream setup JSON." },
    { "role": "user", "content": "<SetupPlanPromptBuilder prompt>" }
  ],
  "temperature": 0.1,
  "stream": false,
  "response_format": { "type": "json_object" }
}
```

  Keep `response_format` as a best-effort hint only. The provider must tolerate
  servers that ignore it because `SetupPlanResponseDecoder` extracts the first
  complete JSON object from plain text.
- Decode response JSON as `choices[0].message.content`, then pass that string to
  `SetupPlanResponseDecoder().decode(...)`.
- On HTTP status `>= 400`, missing choices/content, transport error, or setup
  decode error, throw. Do not log request bodies or API keys.

Add tests in `Tests/MacStreamCoreTests/SessionReportAndSetupTests.swift` after
Plan 001 has moved setup/provider tests there. Use an injected transport closure;
do not use network, `URLProtocol`, global `URLSessionConfiguration`, sleeps, or
real local servers.

Add local test helper shapes in the same test file if needed:

```swift
private struct CapturedRequest: Sendable {
    var request: URLRequest
    var body: Data
}

private actor OpenAICompatibleTransportSpy {
    private(set) var requests: [CapturedRequest] = []
    var response: (Data, URLResponse)

    func transport(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let body = request.httpBody ?? Data()
        requests.append(CapturedRequest(request: request, body: body))
        return response
    }
}
```

Tests to add now (names must start with `openAICompatible` so the count check is
machine-checkable):

1. `openAICompatibleProviderDecodesChatCompletionSetupPlan` — transport returns
   HTTP 200 with `choices[0].message.content` containing valid setup JSON; assert
   `SetupPlan.title`, `.directorProfile.kind`, `.scenes`, and summary.
2. `openAICompatibleProviderSendsBoundedSetupPrompt` — pass a prompt longer than
   `SetupPlanPromptBuilder.maxStreamDescriptionCharacters`; inspect request body
   and assert it contains the prefix, does not contain the suffix, includes the
   model, `stream: false`, and the chat-completions path.
3. `openAICompatibleProviderThrowsSetupPlanDecodingErrorForMalformedContent` —
   HTTP 200 with content lacking any JSON object; assert the thrown error is
   `SetupPlanDecodingError.missingJSON` (or matches `SetupPlanDecodingError`).
4. `openAICompatibleProviderThrowsForHTTPFailure` — HTTP 500 response throws and
   does not return fallback rules.
5. `openAICompatibleProviderAppliesAuthorizationHeaderOnlyWhenAPIKeyPresent` —
   one provider with `apiKey: nil` or whitespace has no `Authorization` header;
   one provider with a non-empty key has `Authorization == "Bearer ..."`. Use a
   dummy key string only; no real secret.
6. `openAICompatibleProviderAppliesRequestTimeout` — assert
   `request.timeoutInterval == configuration.timeout`.
7. `openAICompatibleProviderProbeReturnsAvailableForModelsSuccess` — transport
   observes `GET /models`, no body, probe timeout, and HTTP 200; assert returned
   status is `.available` with provider `.openAICompatible`.
8. `openAICompatibleProviderProbeReturnsUnavailableForModelsFailure` — HTTP 500
   or thrown transport error from `/models` returns `.unavailable`, includes the
   status/failure in detail, and does not throw.
9. `openAICompatibleProviderProbeStatusUpdatesStoreWhenProviderIsReplaced` —
   create a provider, await a successful probe, call
   `store.setIntelligenceProvider(provider.replacingProbedStatus(status))`, and
   assert `store.localIntelligenceStatus.availability == .available`. This is the
   machine-checkable path that prevents a stale `refreshLocalIntelligenceStatus()`
   implementation from passing.

Keep store-level blocked-generation tests as references only. Existing tests
`setupRulesCancelInFlightGenerationWhenStreamStarts` and nearby recording/
connecting tests already cover store blocking; do not duplicate them here.

**Verify**: `grep -c '^func openAICompatible' Tests/MacStreamCoreTests/SessionReportAndSetupTests.swift` → `9`. Compilation is verified in Step 2 after the enum case exists.

### Step 2: Add `.openAICompatible` to the provider kind enum

Edit `Sources/MacStreamCore/Services/LocalIntelligenceProvider.swift` only in
`LocalIntelligenceProviderKind`:

```swift
public enum LocalIntelligenceProviderKind: String, CaseIterable, Identifiable, Sendable {
    case rules
    case mlx
    case openAICompatible

    public var title: String {
        switch self {
        case .rules: "Rule Engine"
        case .mlx: "MLX Local Model"
        case .openAICompatible: "Local server (OpenAI-compatible)"
        }
    }
}
```

Do not change `SetupPlanPromptBuilder`, `SetupPlanResponseDecoder`, rules
provider behavior, or MLX provider behavior.

**Verify**: `grep -R "case openAICompatible" Sources/MacStreamCore/Services` →
one match in `Sources/MacStreamCore/Services/LocalIntelligenceProvider.swift`.
Then run `swift test --filter openAICompatible` → exit 0, 9 tests pass.

### Step 3: Add the app Keychain helper for the provider API key

Create `Sources/MacStream/Support/MacStreamProviderKeychain.swift` by mirroring
`MacStreamDestinationKeychain`'s shape. It is app-level support code, not core.

Required shape, adapt to surrounding code:

```swift
import Foundation
import Security

enum MacStreamProviderKeychain {
    private static let service = "com.ideaplexa.macstream.provider"
    private static let openAICompatibleAPIKeyAccount = "openai-compatible-api-key"

    static func loadOpenAICompatibleAPIKey() -> String? { ... }

    @discardableResult
    static func saveOpenAICompatibleAPIKey(_ value: String) -> Bool { ... }

    @discardableResult
    static func deleteOpenAICompatibleAPIKey() -> Bool { ... }

    private static func baseQuery(account: String) -> [String: Any] { ... }
}
```

Rules:

- Trim whitespace/newlines before saving.
- Empty string deletes the item.
- `load...` returns `nil` for missing or empty values.
- Return `false` only for Keychain errors other than item-not-found on delete.
- Never write the key to `@AppStorage`, `UserDefaults`, logs, events, docs, or
  tests as a real value.

**Verify**: `grep -R "OpenAICompatibleAPIKey" Sources/MacStream/Support/MacStreamProviderKeychain.swift` → shows only the three helper methods/account constant. `grep -R "AppStorage(.*apiKey\|UserDefaults.*apiKey" Sources/MacStream` → no matches.

### Step 4: Extend SettingsView with provider settings and connection probe UI

Edit `Sources/MacStream/Views/SettingsView.swift` inside the existing
`Section("Setup Rules")` from lines 62-90.

Add these settings:

- Provider picker using `LocalIntelligenceProviderKind.allCases` and the titles.
- When `.openAICompatible` is selected, show:
  - `TextField("Base URL", text: ...)`
  - `TextField("Model", text: ...)`
  - `SecureField("API key", text: ...)`
  - timeout control in seconds, clamped to a sane range such as `5...120`
  - `Button("Test connection")` that calls the provider's `probeCapabilities()`
    through a task and shows reachability text.
- Keep the existing Generate Rules button explicit. Do not auto-generate a plan
  when the provider, model, base URL, API key, or timeout changes.
- Keep `.disabled(!store.canGenerateSetupPlan)` on Generate Rules. Generation
  must remain disabled while streaming, connecting, recording, or stopping.
- Continue showing `store.localIntelligenceStatus.availability.title` and
  provider detail. Prefer adding a second line with `store.localIntelligenceStatus.detail`
  over replacing the existing status.

Bindings/persistence shape:

- Use `@AppStorage` for non-secret values in `SettingsView` or route bindings
  through `MacStreamApp` if you centralize persistence there:
  - `localIntelligenceProviderKind`
  - `openAICompatibleBaseURL`
  - `openAICompatibleModel`
  - `openAICompatibleTimeout`
- Use transient `@State` for the API key text shown in `SecureField`; load it
  from `MacStreamProviderKeychain` on appear, save/delete via the Keychain helper
  on change or on submit. Do not use `@AppStorage` for the API key.
- On settings changes, rebuild the configured provider and call the store setter
  added in Step 5. If you are applying this plan strictly linearly, add the
  `StudioStore.setIntelligenceProvider(_:)` method from Step 5 before compiling
  SettingsView; do not introduce a temporary second source of truth.

Connection probe shape, adapt to surrounding code:

```swift
@State private var providerProbeTask: Task<Void, Never>?
@State private var providerProbeMessage = "Not checked"

private func testOpenAICompatibleConnection() {
    providerProbeTask?.cancel()
    providerProbeMessage = "Checking..."
    let provider = makeOpenAICompatibleProviderFromSettings()
    providerProbeTask = Task { @MainActor in
        let status = await provider.probeCapabilities()
        guard !Task.isCancelled else { return }
        providerProbeMessage = status.availability == .available ? "Reachable" : status.detail
        _ = store.setIntelligenceProvider(provider.replacingProbedStatus(status))
    }
}
```

If strict concurrency rejects the exact `@MainActor` task shape, adjust it to the
repo's Swift 6 conventions; keep UI state updates on the main actor.

**Verify**: run the SettingsView grep checks listed in Step 5. Full compilation
is verified after Step 5 because this UI depends on `setIntelligenceProvider(_:)`.


### Step 5: Wire provider selection and persistence at launch

Edit `Sources/MacStream/App/MacStreamApp.swift` and
`Sources/MacStreamCore/Stores/StudioStore.swift`.

In `StudioStore`:

- Change `private let intelligenceProvider` to mutable storage:

```swift
private var intelligenceProvider: any LocalIntelligenceProvider
```

- Add a public guarded setter. Required behavior:
  - no-op and report/return false while `isGeneratingSetupPlan` is true;
  - no-op and report/return false when `setupGenerationBlockedReason` is non-nil
    because the stream is connecting/live or recording is starting/stopping/live;
  - update `localIntelligenceStatus` immediately when accepted;
  - do not cancel streams, recordings, scans, or director-loop tasks;
  - do not generate a setup plan.

Shape, adapt to current naming:

```swift
@discardableResult
public func setIntelligenceProvider(_ provider: any LocalIntelligenceProvider) -> Bool {
    guard !isGeneratingSetupPlan else {
        addWarningEventIfNeeded(title: "Provider unchanged", detail: "Finish setup generation before changing providers.")
        return false
    }

    if let setupGenerationBlockedReason {
        addWarningEventIfNeeded(title: "Provider unchanged", detail: setupGenerationBlockedReason)
        return false
    }

    intelligenceProvider = provider
    localIntelligenceStatus = provider.status
    return true
}

// Do not add a refreshLocalIntelligenceStatus() method for probe results.
// Probe status reaches the store only by replacing the provider with
// provider.replacingProbedStatus(status) through setIntelligenceProvider(_:).
```

If using `setupGenerationBlockedReason` would also block provider changes for a
blank prompt, split the logic so only live/connecting/recording states block
provider switching. A blank setup prompt should block generation, not necessarily
provider configuration.

In `MacStreamApp`:

- Add `@AppStorage` keys for non-secret provider settings.
- On launch, build the provider from persisted settings and Keychain key before
  or during the `.task` that applies launch defaults. The current store is
  constructed with rules at lines 28-33, so the honest wiring is:
  1. initialize with rules, as today;
  2. in `.task`, load non-secret settings from `@AppStorage`, load API key from
     `MacStreamProviderKeychain`, construct provider, and call
     `store.setIntelligenceProvider(...)` before any user-triggered generation.
- When SettingsView changes provider settings, save non-secrets through
  `@AppStorage`, save/delete the API key through Keychain, rebuild the provider,
  and call `store.setIntelligenceProvider(...)`.

Provider factory shape, adapt to the app's structure:

```swift
private func makeLocalIntelligenceProvider() -> any LocalIntelligenceProvider {
    let kind = LocalIntelligenceProviderKind(rawValue: localIntelligenceProviderKindRaw) ?? .rules
    switch kind {
    case .rules:
        return RuleBasedLocalIntelligenceProvider()
    case .mlx:
        return MLXLocalIntelligenceProvider()
    case .openAICompatible:
        let apiKey = MacStreamProviderKeychain.loadOpenAICompatibleAPIKey()
        return OpenAICompatibleLocalIntelligenceProvider(
            configuration: OpenAICompatibleProviderConfiguration(
                baseURL: URL(string: openAICompatibleBaseURL) ?? OpenAICompatibleProviderConfiguration.defaultBaseURL,
                model: openAICompatibleModel,
                apiKey: apiKey,
                timeout: openAICompatibleTimeout
            )
        )
    }
}
```

Do not store the API key in `@AppStorage` just to simplify this factory. If
SettingsView owns the API-key editing state, pass only a closure/factory boundary
needed to save/delete/load through Keychain.

**Verify**: `swift build` → exit 0, `Build complete!`. Then run these
machine-checkable wiring checks:

- `grep -R "LocalIntelligenceProviderKind.allCases" Sources/MacStream/Views/SettingsView.swift` → one provider picker data source.
- `grep -R 'TextField("Base URL"\|TextField("Model"\|SecureField("API key"\|Button("Test connection"' Sources/MacStream/Views/SettingsView.swift` → all four OpenAI-compatible settings controls.
- `grep -R "MacStreamProviderKeychain.loadOpenAICompatibleAPIKey\|MacStreamProviderKeychain.saveOpenAICompatibleAPIKey\|MacStreamProviderKeychain.deleteOpenAICompatibleAPIKey" Sources/MacStream` → call sites for load/save/delete; no API-key persistence bypass.
- `grep -R "case .openAICompatible\|OpenAICompatibleLocalIntelligenceProvider(" Sources/MacStream/App/MacStreamApp.swift` → the launch factory handles `.openAICompatible` and constructs the provider.
- `grep -R "func setIntelligenceProvider\|store.setIntelligenceProvider" Sources/MacStreamCore/Stores/StudioStore.swift Sources/MacStream` → one store setter definition plus app/settings call sites.
- `grep -R "AppStorage(.*apiKey\|UserDefaults.*apiKey" Sources/MacStream` → no matches.

### Step 6: Run the full suite and update the plan index row

Run the full test suite from the repo root after all core/app wiring compiles.
The expected count is baseline 233 + 9 new provider/probe contract tests = 242 tests.
If Plan 001 added an `AGENTS.md` but did not add tests, the count remains 242.
If a reviewer explicitly tells you the baseline changed, reconcile the count
before changing this plan's Done criteria.

Then update `plans/README.md` status row for Plan 003 only. If the row does not
exist, add a row consistent with the index format introduced by Plan 001:

```markdown
| 003 | Add the OpenAI-compatible local intelligence provider with settings and contract tests | P1 | M/L | 001 | DONE |
```

Do not edit other plan rows except to preserve table formatting.

**Verify**: `swift test` → final line contains
`Test run with 242 tests in 0 suites passed`. `git status --short` → only the
in-scope files are modified/created.

## Test plan

Add 9 contract tests in `Tests/MacStreamCoreTests/SessionReportAndSetupTests.swift`
using the injected transport on `OpenAICompatibleLocalIntelligenceProvider`:

1. `openAICompatibleProviderDecodesChatCompletionSetupPlan` — valid
   chat-completions response content decodes to typed `SetupPlan`.
2. `openAICompatibleProviderSendsBoundedSetupPrompt` — request body uses
   `SetupPlanPromptBuilder` output bounded at
   `SetupPlanPromptBuilder.maxStreamDescriptionCharacters`.
3. `openAICompatibleProviderThrowsSetupPlanDecodingErrorForMalformedContent` —
   malformed content throws the setup-plan decoder error instead of falling back.
4. `openAICompatibleProviderThrowsForHTTPFailure` — HTTP 500 throws.
5. `openAICompatibleProviderAppliesAuthorizationHeaderOnlyWhenAPIKeyPresent` —
   no API key means no `Authorization`; non-empty API key means Bearer header.
6. `openAICompatibleProviderAppliesRequestTimeout` — configured timeout is on
   the `URLRequest`.
7. `openAICompatibleProviderProbeReturnsAvailableForModelsSuccess` — `GET /models`
   over injected transport returns `.available` and records the probe timeout.
8. `openAICompatibleProviderProbeReturnsUnavailableForModelsFailure` — failed
   `/models` returns `.unavailable` without throwing.
9. `openAICompatibleProviderProbeStatusUpdatesStoreWhenProviderIsReplaced` —
   replacing the store provider with a probed-status provider immediately updates
   `store.localIntelligenceStatus`.

Use these existing tests as structural patterns after Plan 001 moves them into
`SessionReportAndSetupTests.swift`: `setupRulesBoundPromptSentToProvider`
(original `DirectorEngineTests.swift:4919`),
`setupPlanResponseDecoderUsesFirstCompleteJSONObject` (original line 5015),
`mlxLocalProviderFallsBackWhenRuntimeIsNotLinked` (original line 4967), and
`setupRulesCancelInFlightGenerationWhenStreamStarts` (original line 5156).
Shared fakes such as `DelayedSetupProvider`, `CancellableDelayedSetupProvider`,
and `PromptCapturingSetupProvider` live in post-001 `TestSupport.swift`; do not
make them private again.

Store-level blocked generation while connecting/recording is already covered by
existing tests around `setupRulesCancelInFlightGenerationWhenStreamStarts`; do
not duplicate it. The new store status-update path is covered by
`openAICompatibleProviderProbeStatusUpdatesStoreWhenProviderIsReplaced`.

Verification: `swift test --filter openAICompatible` → 9 new tests pass;
`swift test` → final summary contains `Test run with 242 tests in 0 suites passed`.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `swift build` exits 0 with `Build complete!`.
- [ ] `swift test --filter openAICompatible` exits 0 and runs 9 tests.
- [ ] `swift test` from repo root exits 0; final summary contains
      `Test run with 242 tests in 0 suites passed`.
- [ ] `grep -R "case openAICompatible" Sources/MacStreamCore/Services` returns
      exactly one enum case match.
- [ ] `grep -c '^func openAICompatible' Tests/MacStreamCoreTests/SessionReportAndSetupTests.swift` returns `9`.
- [ ] `grep -R "LocalIntelligenceProviderKind.allCases" Sources/MacStream/Views/SettingsView.swift` returns the provider picker data source.
- [ ] `grep -R 'TextField("Base URL"\|TextField("Model"\|SecureField("API key"\|Button("Test connection"' Sources/MacStream/Views/SettingsView.swift` returns all four OpenAI-compatible settings controls.
- [ ] `grep -R "MacStreamProviderKeychain.loadOpenAICompatibleAPIKey\|MacStreamProviderKeychain.saveOpenAICompatibleAPIKey\|MacStreamProviderKeychain.deleteOpenAICompatibleAPIKey" Sources/MacStream` returns helper usage call sites and no API-key persistence bypass.
- [ ] `grep -R "case .openAICompatible\|OpenAICompatibleLocalIntelligenceProvider(" Sources/MacStream/App/MacStreamApp.swift` returns the app provider factory branch and construction.
- [ ] `grep -R "func setIntelligenceProvider\|store.setIntelligenceProvider" Sources/MacStreamCore/Stores/StudioStore.swift Sources/MacStream` returns one setter definition plus app/settings call sites.
- [ ] `grep -R "AppStorage(.*apiKey\|UserDefaults.*apiKey" Sources/MacStream`
      returns no matches.
- [ ] `grep -R "URLSession.shared.data" Sources/MacStreamCore Sources/MacStream`
      shows only the provider default transport in
      `OpenAICompatibleIntelligenceProvider.swift` and no live media/capture path.
- [ ] `git status --short` shows only the in-scope files modified/created.
- [ ] `plans/README.md` status row for Plan 003 is updated to `DONE`.

## STOP conditions

Stop and report back (do not improvise) if:

- The drift check shows changes in any in-scope file and the current code no
  longer matches the excerpts above.
- Plan 001 has not been applied yet, so
  `Tests/MacStreamCoreTests/SessionReportAndSetupTests.swift` does not exist.
- `StudioStore` no longer owns provider injection through an `intelligenceProvider`
  initializer parameter, or provider storage has already been replaced by a
  different architecture. Do not create a second source of truth.
- Any implementation path would store the OpenAI-compatible API key in
  `@AppStorage`, `UserDefaults`, logs, setup events, docs, tests, or this plan.
- A target server rejects `response_format`; do not treat that as a reason to
  remove tolerant decoding. Keep request-body `response_format` best-effort and
  continue decoding `choices[0].message.content` with `SetupPlanResponseDecoder`.
- You find yourself adding networking to `MediaPipeline`, capture callbacks,
  director-loop sampling, or any per-frame/live hot path.
- You find yourself auto-generating setup plans on launch or settings changes
  instead of requiring the explicit Generate Rules button.
- A step's verification fails twice after a reasonable fix attempt.
- The fix requires touching files outside Scope.

## Maintenance notes

- This provider is a setup-assistant adapter only. Future preflight coach,
  clip-title, post-session, or sampled-frame features should add separate calls
  and tests; do not route live scene switching through model output.
- Reviewers should scrutinize request construction, timeout application, API-key
  handling, and failure semantics. Network/decode failures must throw and surface
  through the existing `StudioStore` setup failure path; they must not silently
  apply fallback rules as if the configured model succeeded.
- Settings persistence deliberately splits non-secrets (`@AppStorage`) from the
  API key (Keychain). Preserve this split for all future provider credentials.
- If more OpenAI-compatible endpoints need quirks later, prefer configuration or
  small request-shaping helpers inside `OpenAICompatibleIntelligenceProvider`
  over server-specific branches in `StudioStore` or `SettingsView`.
