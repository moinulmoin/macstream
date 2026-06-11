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
