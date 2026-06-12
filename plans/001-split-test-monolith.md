# Plan 001: Split the 6,089-line test monolith into subsystem files and add AGENTS.md

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 03ae477..HEAD -- Tests/ Package.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: dx / tests
- **Planned at**: commit `03ae477`, 2026-06-11

## Why this matters

The entire test suite — 233 tests covering packaging, the director engine, the
media pipeline, the studio store, destinations, clip markers, session reports,
and AI setup providers — lives in one 6,089-line file,
`Tests/MacStreamCoreTests/DirectorEngineTests.swift`. Contributors changing one
subsystem must navigate the monolith, and future plans (002–006) need obvious
homes for the tests they add. This plan is purely mechanical: redistribute the
existing tests into subsystem files **without changing any test's body**, and
add an `AGENTS.md` so future agents/contributors follow repo conventions
instead of copying the monolith pattern. Plans 002–006 reference the new file
layout, so this plan executes first.

## Current state

- `Tests/MacStreamCoreTests/DirectorEngineTests.swift` — the only test file.
  6,089 lines, 233 top-level `@Test` functions (Swift Testing framework, not
  XCTest), plus shared private fakes at the bottom (lines 5469–6089).
- The file header (lines 1–6) is:

```swift
// Tests/MacStreamCoreTests/DirectorEngineTests.swift:1-6
import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import Network
import Testing
@testable import MacStreamCore
```

- Tests are top-level functions, e.g.:

```swift
// Tests/MacStreamCoreTests/DirectorEngineTests.swift:692-694
@Test
func speakingOverQuietScreenCuesFace() {
    var engine = DirectorEngine()
```

  Some carry `@MainActor` between `@Test` and `func` (e.g. line 1300–1301),
  some are `throws` or `async`. A moved test always means the whole block:
  the `@Test` attribute line through the closing brace, attributes included.

- Shared fakes are file-private top-level types at the bottom, e.g.:

```swift
// Tests/MacStreamCoreTests/DirectorEngineTests.swift:5470
private final class FixedSignalProvider: SignalProvider, @unchecked Sendable {
```

  Because they are `private` (file-scope), they are visible to every test
  today. After the split they must be visible across test files, so they move
  to a shared `TestSupport.swift` with the `private` keyword **removed**
  (internal access within the test module).

- About a dozen tests are "source-text guardrails": they read `.swift`, `.sh`,
  `.yml`, `.plist`, or `.md` files from the repo as strings and assert
  substrings, e.g.:

```swift
// Tests/MacStreamCoreTests/DirectorEngineTests.swift:8-17
@Test
func packageMetadataDefinesRequiredCapturePrivacyKeys() throws {
    let infoPlistURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Resources/Info.plist")
```

  These run with paths relative to the **current working directory**, so
  `swift test` must run from the repo root. They all go into one quarantine
  file (`SourceTextGuardrailTests.swift`) so they are easy to find and replace
  with behavior tests later.

- There is no `AGENTS.md`, `CLAUDE.md`, `.swiftformat`, or SwiftLint config
  anywhere in the repo (verified at planning time).
- SwiftPM discovers all files in `Tests/MacStreamCoreTests/` automatically —
  no manifest change is needed to add test files.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `swift build` | exit 0, `Build complete!` |
| Tests | `swift test` (from repo root) | final line contains `Test run with 233 tests in 0 suites passed` |
| Count tests in a file | `grep -c '^@Test' Tests/MacStreamCoreTests/<file>` | per-file counts; total across all files = 233 |

## Scope

**In scope** (the only files you should modify or create):
- `Tests/MacStreamCoreTests/DirectorEngineTests.swift` (shrinks to director-only tests)
- `Tests/MacStreamCoreTests/SourceTextGuardrailTests.swift` (create)
- `Tests/MacStreamCoreTests/CapturePreflightModelTests.swift` (create)
- `Tests/MacStreamCoreTests/StreamDestinationTests.swift` (create)
- `Tests/MacStreamCoreTests/MediaPipelinePolicyTests.swift` (create)
- `Tests/MacStreamCoreTests/StudioStoreDirectorLoopTests.swift` (create)
- `Tests/MacStreamCoreTests/StudioStoreSourceTests.swift` (create)
- `Tests/MacStreamCoreTests/CaptureScanAndReadinessTests.swift` (create)
- `Tests/MacStreamCoreTests/DestinationPresetTests.swift` (create)
- `Tests/MacStreamCoreTests/CaptureLocksAndAdaptiveModeTests.swift` (create)
- `Tests/MacStreamCoreTests/StreamLifecycleTests.swift` (create)
- `Tests/MacStreamCoreTests/ClipMarkerTests.swift` (create)
- `Tests/MacStreamCoreTests/SessionReportAndSetupTests.swift` (create)
- `Tests/MacStreamCoreTests/TestSupport.swift` (create)
- `AGENTS.md` (create, repo root)
- `plans/README.md` (status row only)

**Out of scope** (do NOT touch):
- Anything under `Sources/` — this plan changes zero production code.
- `Package.swift` — test discovery is automatic.
- Test bodies — do not edit, fix, rename, or "improve" any test while moving
  it. Byte-identical moves only (the single exception: deleting the `private`
  keyword on moved top-level helpers, Step 3).
- Adding a formatter (`.swiftformat` etc.) — deliberately deferred; a
  formatting commit would invalidate the line references used by plans
  002–006.

## Git workflow

- Commit directly on `main` (repo convention — no PRs unless asked).
- Message style follows the existing log (`fix:`, `feat:`, `docs:`,
  `refactor:` prefixes), e.g. `refactor: split test monolith into subsystem files`.
- Do NOT push unless the operator explicitly instructed it.

## Steps

All original-line-number references below refer to
`Tests/MacStreamCoreTests/DirectorEngineTests.swift` **as it exists at commit
`03ae477`, before any edits**. Work from a copy strategy: create every new
file first by copying regions out of the original (the original's numbering
never shifts), and only rewrite the original file in the final step.

### Step 1: Create the quarantine file for source-text guardrail tests

Create `Tests/MacStreamCoreTests/SourceTextGuardrailTests.swift` with the
import header (the same 6 lines quoted in "Current state") plus this comment
under the imports:

```swift
// Source-text guardrail tests: these read repo files as strings and assert
// substrings. They are quarantined here so they can be replaced with behavior
// tests over time. Do NOT add new tests of this style (see AGENTS.md).
```

Move exactly these 13 functions (whole blocks, original line of the `func`
shown):

| Function | Original line |
|---|---|
| `packageMetadataDefinesRequiredCapturePrivacyKeys` | 9 |
| `packagingScriptsSignAppBundleWithStableIdentifier` | 29 |
| `capturePreflightViewOffersRelaunchForRestartScopedPermissions` | 136 |
| `studioKeepsFrequentControlsInBottomDeck` | 153 |
| `screenPreviewDoesNotRequestScreenRecordingPermissionPassively` | 453 |
| `signalSamplingDoesNotRequestScreenRecordingPermissionPassively` | 473 |
| `cameraPreviewDoesNotRequestCameraPermissionPassively` | 486 |
| `cameraEnhancementControlsStayWithCameraSourceAndPreviewOnly` | 517 |
| `technicalRisksSeparateSmoothMicFromVirtualMicrophoneReleasePath` | 549 |
| `packageManifestKeepsHeavyAIAndRTMPDependenciesOptIn` | 562 |
| `releaseAutomationDefinesSignedNotarizedMacPipeline` | 577 |
| `keychainPersistenceReportsFailuresToApp` | 636 |
| `studioStoreKeepsRuntimeStateReadOnlyOutsideStore` | 653 |

**Verify**: `grep -c '^@Test' Tests/MacStreamCoreTests/SourceTextGuardrailTests.swift` → `13`

### Step 2: Create the subsystem test files from contiguous regions

For each row, create the file with the same 6-line import header, then copy
the original-line region into it. Every region boundary below falls between
test functions; copy whole `@Test` blocks and skip the 13 functions already
moved in Step 1 (relevant only for the `56-134` region's neighbors — the
regions below already exclude them).

| New file | Original lines | Content summary |
|---|---|---|
| `CapturePreflightModelTests.swift` | 56–134 | `CaptureDeviceInfo`/`CapturePreflightReport` behavior + `SystemCaptureDeviceProvider` scan gating |
| `DirectorEngineTests.swift` (rewrite, Step 4) | 692–843 | DirectorEngine cue/profile/hold behavior |
| `StreamDestinationTests.swift` | 844–981 | `StreamDestination` parsing/redaction + `StreamState`/`RecordingState` |
| `MediaPipelinePolicyTests.swift` | 982–1299 | `SystemMediaPipeline` static policies, geometry, backpressure gate, cancellation box, preview start |
| `StudioStoreDirectorLoopTests.swift` | 1300–1782 | store scene basics, preferences clamps, signal/director loop, countdown, pressure sampling |
| `StudioStoreSourceTests.swift` | 1783–2434 | source toggles/levels/capabilities, scene→pipeline configuration, camera enhancements |
| `CaptureScanAndReadinessTests.swift` | 2435–3453 | capture scans, device/target selection & persistence, readiness, permissions, setup checklist, capture-start gating |
| `DestinationPresetTests.swift` | 3454–3588 | platform presets, preset/URL interactions |
| `CaptureLocksAndAdaptiveModeTests.swift` | 3589–3877 | target-change locks while recording/connecting, adaptive performance mode |
| `StreamLifecycleTests.swift` | 3878–4411 | destination modes/transport, stream start/retry/cancel/stop idempotency, secret redaction in events |
| `ClipMarkerTests.swift` | 4412–4632 | manual/auto clip markers, clip exporter |
| `SessionReportAndSetupTests.swift` | 4633–5468 | session report exporter/payload, setup-plan prompt/decoder/provider behavior |

**Verify** after creating each file: `swift build` is NOT expected to pass yet
(duplicate symbols with the original file remain until Step 4). Just confirm
each file's `grep -c '^@Test'` count looks plausible (>0); record the counts.

### Step 3: Create TestSupport.swift with the shared fakes

Create `Tests/MacStreamCoreTests/TestSupport.swift` with the import header.
Copy original lines 5469–6089 (every top-level helper from
`FixedSignalProvider` at 5470 to the end of the file, including
`ConfigurableMediaPipeline`, `TransportCountingMediaPipeline`,
`ReadinessGatedMediaPipeline`, `ScreenVideoGatedMediaPipeline`,
`ComposedScreenVideoMediaPipeline`, `DelayedSuccessfulRTMPPublisher`,
`RecoveringMediaPipeline`, `FlakyStartMediaPipeline`,
`DelayedStartMediaPipeline`, `DelayedStopMediaPipeline`,
`DelayedStopRecordingPipeline`, `NonCancellableDelayedStartMediaPipeline`,
`NonCancellableDelayedRecordingPipeline`, `TestStreamError`,
`ConfigurableSignalProvider`, `FixedCaptureDeviceProvider`,
`CountingScreenCaptureContentListing`, `DelayedCountingCaptureDeviceProvider`,
`SequencedCaptureDeviceProvider`, `DelayedSetupProvider`,
`CancellableDelayedSetupProvider`, `CountingSetupProvider`,
`PromptCapturingSetupProvider`, `SpyMediaPipeline`, and any further types to
line 6089).

On every **top-level** declaration in this file, delete the leading `private`
keyword (`private final class X` → `final class X`, `private actor Y` →
`actor Y`, `private struct Z` → `struct Z`). Do not touch `private` on
members *inside* the types.

**Verify**: `grep -c '^private' Tests/MacStreamCoreTests/TestSupport.swift` → `0`

### Step 4: Rewrite the original file as director-only and reconcile leftovers

Replace the entire contents of
`Tests/MacStreamCoreTests/DirectorEngineTests.swift` with: the 6-line import
header + original lines 692–843 (the DirectorEngine behavior tests).

Then build:

```
swift build --build-tests
```

Two failure classes are expected on the first attempt; fix them mechanically:

1. **Duplicate symbol / redeclaration**: a function or helper was copied into
   two files. Delete the extra copy.
2. **Cannot find <helper> in scope**: a `private` helper function, extension,
   or constant that lived *between* tests in the original file (not in the
   5469–6089 fakes block) was used by tests now living in a different file.
   Move that helper to `TestSupport.swift` and drop its `private` keyword.
   Do not duplicate it.

Iterate until the build is green.

**Verify**: `swift build --build-tests` → exit 0

### Step 5: Run the full suite and confirm the count is exactly 233

```
swift test
```

The final summary line must read `Test run with 233 tests in 0 suites passed`
— the same count as before the split. A lower count means a test was lost in
the move; a failure in a source-text guardrail usually means `swift test` was
not run from the repo root.

**Verify**: `swift test` → `Test run with 233 tests in 0 suites passed`

### Step 6: Add AGENTS.md at the repo root

Create `AGENTS.md` with exactly this content (adjust nothing else):

```markdown
# MacStream — agent & contributor notes

## Build / test / flags

- Build: `swift build` (macOS 26 SDK, Swift 6, strict concurrency).
- Test: `swift test` — MUST run from the repo root; some guardrail tests read
  repo files relative to the working directory.
- Optional builds: `MAC_STREAM_ENABLE_HAISHINKIT=1 swift build` (real RTMP
  publish path), `MAC_STREAM_ENABLE_MLX=1 swift build` (experimental MLX
  adapter shell). CI builds all variants.
- Packaging: `./script/package_macos_app.sh` → `dist/MacStream.app`.

## Architecture rules (do not violate)

- `StudioStore` (`Sources/MacStreamCore/Stores/`) is the single observable
  source of truth; it is `@MainActor` + `@Observable`.
- `MediaPipeline` implementations own capture/recording/publish state. The
  live hot path (sample-buffer callbacks in
  `Sources/MacStreamCore/Services/MediaPipeline.swift`) must stay free of
  per-frame allocations and main-thread hops.
- The director stays deterministic: no model output may drive live scene
  switching. AI providers implement `LocalIntelligenceProvider` and are only
  invoked outside the live hot path.
- Stream keys live in the Keychain and must stay redacted in UI, logs,
  events, and exports (`safeDisplayDetail` pattern).

## Test conventions

- Framework: Swift Testing (`@Test` functions, `#expect`), not XCTest.
- Tests live in `Tests/MacStreamCoreTests/`, one file per subsystem; shared
  fakes live in `TestSupport.swift`. Add new tests to the matching subsystem
  file, new fakes to `TestSupport.swift`.
- Do NOT add new source-text assertion tests (tests that read `.swift`/`.sh`/
  `.yml` files as strings). Existing ones are quarantined in
  `SourceTextGuardrailTests.swift` and are being replaced with behavior tests
  over time.
- Store tests construct `StudioStore` with injected fakes (see
  `TestSupport.swift`); follow that pattern instead of touching real devices,
  network, or TCC-gated APIs in default tests.

## Git

- Conventional-prefix commit messages (`feat:`, `fix:`, `refactor:`,
  `docs:`, `style:`, `test:`). Direct commits to `main`; no PRs unless asked.
- Never push without explicit operator consent.
```

**Verify**: `test -f AGENTS.md && head -1 AGENTS.md` → `# MacStream — agent & contributor notes`

## Test plan

No new tests — this plan redistributes existing ones. The verification IS the
test plan: the suite must pass with exactly the same test count (233) as
before the split.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `swift build` exits 0
- [ ] `swift test` (from repo root) exits 0 and reports exactly `233 tests`
- [ ] `Tests/MacStreamCoreTests/` contains the 14 files listed in Scope
- [ ] `grep -c '^@Test' Tests/MacStreamCoreTests/SourceTextGuardrailTests.swift` → 13
- [ ] `wc -l Tests/MacStreamCoreTests/DirectorEngineTests.swift` → under 200 lines
- [ ] `grep -rn '^private final class FixedSignalProvider' Tests/` → no matches (fakes are internal now)
- [ ] `AGENTS.md` exists at repo root
- [ ] `git status` shows no modified files outside the Scope list
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The drift check shows `Tests/MacStreamCoreTests/DirectorEngineTests.swift`
  changed since `03ae477` — the line-range manifest above is then stale.
- After two reconciliation passes in Step 4, `swift build --build-tests`
  still fails for reasons other than the two expected failure classes.
- `swift test` passes but reports a count other than 233 and you cannot
  identify the lost/duplicated test within one comparison pass
  (`grep -h '^func ' Tests/MacStreamCoreTests/*.swift | sort` vs the original
  file's function list at `03ae477`, via `git show 03ae477:Tests/MacStreamCoreTests/DirectorEngineTests.swift`).
- Any test needs its **body** edited to pass — that is a behavior change and
  out of scope.

## Maintenance notes

- Plans 002–006 add tests to the new subsystem files; if you rename any file
  here, update those plans' "Test plan" sections.
- The 13 quarantined guardrail tests are candidates for replacement with
  behavior tests (audit finding TESTS-01); that work is deferred, not
  forgotten — it is listed in `plans/README.md` under deferred findings.
- A formatter (`.swiftformat`) is deliberately NOT introduced here; adopt it
  only after plans 002–006 land, in a dedicated mechanical commit.
