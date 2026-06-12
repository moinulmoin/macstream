# Plan 004: Wire director cue explanations and a deterministic preflight coach into the UI

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 03ae477..HEAD -- Sources/MacStreamCore/Services/PreflightCoach.swift Sources/MacStreamCore/Stores/StudioStore.swift Sources/MacStream/Views/DirectorPanelView.swift Sources/MacStream/Views/CapturePreflightView.swift Tests/MacStreamCoreTests/TestSupport.swift Tests/MacStreamCoreTests/CapturePreflightModelTests.swift Tests/MacStreamCoreTests/CaptureScanAndReadinessTests.swift Tests/MacStreamCoreTests/StudioStoreDirectorLoopTests.swift Tests/MacStreamCoreTests/SourceTextGuardrailTests.swift plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW/MED
- **Depends on**: plans/001-split-test-monolith.md
- **Category**: direction / feature
- **Planned at**: commit `03ae477`, 2026-06-11

## Why this matters

The repo already promises two local-intelligence use cases that are one interface away from shipping: director explanations and a preflight coach. Today the rules provider can explain a cue, but the UI never calls it; preflight readiness is typed, but the advice is scattered across the capture panel, setup checklist, and start-blocking strings. This plan makes both features deterministic and local-first: explanations are display-only and never affect scene switching, and the coach is a pure rules builder over existing typed state with no model call and no passive permission prompts. Plan 003 will make explanations richer when a real local provider lands, but this plan works fully with the existing rules provider and does not depend on 003.

## Current state

- `README.md` and `docs/current-state.md` explicitly name these features as worthwhile local AI/UI work:

```markdown
// README.md:145-152
Good AI use cases for this app:

- setup assistant from natural language to a typed profile;
- preflight coach for missing permissions or dead sources;
- director explanations based on local signals;
- clip title suggestions;
- post-session health summaries;
- slow sampled-frame review outside the live hot path.
```

```markdown
// docs/current-state.md:59-65
## AI User Scenarios Worth Building

- Setup assistant: convert “I’m teaching SwiftUI with screen and camera” into a typed director profile.
- Preflight coach: explain missing permissions, muted mic, zero-level sources, wrong capture target, or missing destination.
- Director explanation: explain why a cue appeared using local signals and stream health.
```

- `Sources/MacStreamCore/Services/LocalIntelligenceProvider.swift` — the explain API already exists. At planning time it has no callers under `Sources/`.

```swift
// Sources/MacStreamCore/Services/LocalIntelligenceProvider.swift:3-8
public protocol LocalIntelligenceProvider: Sendable {
    var status: LocalIntelligenceStatus { get }

    func generateSetupPlan(for prompt: String) async throws -> SetupPlan
    func explain(_ recommendation: DirectorRecommendation, snapshot: SignalSnapshot) async throws -> String
}
```

```swift
// Sources/MacStreamCore/Services/LocalIntelligenceProvider.swift:247-249
public func explain(_ recommendation: DirectorRecommendation, snapshot: SignalSnapshot) async throws -> String {
    "\(recommendation.reason) Signals: speech \(Int(snapshot.speechLevel * 100))%, motion \(Int(snapshot.screenMotion * 100))%, app \(snapshot.activeApplication)."
}
```

```swift
// Sources/MacStreamCore/Services/LocalIntelligenceProvider.swift:304-306
public func explain(_ recommendation: DirectorRecommendation, snapshot: SignalSnapshot) async throws -> String {
    try await fallback.explain(recommendation, snapshot: snapshot)
}
```

- `Sources/MacStreamCore/Services/DirectorEngine.swift` — cue production is already rules-based and reasons are human-readable. The UI needs the same `SignalSnapshot` that produced the displayed `DirectorRecommendation`.

```swift
// Sources/MacStreamCore/Services/DirectorEngine.swift:19-28
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
```

```swift
// Sources/MacStreamCore/Services/DirectorEngine.swift:92-99
if snapshot.isMicMuted && snapshot.speechLevel > 0.35 {
    return DirectorRecommendation(
        target: currentScene,
        confidence: 0.96,
        reason: "Mic looks muted while speech is detected.",
        urgency: .immediate,
        delaySeconds: 0
    )
```

```swift
// Sources/MacStreamCore/Services/DirectorEngine.swift:128-147
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
```

- `Sources/MacStreamCore/Models/StudioModels.swift` — `SignalSnapshot` and `DirectorRecommendation` are Sendable value types suitable for storing together.

```swift
// Sources/MacStreamCore/Models/StudioModels.swift:598-607
public struct SignalSnapshot: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var isSpeaking: Bool
    public var speechLevel: Double
    public var screenMotion: Double
    public var hasFace: Bool
    public var activeApplication: String
    public var idleSeconds: TimeInterval
    public var isScreenFrozen: Bool
    public var isMicMuted: Bool
```

```swift
// Sources/MacStreamCore/Models/StudioModels.swift:638-645
public struct DirectorRecommendation: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var target: SceneKind
    public var confidence: Double
    public var reason: String
    public var urgency: RecommendationUrgency
    public var delaySeconds: Int
```

- `Sources/MacStreamCore/Models/StudioModels.swift` — capture preflight state is centralized and already has permission helpers.

```swift
// Sources/MacStreamCore/Models/StudioModels.swift:902-908
public struct CaptureDeviceInfo: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: CaptureDeviceKind
    public var name: String
    public var detail: String
    public var permission: CapturePermissionState
```

```swift
// Sources/MacStreamCore/Models/StudioModels.swift:937-940
public var permissionRecoveryHint: String? {
    guard permission != .granted, kind.requiresRestartAfterPermissionGrant else { return nil }
    return "Enable Screen Recording in System Settings. If it is already on, quit and reopen MacStream."
}
```

```swift
// Sources/MacStreamCore/Models/StudioModels.swift:984-1008
public struct CapturePreflightReport: Equatable, Sendable {
    public var devices: [CaptureDeviceInfo]
    public var summary: String

    public init(devices: [CaptureDeviceInfo] = [], summary: String = "Not scanned yet.") {
        self.devices = devices
        self.summary = summary
    }

    public var screenCaptureTargets: [ScreenCaptureTarget] {
        devices
            .filter { $0.permission == .granted }
            .compactMap(\.screenCaptureTarget)
    }

    public var requiresRelaunchToRefreshPermissionState: Bool {
        devices.contains { device in
            device.permission != .granted && device.kind.requiresRestartAfterPermissionGrant
        }
    }
```

```swift
// Sources/MacStreamCore/Models/StudioModels.swift:1047-1065
public func missingPermissionKinds(requiredKinds: [CaptureDeviceKind]) -> [CaptureDeviceKind] {
    var missingKinds: [CaptureDeviceKind] = []
    for kind in requiredKinds where !hasGrantedPermission(for: kind) {
        guard !missingKinds.contains(kind) else { continue }
        missingKinds.append(kind)
    }
    return missingKinds
}

public func permissionState(for kind: CaptureDeviceKind) -> CapturePermissionState? {
    switch kind {
    case .display, .window:
        if isScreenCapturePermissionGranted {
            return .granted
        }
        return devices.first { $0.kind == .display || $0.kind == .window }?.permission
```

- `Sources/MacStreamCore/Services/MediaPipeline.swift` — destination readiness is typed; do not inspect or print stream keys in advice.

```swift
// Sources/MacStreamCore/Services/MediaPipeline.swift:144-149
public struct StreamDestination: Equatable, Sendable {
    public var mode: StreamDestinationMode
    public var name: String
    public var rtmpServerURL: String
    public var rtmpStreamKey: String
```

```swift
// Sources/MacStreamCore/Services/MediaPipeline.swift:181-193
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
```

- `Sources/MacStreamCore/Stores/StudioStore.swift` — `StudioStore` is the single `@MainActor @Observable` source of truth. Current recommendation state is public read-only, but there is no snapshot stored with a recommendation and no explanation state.

```swift
// Sources/MacStreamCore/Stores/StudioStore.swift:4-6
@MainActor
@Observable
public final class StudioStore {
```

```swift
// Sources/MacStreamCore/Stores/StudioStore.swift:23-26
public private(set) var systemPressure = SystemPressureSnapshot()
public private(set) var latestSignals = SignalSnapshot()
public private(set) var recommendation: DirectorRecommendation?
public private(set) var autoCueRemainingSeconds: Int?
```

- `Sources/MacStreamCore/Stores/StudioStore.swift` — start readiness already combines sources, capture readiness, and destination validation, but the advice is only exposed as strings/actions in different places.

```swift
// Sources/MacStreamCore/Stores/StudioStore.swift:252-275
public var captureStartBlockedReason: String? {
    guard mediaPipeline.requiresCaptureReadinessForStart else { return nil }

    let missingSceneSourceKinds = missingSelectedSceneSourceKinds
    guard missingSceneSourceKinds.isEmpty else {
        return "\(sourceRecoveryActionTitle(for: missingSceneSourceKinds)) \(Self.sourceListTitle(for: missingSceneSourceKinds)) for \(selectedScene.title) before starting."
    }

    let enabledSourceCount = sources.filter(\.isEnabled).count
    guard enabledSourceCount > 0 else {
        return "Enable at least one source before starting."
    }

    let readiness = captureReadiness
    switch readiness.state {
```

```swift
// Sources/MacStreamCore/Stores/StudioStore.swift:342-385
public var captureReadiness: CaptureReadiness {
    if isScanningCapture {
        return CaptureReadiness(
            state: .checking,
            title: "Checking",
            detail: captureReport.summary
        )
    }

    guard hasRunInitialCaptureScan else {
        return CaptureReadiness(
            state: .unchecked,
            title: "Not checked",
            detail: captureReport.summary
        )
    }

    let missingKinds = missingRequiredCapturePermissionKinds
    guard !missingKinds.isEmpty else {
        return CaptureReadiness(
            state: .ready,
            title: "Ready",
            detail: "Capture sources are ready."
        )
    }
```

```swift
// Sources/MacStreamCore/Stores/StudioStore.swift:2044-2070
private var setupGenerationBlockedReason: String? {
    if isStreamConnecting {
        return "Finish connecting before generating setup rules."
    }

    if streamState.isLive {
        return streamTransport == .preview
            ? "Stop preview before generating local setup rules."
            : "Stop streaming before generating local setup rules."
    }

    if isRecordingStarting {
        return "Finish recording startup before generating setup rules."
    }
```

- `Sources/MacStreamCore/Stores/StudioStore.swift` — `advanceDirector()` computes `latestSignals`, evaluates the engine, and publishes `recommendation`. This is where `latestRecommendationSnapshot` must be set/cleared so explanations use the same snapshot that produced the visible cue.

```swift
// Sources/MacStreamCore/Stores/StudioStore.swift:1076-1091
public func advanceDirector() {
    sampleSystemPressure()
    latestSignals = signalSnapshotApplyingSourceState(signalProvider.snapshot())
    refreshStreamHealth()

    let previousRecommendation = recommendation
    var nextRecommendation = director.evaluate(
        snapshot: latestSignals,
        currentScene: selectedSceneKind,
        mode: directorMode
    )
    nextRecommendation = recommendationApplyingPreferences(nextRecommendation)
    nextRecommendation = recommendationRespectingSceneAvailability(nextRecommendation)

    recommendation = nextRecommendation
```

```swift
// Sources/MacStreamCore/Stores/StudioStore.swift:1112-1148
public func applyRecommendation() {
    cancelPendingAutoCue()
    guard let recommendation,
          let scene = scenes.first(where: { $0.kind == recommendation.target }),
          scene.kind != selectedSceneKind
    else {
        self.recommendation = nil
        return
    }
    guard canSelectScene(scene) else {
        if let blockedReason = sceneSelectionBlockedReason(for: scene) {
            addWarningEventIfNeeded(title: "Cue unavailable", detail: blockedReason)
        }
        self.recommendation = nil
        return
    }
```

```swift
// Sources/MacStreamCore/Stores/StudioStore.swift:1220-1247
public func generateSetupPlan() {
    guard canGenerateSetupPlan else {
        if let setupGenerationBlockedReason {
            setupSummary = setupGenerationBlockedReason
            addWarningEventIfNeeded(title: "Setup paused", detail: setupGenerationBlockedReason)
        }
        return
    }

    let prompt = SetupPlanPromptBuilder.boundedStreamDescription(setupPrompt)
    let generationID = UUID()
    setupGenerationID = generationID
    isGeneratingSetupPlan = true
    localIntelligenceStatus = intelligenceProvider.status
    setupSummary = "Generating setup rules..."

    setupGenerationTask = Task {
        defer {
            if isCurrentSetupGeneration(generationID) {
```

- `Sources/MacStreamCore/Stores/StudioStore.swift` — existing store actions the coach may map to. Do not invent new capabilities.

```swift
// Sources/MacStreamCore/Stores/StudioStore.swift:918-934
public func enableRecommendedSources() {
    let recommendedKinds = recommendedSourceKindsForSelectedScene
    let repairableIndices = sources.indices.filter { index in
        guard recommendedKinds.contains(sources[index].kind) else { return false }
        return !sources[index].isEnabled
            || (sources[index].kind.supportsLevelControl && sources[index].level <= 0)
    }
    guard !repairableIndices.isEmpty else { return }

    for index in repairableIndices {
        sources[index].isEnabled = true
        if sources[index].kind.supportsLevelControl, sources[index].level <= 0 {
            sources[index].level = 1
        }
    }
    applyPerformanceConfiguration()
    addEvent(kind: .source, title: "Sources ready", detail: "Needed sources ready for \(selectedScene.title).")
}
```

```swift
// Sources/MacStreamCore/Stores/StudioStore.swift:956-974
public func setDestinationMode(_ mode: StreamDestinationMode) {
    guard canEditDestination, destination.mode != mode else { return }

    var nextDestination = destination
    nextDestination.mode = mode
    switch mode {
    case .preview:
        if nextDestination.name.isEmpty || nextDestination.name == "RTMP Destination" {
            nextDestination.name = "Preview Session"
        }
    case .rtmp:
        if nextDestination.name.isEmpty || nextDestination.name == "Preview Session" {
            nextDestination.name = "RTMP Destination"
        }
```

```swift
// Sources/MacStreamCore/Stores/StudioStore.swift:1041-1073
public func selectScreenCaptureTarget(_ target: ScreenCaptureTarget) {
    guard canEditScreenCaptureTarget else { return }
    guard selectedScreenCaptureTarget != target else {
        screenCaptureTargetPreference = target
        return
    }

    screenCaptureTargetPreference = target
    selectedScreenCaptureTarget = target
    applyPerformanceConfiguration()
    addEvent(kind: .source, title: "Screen target", detail: target.title)
}

public func selectCameraDevice(id: String) {
    guard canSelectInputDevice else { return }
    cameraDeviceIDPreference = id
```

```swift
// Sources/MacStreamCore/Stores/StudioStore.swift:1276-1284
public func scanCaptureDevices() {
    guard canScanCaptureDevices else { return }
    isScanningCapture = true
    let captureDeviceProvider = captureDeviceProvider

    Task.detached(priority: .userInitiated) { [weak self] in
        let report = await captureDeviceProvider.scan()
        await self?.finishCaptureScan(with: report)
    }
```

- `Sources/MacStream/Views/DirectorPanelView.swift` — the cue panel renders the reason and Take/Hold buttons, but no explanation affordance.

```swift
// Sources/MacStream/Views/DirectorPanelView.swift:37-64
private func expandedDirectorPanel(for recommendation: DirectorRecommendation) -> some View {
    VStack(alignment: .leading, spacing: StudioMetrics.md) {
        StudioPanelHeader(title: "Director", systemImage: "sparkles.tv") {
            HStack(spacing: StudioMetrics.sm) {
                StudioBadge(title: store.directorMode.title, systemImage: "sparkles", tint: directorModeTint)
                directorActionButtons
            }
        }

        VStack(alignment: .leading, spacing: StudioMetrics.sm) {
            HStack(alignment: .firstTextBaseline, spacing: StudioMetrics.sm) {
                Label("Cue \(recommendation.target.title)", systemImage: recommendation.target.symbolName)
                    .font(.title3.weight(.semibold))
                Spacer()
                StudioBadge(title: "\(Int(recommendation.confidence * 100))%", systemImage: "gauge.with.dots.needle.50percent", tint: recommendationTint(for: recommendation), isFilled: recommendation.urgency == .immediate)
            }

            Text(recommendation.reason)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
```

```swift
// Sources/MacStream/Views/DirectorPanelView.swift:64-83
HStack {
    if recommendation.target != store.selectedSceneKind {
        Button {
            store.applyRecommendation()
        } label: {
            Label("Take", systemImage: "arrow.right.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        .disabled(!store.canApplyRecommendation)
        .help(store.recommendationActionBlockedReason ?? "Take cue")
    }

    Button {
        store.dismissRecommendation()
    } label: {
        Label("Hold", systemImage: "hand.raised")
    }
    .help("Keep the current scene")
}
```

- `Sources/MacStream/Views/CapturePreflightView.swift` — permission rows already use compact HStack styling and explicit permission actions. Coach rows should match this density, but must not trigger passive permission prompts.

```swift
// Sources/MacStream/Views/CapturePreflightView.swift:8-17
var body: some View {
    VStack(alignment: .leading, spacing: 12) {
        StudioPanelHeader(
            title: "Capture",
            systemImage: "checklist",
            subtitle: store.captureReport.summary
        ) {
            Button {
                store.scanCaptureDevices()
```

```swift
// Sources/MacStream/Views/CapturePreflightView.swift:59-89
private func permissionRows(_ rows: [CapturePermissionRow]) -> some View {
    VStack(spacing: 10) {
        ForEach(rows) { row in
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: row.kind.symbolName)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.callout.weight(.semibold))
                    .lineLimit(1)
```

```swift
// Sources/MacStream/Views/CapturePreflightView.swift:94-118
@ViewBuilder
private func permissionAction(for row: CapturePermissionRow) -> some View {
    if canAskForPermission(row) {
        Button {
            CapturePermissionActions.requestAccess(for: row.requestKind, store: store)
        } label: {
            Text("Ask")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .tint(.orange)
        .help("Ask macOS for \(row.title.lowercased())")
    } else if row.permission != .granted,
              CapturePermissionActions.privacySettingsURL(for: row.requestKind) != nil {
        Button {
            CapturePermissionActions.openSettings(for: row.requestKind)
```

- `Sources/MacStream/Views/SetupChecklistView.swift` — setup checklist already maps the same readiness problems to existing UI actions. The coach action mapping should reuse these capabilities instead of creating new flows.

```swift
// Sources/MacStream/Views/SetupChecklistView.swift:57-91
@ViewBuilder
private var primarySetupAction: some View {
    switch nextIncompleteItemID {
    case .some(.scene):
        Button {
            store.selectRecommendedStartingScene()
        } label: {
            Label("Use Screen + Face", systemImage: "rectangle.inset.filled.and.person.filled")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .help("Select the default screen and camera scene")
    case .some(.capture):
        captureSetupAction
    case .some(.destination):
        Button {
            store.setDestinationMode(.preview)
```

```swift
// Sources/MacStream/Views/SetupChecklistView.swift:117-156
} else if missingScreenCaptureAccess {
    HStack(spacing: StudioMetrics.sm) {
        Button {
            CapturePermissionActions.openSettings(for: .display)
        } label: {
            Label("Open Screen Settings", systemImage: "gearshape")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .help("Grant Screen Recording in System Settings")

        Button {
            MacStreamRelauncher.relaunch()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
```

- `Tests/MacStreamCoreTests/DirectorEngineTests.swift` line references below are original at commit `03ae477`. After Plan 001, `screenCapturePermissionHintExplainsRestartRequirement` lives in `Tests/MacStreamCoreTests/CapturePreflightModelTests.swift`; the passive permission-request source-text guardrails live in `Tests/MacStreamCoreTests/SourceTextGuardrailTests.swift`. Keep the same function names. Use the permission-hint test as a fixture/style pattern only, not as the destination for new `PreflightCoach` tests.

```swift
// Tests/MacStreamCoreTests/DirectorEngineTests.swift:57-87
func screenCapturePermissionHintExplainsRestartRequirement() {
    let display = CaptureDeviceInfo(
        id: "display-7",
        kind: .display,
        name: "Studio Display",
        detail: "3024x1964",
        permission: .notDetermined
    )
...
    #expect(display.permissionRecoveryHint == "Enable Screen Recording in System Settings. If it is already on, quit and reopen MacStream.")
    #expect(window.permissionRecoveryHint == "Enable Screen Recording in System Settings. If it is already on, quit and reopen MacStream.")
```

```swift
// Tests/MacStreamCoreTests/DirectorEngineTests.swift:453-480
func screenPreviewDoesNotRequestScreenRecordingPermissionPassively() throws {
...
    #expect(!previewSource.contains("CGRequestScreenCaptureAccess"))
    #expect(previewSource.contains("CGPreflightScreenCaptureAccess()"))
...
func signalSamplingDoesNotRequestScreenRecordingPermissionPassively() throws {
...
    #expect(!signalSource.contains("CGRequestScreenCaptureAccess"))
    #expect(signalSource.contains("CGPreflightScreenCaptureAccess()"))
```

```swift
// Tests/MacStreamCoreTests/DirectorEngineTests.swift:486-510
func cameraPreviewDoesNotRequestCameraPermissionPassively() throws {
...
    #expect(captureSource.contains("CapturePermissionRow.rows"))
    #expect(captureSource.contains("CapturePermissionActions.requestAccess(for: row.requestKind, store: store)"))
    #expect(!captureSource.contains("CapturePermissionActions.requestAccess(for: device.kind, store: store)"))
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift check | `git diff --stat 03ae477..HEAD -- Sources/MacStreamCore/Services/PreflightCoach.swift Sources/MacStreamCore/Stores/StudioStore.swift Sources/MacStream/Views/DirectorPanelView.swift Sources/MacStream/Views/CapturePreflightView.swift Tests/MacStreamCoreTests/TestSupport.swift Tests/MacStreamCoreTests/CapturePreflightModelTests.swift Tests/MacStreamCoreTests/CaptureScanAndReadinessTests.swift Tests/MacStreamCoreTests/StudioStoreDirectorLoopTests.swift Tests/MacStreamCoreTests/SourceTextGuardrailTests.swift plans/README.md` | no output, or only changes you reviewed against this plan |
| Build | `swift build` | exit 0, `Build complete!` |
| Full tests | `swift test` (from repo root) | final line contains `Test run with 242 tests in 0 suites passed` if this plan adds 9 tests to the post-001 baseline of 233 |
| Coach test slice | `swift test --filter PreflightCoach` | exit 0; all `PreflightCoach` tests pass |
| Explain test slice | `swift test --filter RecommendationExplanation` | exit 0; all explanation-flow tests pass |
| Source guardrails | `swift test --filter DoesNotRequest` | exit 0; no passive permission-request guardrail regresses |
| Caller check | `grep -R "\.explain(" -n Sources Tests` | existing provider delegation `Sources/MacStreamCore/Services/LocalIntelligenceProvider.swift:305` (`fallback.explain(...)`), the new production caller in `StudioStore.swift`, and fake/test references under `Tests/`; no SwiftUI view calls providers directly |
| Scope check | `git status --short` | only files listed under Scope are modified |

## Scope

**In scope** (the only files you should modify or create):
- `Sources/MacStreamCore/Services/PreflightCoach.swift` (create; contains `PreflightAdvice`, `PreflightAdviceAction`, and pure `PreflightCoach` builder)
- `Sources/MacStreamCore/Stores/StudioStore.swift` (recommendation snapshot/explanation state, `preflightAdvice` computed property, action-support computed properties only if needed)
- `Sources/MacStream/Views/DirectorPanelView.swift` (Explain affordance and explanation rendering)
- `Sources/MacStream/Views/CapturePreflightView.swift` (coach advice rows and action buttons)
- `Tests/MacStreamCoreTests/TestSupport.swift` (add/reuse provider fake helpers after Plan 001 moves shared fakes here)
- `Tests/MacStreamCoreTests/CaptureScanAndReadinessTests.swift` (new pure `PreflightCoach` tests)
- `Tests/MacStreamCoreTests/StudioStoreDirectorLoopTests.swift` (new explanation-flow tests)
- `Tests/MacStreamCoreTests/SourceTextGuardrailTests.swift` (only if an existing guardrail string must be updated because the capture view still enforces the same no-passive-request rule)
- `plans/README.md` (status row only)

**Out of scope** (do NOT touch):
- `Tests/MacStreamCoreTests/CapturePreflightModelTests.swift` — read only as the post-001 home of the permission-hint fixture pattern; do not add `PreflightCoach` tests here.
- `Sources/MacStreamCore/Services/LocalIntelligenceProvider.swift` — the interface and rules/fallback implementations already exist.
- `Sources/MacStreamCore/Services/DirectorEngine.swift` — cue production is not changing.
- `Sources/MacStreamCore/Services/MediaPipeline.swift` — destination validation stays as-is; do not expose or log stream keys.
- `Sources/MacStreamCore/Models/StudioModels.swift` unless the executor discovers `PreflightAdvice` cannot compile in `PreflightCoach.swift`; prefer the new service file to keep model types from becoming a dumping ground.
- `Sources/MacStream/Views/SetupChecklistView.swift` — read it as the action/style exemplar, but put coach rows in `CapturePreflightView.swift`.
- Any provider-phrased preflight coach text or model call for advice.
- Any new permission-prompting behavior, background permission requests, or changes to passive preflight checks.
- Any changes to stream destination persistence, Keychain storage, or secret redaction.
- Any generated docs beyond the `plans/README.md` status row.

## Git workflow

- Commit directly to `main` (repo convention — no PRs unless asked).
- Use conventional-prefix commit messages (`feat:`, `fix:`, `refactor:`, `test:`, `ci:`), e.g. `feat: add deterministic preflight coach`.
- Do NOT push unless the operator explicitly instructed it.

## Steps

### Step 1: Add the deterministic preflight advice types and builder

Create `Sources/MacStreamCore/Services/PreflightCoach.swift`. Keep it pure, `Sendable`, and free of UI imports. Put both the advice DTOs and the static builder in this file unless compile errors prove a model-file location is required.

Target shape, adapt to surrounding code:

```swift
// shape, adapt to surrounding code
import Foundation

public struct PreflightAdvice: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var action: PreflightAdviceAction

    public init(id: String, title: String, detail: String, action: PreflightAdviceAction) { ... }
}

public enum PreflightAdviceAction: Equatable, Sendable {
    case openCaptureSettings(CaptureDeviceKind)
    case rescanCapture
    case selectScreenCaptureTarget(ScreenCaptureTarget)
    case selectCameraDevice(String)
    case selectMicrophoneDevice(String)
    case fixSelectedSceneSources
    case usePreviewDestination
}

public enum PreflightCoach {
    public static func advice(
        report: CapturePreflightReport,
        sources: [StudioSource],
        selectedScene: SceneKind,
        selectedScreenCaptureTarget: ScreenCaptureTarget?,
        selectedCameraDeviceID: String?,
        selectedMicrophoneDeviceID: String?,
        destination: StreamDestination,
        hasRunInitialCaptureScan: Bool,
        isScanningCapture: Bool
    ) -> [PreflightAdvice] { ... }
}
```

Rules to implement, in this exact severity order:

1. Permissions first. If no scan has run, return one `rescanCapture` advice: title `Check capture permissions`, detail `Run a capture scan before going live.`. If scanning, return one `rescanCapture` advice with title `Checking capture permissions` and no additional blocking advice. If required permissions are missing for the selected scene, return one advice per missing kind (dedupe display/window as screen): `openCaptureSettings(kind)` for missing screen/display/window or denied/unknown camera/microphone; never call request-access from the builder.
2. Devices/targets second. If selected scene uses screen and `report.screenCaptureTargets` is non-empty but `selectedScreenCaptureTarget == nil`, return `selectScreenCaptureTarget(first display target else first target)`. If selected scene needs camera/microphone and granted devices exist but the selected ID is nil, return `selectCameraDevice(id)` / `selectMicrophoneDevice(id)` for the first granted device. If required granted devices/targets do not exist, return `rescanCapture` advice asking the operator to connect/check hardware.
3. Sources third. If a required source for the selected scene is disabled or has `level <= 0` and supports level control, return one `fixSelectedSceneSources` advice using the same semantics as `StudioStore.enableRecommendedSources()`.
4. Destination last. If `destination.isReadyToStart == false`, return `usePreviewDestination` advice with the validation error as detail. Do not include `rtmpStreamKey`, raw combined RTMP URLs, or any secret-like value in title/detail.
5. All-clear returns `[]`.

Use private helpers inside `PreflightCoach.swift` for required source/device kinds. Match `StudioStore.requiredSourceKinds(for:)` and `CapturePreflightReport.missingPermissionKinds(requiredKinds:)`; do not make `StudioStore` helpers public just for the builder.

**Verify**: `swift build` → exit 0, `Build complete!`

### Step 2: Add pure PreflightCoach tests in the post-001 capture/readiness test file

In `Tests/MacStreamCoreTests/CaptureScanAndReadinessTests.swift`, add tests whose names include `PreflightCoach` so the filter works. Use Swift Testing (`@Test` + `#expect`, not XCTest). Model the value-fixture style after `screenCapturePermissionHintExplainsRestartRequirement`, originally at `Tests/MacStreamCoreTests/DirectorEngineTests.swift:57` and post-001 in `Tests/MacStreamCoreTests/CapturePreflightModelTests.swift`; that file is a pattern source only, not the destination for these tests.

Add these five tests:

1. `preflightCoachReportsMissingPermissionFirst` — selected `.screenAndFace`, display/window permission missing and camera granted; expect first advice action is `.openCaptureSettings(.display)` (or the chosen screen kind) and source/destination advice comes later or is absent.
2. `preflightCoachReportsMissingDeviceOrTarget` — permissions granted but no screen target or no camera device for required selected scene; expect `rescanCapture` or first selectable target/device action depending on test fixture.
3. `preflightCoachReportsMutedOrZeroLevelNeededSource` — selected `.screenAndFace`, screen source enabled with level `0` or camera source disabled; expect `.fixSelectedSceneSources`.
4. `preflightCoachReportsMissingDestinationAfterCaptureAndSources` — ready capture and sources, RTMP destination with invalid/missing endpoint; expect `.usePreviewDestination` and detail equals/safely includes `destination.validationError`, with no stream key string.
5. `preflightCoachReturnsEmptyWhenAllClear` — ready capture, selected target/device IDs set, needed sources enabled and levels above zero, preview destination ready; expect `[]`.

Keep fixtures small and in-test. Do not create mocks; the builder is a pure function over value types.

**Verify**: `swift test --filter PreflightCoach` → exit 0; all five new coach tests pass.

### Step 3: Expose preflight advice from StudioStore

In `Sources/MacStreamCore/Stores/StudioStore.swift`, add a public computed property near existing readiness/setup computed properties:

```swift
// shape, adapt to surrounding code
public var preflightAdvice: [PreflightAdvice] {
    PreflightCoach.advice(
        report: captureReport,
        sources: sources,
        selectedScene: selectedSceneKind,
        selectedScreenCaptureTarget: selectedScreenCaptureTarget,
        selectedCameraDeviceID: selectedCameraDeviceID,
        selectedMicrophoneDeviceID: selectedMicrophoneDeviceID,
        destination: destination,
        hasRunInitialCaptureScan: hasRunInitialCaptureScan,
        isScanningCapture: isScanningCapture
    )
}
```

If `CapturePreflightView` cannot safely determine whether action buttons should be enabled from existing store state, add only minimal read-only computed properties to `StudioStore`; do not add new mutating capabilities. Existing capabilities to wire are `scanCaptureDevices()`, `selectScreenCaptureTarget(_:)`, `selectCameraDevice(id:)`, `selectMicrophoneDevice(id:)`, `enableRecommendedSources()`, and `setDestinationMode(.preview)`.

**Verify**: `swift build` → exit 0, `Build complete!`

### Step 4: Add recommendation snapshot and explanation state to StudioStore

In `Sources/MacStreamCore/Stores/StudioStore.swift`, add recommendation explanation state next to `recommendation`:

```swift
// shape, adapt to surrounding code
public private(set) var latestRecommendationSnapshot: SignalSnapshot?
public private(set) var recommendationExplanation: String?
public private(set) var isExplainingRecommendation = false
@ObservationIgnored private var recommendationExplanationTask: Task<Void, Never>?
@ObservationIgnored private var recommendationExplanationID: UUID?
```

Mirror the cancellation/generation-ID discipline of `generateSetupPlan()` (`StudioStore.swift:1220-1274`): one in-flight explanation at a time, stale task results ignored, and state reset in `defer` only for the current ID.

Add helpers, shape only:

```swift
// shape, adapt to surrounding code
public func explainCurrentRecommendation() {
    guard !isExplainingRecommendation,
          let recommendation,
          let snapshot = latestRecommendationSnapshot
    else { return }

    let explanationID = UUID()
    recommendationExplanationID = explanationID
    isExplainingRecommendation = true
    recommendationExplanation = nil

    recommendationExplanationTask = Task {
        defer { ... current-ID cleanup ... }
        do {
            let explanation = try await intelligenceProvider.explain(recommendation, snapshot: snapshot)
            guard isCurrentRecommendationExplanation(explanationID, recommendation: recommendation) else { return }
            recommendationExplanation = explanation
            localIntelligenceStatus = intelligenceProvider.status
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentRecommendationExplanation(explanationID, recommendation: recommendation) else { return }
            recommendationExplanation = recommendation.reason
        }
    }
}
```

Implement these invariants:

- When `advanceDirector()` publishes a new non-nil recommendation, set `latestRecommendationSnapshot = latestSignals` before any UI can ask for an explanation.
- If the cue changes (`!nextRecommendation.hasSameCue(as: previousRecommendation)`), clear `recommendationExplanation` and cancel any in-flight explanation before assigning/after assigning the new cue. If the same cue remains, preserve an existing explanation.
- Whenever `recommendation` is set to nil (`selectScene`, `applyRecommendation`, `dismissRecommendation`, `stopStream`, `directorModeDidChange(.paused)`, `prepareCaptureSessionIfIdle`, `generateSetupPlan` applying a plan, and any other direct nil assignment you find), also clear `latestRecommendationSnapshot`, `recommendationExplanation`, `isExplainingRecommendation`, and cancel the explanation task.
- `explainCurrentRecommendation()` never calls `applyRecommendation()`, never changes `selectedSceneID`, never schedules/cancels auto cue except as a side effect of existing recommendation lifecycle, and never blocks `advanceDirector()`.

Prefer a private helper such as `clearRecommendationExplanation(cancelTask: Bool = true)` and, if useful, `clearRecommendation()` to avoid missing nil paths. Keep the cutover clean; do not leave stale explanation aliases.

**Verify**: `swift build` → exit 0, `Build complete!`

### Step 5: Add StudioStore explanation-flow tests

In `Tests/MacStreamCoreTests/TestSupport.swift`, add an internal fake provider if no existing setup-provider fake cleanly supports `explain`:

```swift
// shape, adapt to surrounding code
final class ExplainingProvider: LocalIntelligenceProvider, @unchecked Sendable {
    var status = LocalIntelligenceStatus(...)
    var explanationResult: Result<String, Error>
    private(set) var requestedSnapshots: [SignalSnapshot] = []

    func generateSetupPlan(for prompt: String) async throws -> SetupPlan { ... minimal valid plan ... }
    func explain(_ recommendation: DirectorRecommendation, snapshot: SignalSnapshot) async throws -> String {
        requestedSnapshots.append(snapshot)
        return try explanationResult.get()
    }
}
```

Use existing `FixedSignalProvider`, `ConfigurableSignalProvider`, and `SpyMediaPipeline` from `TestSupport.swift` after Plan 001 removes `private` from shared fakes.

In `Tests/MacStreamCoreTests/StudioStoreDirectorLoopTests.swift`, add tests whose names include `RecommendationExplanation`:

1. `recommendationExplanationPopulatesOnDemand` — configure a signal snapshot that creates a visible cue, call `advanceDirector()`, call `explainCurrentRecommendation()`, await until `recommendationExplanation == expected`, and assert the fake provider saw exactly the snapshot that produced the cue (same speech/motion/app values, not a later `latestSignals` mutation).
2. `recommendationExplanationFallsBackToCueReasonOnProviderError` — fake provider throws; explanation becomes `recommendation.reason`.
3. `recommendationExplanationClearsWhenRecommendationChanges` — explain a cue, change the signal/current recommendation so a different cue is published, call `advanceDirector()`, assert `recommendationExplanation == nil` and the snapshot updates.
4. `recommendationExplanationDoesNotMutateSceneState` — capture `selectedSceneID`, `directorMode`, and `autoCueRemainingSeconds` or recommendation target before explaining; after explanation completes, assert scene and mode are unchanged and no scene switch event was added.

Do not use sleeps longer than necessary. If the existing tests use an eventual assertion helper, reuse it; otherwise add a tiny test-local async polling helper in `TestSupport.swift`.

**Verify**: `swift test --filter RecommendationExplanation` → exit 0; all four new explanation tests pass.

### Step 6: Wire the Explain affordance into DirectorPanelView

In `Sources/MacStream/Views/DirectorPanelView.swift`, update `expandedDirectorPanel(for:)` only. Add a `Why this cue?` button in the same action HStack as Take/Hold. It should:

- call `store.explainCurrentRecommendation()`;
- be disabled while `store.isExplainingRecommendation` is true;
- show a small `ProgressView` or `Label("Explaining", systemImage: "hourglass")` while explaining;
- not hide or delay Take/Hold;
- render `store.recommendationExplanation` under the cue reason when non-nil, using secondary/caption styling and the existing tinted rounded cue card.

Target shape, adapt to surrounding code:

```swift
// shape, adapt to surrounding code
Button {
    store.explainCurrentRecommendation()
} label: {
    if store.isExplainingRecommendation {
        Label("Explaining", systemImage: "hourglass")
    } else {
        Label("Why this cue?", systemImage: "questionmark.circle")
    }
}
.disabled(store.isExplainingRecommendation)
.help("Explain this cue using the signals that produced it")

if let explanation = store.recommendationExplanation {
    Text(explanation)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
}
```

Do not call the provider directly from SwiftUI. Do not use `store.latestSignals` for the explanation text; the store owns the faithful snapshot.

**Verify**: `swift build` → exit 0, `Build complete!`

### Step 7: Render coach rows in CapturePreflightView and wire existing actions

In `Sources/MacStream/Views/CapturePreflightView.swift`, add an advice section after the scan/relaunch/checked-on-launch header area and before or after permission rows. Keep row density visually consistent with `permissionRows(_:)` and `SetupChecklistRow`: icon, title, detail, trailing action button.

Implementation shape:

```swift
// shape, adapt to surrounding code
let advice = store.preflightAdvice
if !advice.isEmpty {
    preflightAdviceRows(advice)
}

private func preflightAdviceRows(_ advice: [PreflightAdvice]) -> some View { ... }

@ViewBuilder
private func adviceAction(for advice: PreflightAdvice) -> some View {
    switch advice.action {
    case let .openCaptureSettings(kind):
        Button { CapturePermissionActions.openSettings(for: kind) } label: { Label("Settings", systemImage: "gearshape") }
    case .rescanCapture:
        Button { store.scanCaptureDevices() } label: { Label("Check", systemImage: "arrow.clockwise") }
            .disabled(!store.canScanCaptureDevices)
    case let .selectScreenCaptureTarget(target):
        Button { store.selectScreenCaptureTarget(target) } label: { Label("Select", systemImage: "display") }
    case let .selectCameraDevice(id):
        Button { store.selectCameraDevice(id: id) } label: { Label("Select", systemImage: "video") }
    case let .selectMicrophoneDevice(id):
        Button { store.selectMicrophoneDevice(id: id) } label: { Label("Select", systemImage: "mic") }
    case .fixSelectedSceneSources:
        Button { store.enableRecommendedSources() } label: { Label("Fix", systemImage: "slider.horizontal.3") }
    case .usePreviewDestination:
        Button { store.setDestinationMode(.preview) } label: { Label("Use Preview", systemImage: "play.rectangle") }
    }
}
```

Rules:

- `openCaptureSettings` may open System Settings; it must not call `CapturePermissionActions.requestAccess` from coach rows.
- `rescanCapture` must respect `store.canScanCaptureDevices` and use `store.captureScanBlockedReason` for help text when disabled.
- Keep permission rows intact. The existing explicit `Ask` buttons in permission rows remain allowed because they require a user click and are already covered by guardrails; the coach itself must not introduce passive prompts.
- Do not show secrets or raw RTMP URLs in advice detail. Use `destination.validationError` or a generic message.

**Verify**: `swift build` → exit 0, `Build complete!`

### Step 8: Run guardrails, full tests, and update the plan index

Run the focused guardrail and full suite from the repo root:

```
swift test --filter DoesNotRequest
swift test
```

Expected full-suite count: post-001 baseline `233` + `5` coach tests + `4` explanation tests = `242` tests. If a different count appears because another plan added tests first, confirm that all nine tests from this plan are present and passing, then record the observed count in the commit message or handoff note.

Update only the Plan 004 row in `plans/README.md` from `TODO` to `DONE` (or add the row if Plan 004 is missing and the index already exists after Plan 001). Do not rewrite other plan rows.

**Verify**: `swift test` → final line contains `Test run with 242 tests in 0 suites passed` (or higher only if other plans added tests and this plan's nine tests pass); `git status --short` → only files listed under Scope are modified.

## Test plan

- `Tests/MacStreamCoreTests/CaptureScanAndReadinessTests.swift`:
  - Add five pure-function tests for `PreflightCoach` covering missing permission, missing device/target, muted or zero-level required source, invalid destination, and all-clear empty advice.
  - Pattern: original `screenCapturePermissionHintExplainsRestartRequirement` at `Tests/MacStreamCoreTests/DirectorEngineTests.swift:57`, which after Plan 001 lives in `Tests/MacStreamCoreTests/CapturePreflightModelTests.swift` and uses small value fixtures with `#expect`; add the new `PreflightCoach` tests to `CaptureScanAndReadinessTests.swift`, not to the pattern file.
  - Verification: `swift test --filter PreflightCoach` → all five pass.

- `Tests/MacStreamCoreTests/StudioStoreDirectorLoopTests.swift`:
  - Add four explanation-flow tests with `ExplainingProvider`: explanation populated on demand, provider error falls back to `recommendation.reason`, explanation clears when the recommendation changes, and explaining never mutates scene state.
  - Pattern: post-001 director-loop store tests using shared fakes from `Tests/MacStreamCoreTests/TestSupport.swift` (`FixedSignalProvider`, `ConfigurableMediaPipeline`, `SpyMediaPipeline`, etc.; these are internal, not private, after Plan 001).
  - Verification: `swift test --filter RecommendationExplanation` → all four pass.

- Existing guardrails to preserve:
  - Original `screenPreviewDoesNotRequestScreenRecordingPermissionPassively` at `Tests/MacStreamCoreTests/DirectorEngineTests.swift:453`, post-001 file `SourceTextGuardrailTests.swift`.
  - Original `signalSamplingDoesNotRequestScreenRecordingPermissionPassively` at `Tests/MacStreamCoreTests/DirectorEngineTests.swift:473`, post-001 file `SourceTextGuardrailTests.swift`.
  - Original `cameraPreviewDoesNotRequestCameraPermissionPassively` at `Tests/MacStreamCoreTests/DirectorEngineTests.swift:486`, post-001 file `SourceTextGuardrailTests.swift`.
  - Verification: `swift test --filter DoesNotRequest` → all passive-permission guardrails pass.

- Full regression:
  - `swift test` from repo root → final line contains `Test run with 242 tests in 0 suites passed` if no other plans have added tests.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `git diff --stat 03ae477..HEAD -- Sources/MacStreamCore/Services/PreflightCoach.swift Sources/MacStreamCore/Stores/StudioStore.swift Sources/MacStream/Views/DirectorPanelView.swift Sources/MacStream/Views/CapturePreflightView.swift Tests/MacStreamCoreTests/TestSupport.swift Tests/MacStreamCoreTests/CapturePreflightModelTests.swift Tests/MacStreamCoreTests/CaptureScanAndReadinessTests.swift Tests/MacStreamCoreTests/StudioStoreDirectorLoopTests.swift Tests/MacStreamCoreTests/SourceTextGuardrailTests.swift plans/README.md` has been reviewed against the Current state excerpts before editing.
- [ ] `swift build` exits 0 with `Build complete!`.
- [ ] `swift test --filter PreflightCoach` exits 0 and includes the five new branch tests.
- [ ] `swift test --filter RecommendationExplanation` exits 0 and includes the four explanation-flow tests.
- [ ] `swift test --filter DoesNotRequest` exits 0; no passive permission-request guardrail regresses.
- [ ] `swift test` exits 0; expected count is `Test run with 242 tests in 0 suites passed` unless other completed plans increased the count.
- [ ] `grep -R "\.explain(" -n Sources Tests` shows the existing provider delegation in `Sources/MacStreamCore/Services/LocalIntelligenceProvider.swift` (`fallback.explain(...)`), the new production caller in `Sources/MacStreamCore/Stores/StudioStore.swift`, plus test/fake references; there is still no direct SwiftUI-to-provider call.
- [ ] `grep -R "CapturePermissionActions.requestAccess" -n Sources/MacStream/Views/CapturePreflightView.swift` shows only the existing explicit permission-row path, not a coach-row passive/bulk path.
- [ ] `grep -R "rtmpStreamKey\|combinedRTMPURL" -n Sources/MacStreamCore/Services/PreflightCoach.swift Sources/MacStream/Views/CapturePreflightView.swift` returns no matches.
- [ ] `git status --short` lists only files in the Scope section.
- [ ] `plans/README.md` Plan 004 row is updated to `DONE`.

## STOP conditions

Stop and report back (do not improvise) if:

- Any code at the locations quoted in "Current state" does not match after the drift check and cannot be reconciled with a small local adjustment.
- `StudioStore.advanceDirector()` no longer owns recommendation publication, or recommendation storage no longer has a single obvious `recommendation` property; the snapshot/explanation lifecycle would be easy to wire incorrectly.
- The implementation would require changing `DirectorEngine.evaluate(...)` or making model output drive live scene switching. Explanations must be display-only.
- A coach action you need does not map to an existing explicit capability (`scanCaptureDevices`, `selectScreenCaptureTarget`, `selectCameraDevice`, `selectMicrophoneDevice`, `enableRecommendedSources`, `setDestinationMode(.preview)`, or opening an existing System Settings pane).
- Any step appears to require requesting camera, microphone, or screen permissions passively or in bulk. Existing guardrails at original `DirectorEngineTests.swift:453-515` forbid passive permission prompts.
- Advice text would need to include a stream key, raw combined RTMP URL, Keychain value, or other secret-bearing value to be actionable.
- Adding `PreflightCoach.swift` causes SwiftPM/module visibility issues that cannot be solved without touching files outside Scope.
- A verification command fails twice after a reasonable fix attempt.

## Maintenance notes

- Review `StudioStore` nil-recommendation paths carefully. A stale explanation under a new cue is the main correctness risk; prefer one private clearing helper and use it everywhere recommendation state is cleared.
- The live hot path must stay cheap: `advanceDirector()` may store one already-created `SignalSnapshot`, but must not await the provider, allocate explanation strings, or hop off the main actor for every sample. `explainCurrentRecommendation()` runs only on explicit user action.
- `PreflightCoach` is intentionally deterministic. If Plan 003 later adds a real local provider, it may enrich director explanations, but preflight advice should remain rules-first unless a future plan adds typed provider suggestions behind explicit review.
- Keep permission behavior conservative. The coach can guide to Settings or trigger an explicit existing scan; it should never call `CGRequestScreenCaptureAccess` or `AVCaptureDevice.requestAccess` except through the already-visible user-click `Ask` path.
- Reviewers should scrutinize secret handling in destination advice and confirm no stream key or raw RTMP URL can appear in UI text, logs, events, tests, or plans.
