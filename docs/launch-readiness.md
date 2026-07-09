# Launch Readiness Checklist

Check items off as they're verified. Link to benchmark artifacts, screenshots, or
test logs where applicable. When every box is checked, MacStream is ready for
public release.

---

## 1. Code Signing & Gatekeeper

> Source: [releasing.md](releasing.md), [qa-checklist.md](qa-checklist.md)

- [ ] Developer ID Application certificate is valid and not expired
- [ ] Hardened runtime is enabled (`--options runtime`)
- [ ] Release entitlements include `com.apple.security.device.camera` and
  `com.apple.security.device.audio-input`
- [ ] `codesign --verify --strict --verbose=2 dist/MacStream.app` passes
- [ ] `spctl -a -vv --type execute dist/MacStream.app` shows `accepted` with
  `source=Notarized Developer ID`
- [ ] Notarization submits without error
- [ ] Notarization status returns `Accepted` (not `Invalid` or `In Progress`)
- [ ] Notarization ticket is stapled (`xcrun stapler staple dist/MacStream.app`
  → `The staple and validate action worked!`)
- [ ] `xcrun stapler validate dist/MacStream.app` passes
- [ ] Bundle identifier reads `com.ideaplexa.macstream`
- [ ] App icon appears in Finder, Dock, and Launchpad
- [ ] Release zip extracts to a launchable app outside the repo directory
- [ ] Zip SHA256 checksum matches the published `.sha256` file

---

## 2. Fresh-Mac Permission Flow (TCC)

> Source: [architecture.md](architecture.md), [qa-checklist.md](qa-checklist.md)

- [ ] First launch on `BRB` scene shows the preflight checklist with permission
  guidance
- [ ] Camera prompt appears → grant → camera preview renders in Face scene
- [ ] Microphone prompt appears → grant → mic level meter shows signal
- [ ] Screen Recording prompt appears → grant → relaunch required
- [ ] After relaunch, Screen Recording is detected and display/window capture works
- [ ] Denying Camera → "Open Settings" button opens `x-apple.systempreferences:`
  to Camera privacy pane
- [ ] Denying Microphone → "Open Settings" button opens `x-apple.systempreferences:`
  to Microphone privacy pane
- [ ] Denying Screen Recording → "Open Settings" button opens
  `x-apple.systempreferences:` to Screen & System Audio Recording privacy pane
- [ ] No camera connected → appropriate unavailable state, no crash
- [ ] No microphone connected → appropriate unavailable state, no crash
- [ ] TCC identity is stable across rebuilds with same bundle ID
  (ad-hoc signing caveat noted if applicable)

---

## 3. RTMP Live Ingest QA

> Source: [qa-checklist.md](qa-checklist.md), [current-state.md](current-state.md),
> [benchmark-plan.md](benchmark-plan.md)

> ⚠️ **HIGHEST RISK.** This is the gating item before release-grade streaming.

### Screen publish

- [ ] 30-minute Screen publish to real ingest endpoint — video present throughout
- [ ] A/V sync verified at 5, 15, and 30 minutes (clap test or equivalent)
- [ ] Bitrate stable within platform ceiling (no wild oscillation)
- [ ] Zero dropped frames over last 10 minutes
- [ ] Reconnect on network interruption restores cleanly (no duplicate frames,
  no A/V drift)
- [ ] Stream stop → state returns to offline, health metrics finalize

### Screen + Face composited publish

- [ ] 30-minute Screen+Face publish — camera PiP is visible on remote output
- [ ] PiP position and size match local preview
- [ ] A/V sync across camera, screen, microphone, and system audio
- [ ] Bitrate stable with composited frames
- [ ] Scene switch during stream (Face → Screen+Face → Screen → BRB → Screen+Face)
  — no glitch, no black frames, no audio pop
- [ ] BRB splash reaches remote output during BRB scene
- [ ] Reconnect after network loss restores composited output
- [ ] 60-minute stress test: no drift, no memory growth, no crash

### Secret redaction

- [ ] Stream key is never logged in plaintext
- [ ] Stream key is masked in Destination panel (`••••••••`)
- [ ] Exported session report has stream key redacted
- [ ] Exported clip markers have stream key redacted
- [ ] StudioEvent log entries have stream key redacted

### Edge cases

- [ ] Default build (no HaishinKit) shows "Endpoint Check" label, not "Go Live"
- [ ] Malformed RTMP URL is blocked with clear error
- [ ] Cancel during "connecting" returns to offline cleanly
- [ ] Stream key field in Settings does not echo in plaintext
- [ ] Rapid start/stop/start does not leak resources or crash
- [ ] Idle-to-capture transition on stream start holds director steady

---

## 4. Recording Playback Verification

> Source: [qa-checklist.md](qa-checklist.md), [benchmark-plan.md](benchmark-plan.md)

- [ ] 30-minute Screen `.mov` — no black frames, no frozen frames
- [ ] 30-minute Screen `.mov` — microphone audio present and in sync
- [ ] 30-minute Screen `.mov` — system audio present (when enabled) and in sync
- [ ] 30-minute Screen+Face `.mov` — camera PiP baked into video frame, correct
  position and size
- [ ] 30-minute Screen+Face `.mov` — A/V sync across all sources
- [ ] 60-minute long-session recording — no drift, no corruption, file is playable
- [ ] Recording file size is reasonable for the duration
- [ ] Two consecutive recordings produce distinct filenames (no overwrite)
- [ ] Recording stops cleanly on app quit
- [ ] Recording path appears in Destination panel with Open/Reveal buttons

---

## 5. HaishinKit Smoke Tests

> Source: [qa-checklist.md](qa-checklist.md), `Package.swift`

- [ ] `MAC_STREAM_ENABLE_HAISHINKIT=1 swift build` succeeds
- [ ] `Package.resolved` does not change unexpectedly after resolve
- [ ] App launches with HaishinKit linked (no dyld errors)
- [ ] RTMP publisher connects to a test ingest server
- [ ] Screen media arrives at ingest endpoint
- [ ] Screen+Face composited media arrives at ingest endpoint
- [ ] HaishinKit variant built in CI on every push

---

## 6. AI Provider Integration

> Source: [qa-checklist.md](qa-checklist.md), [architecture.md](architecture.md),
> [current-state.md](current-state.md)

- [ ] Rules provider generates valid setup plans (keyword match: "podcast",
  "coding", "demo", "teaching")
- [ ] Setup generation is blocked during active capture (streaming, connecting,
  recording, stopping)
- [ ] In-flight generation is cancelled when capture starts
- [ ] Provider offline → visible fallback to rules, no crash, no spinner hang
- [ ] OpenAI-compatible endpoint smoke test: LM Studio or Ollama → valid
  `SetupPlan` return
- [ ] Provider API key stored in Keychain, masked in Settings
- [ ] "Test connection" button in Settings probes `/v1/models` and reports
  status
- [ ] Foundation Models provider smoke test (macOS 26 native)
- [ ] `MAC_STREAM_ENABLE_MLX=1 swift build` compiles without model loading
- [ ] Director remains deterministic regardless of provider state (no model
  inference on live path)

---

## 7. CI/CD Pipeline Verification

> Source: [releasing.md](releasing.md), `.github/workflows/ci.yml`,
> `.github/workflows/release.yml`

- [ ] CI workflow (`ci.yml`) passes on push to `main`:
  - tests pass
  - default build succeeds
  - HaishinKit-only build succeeds
  - MLX-only build succeeds
  - package smoke test succeeds
- [ ] CI workflow uploads a valid `.app` artifact
- [ ] Release workflow (`release.yml`) triggers on annotated `v*.*.*` tag push
- [ ] Certificate import succeeds (all 6 secrets present and valid)
- [ ] Notarization submits and completes without manual intervention
- [ ] Stapling validates after notarization
- [ ] GitHub Release is created with:
  - `MacStream-vX.Y.Z-macos-arm64.zip`
  - `MacStream-vX.Y.Z-macos-arm64.zip.sha256`
  - Release notes with version, sha256, and verification commands
- [ ] Manual workflow dispatch with `publish_release=true` works as fallback

---

## 8. Version Tagging & Artifact

> Source: [releasing.md](releasing.md)

- [ ] Working tree is clean (no uncommitted changes)
- [ ] All tests pass before tag is created
- [ ] Annotated tag created: `git tag -a vX.Y.Z -m "MacStream vX.Y.Z"`
- [ ] Tag pushed: `git push origin vX.Y.Z`
- [ ] Release zip naming follows convention: `MacStream-vX.Y.Z-macos-arm64.zip`
- [ ] SHA256 file is accurate and downloadable
- [ ] Release notes include verification commands
- [ ] No build artifacts in git (`dist/`, `.build/`, `.swiftpm/` are gitignored)
- [ ] Version in `Info.plist` matches tag

---

## 9. Documentation Audit

> Source: all docs

- [ ] README.md is complete and reflects all implemented features
- [ ] Architecture doc matches current implementation (class names, file structure)
- [ ] Product brief aligns with README feature claims
- [ ] MVP scope doc accurately separates in/out for v0.2.0
- [ ] QA checklist covers all current features
- [ ] Release process doc matches CI workflow reality
- [ ] Launch readiness checklist (this document) is linked from README
- [ ] All doc cross-references resolve (no 404 links)
- [ ] `AGENTS.md` build/test commands match current toolchain

---

## 10. Final Sanity

> Source: [qa-checklist.md](qa-checklist.md) — all sections

Run the full QA checklist from a release artifact on a Mac that has never run the
dev build.

- [ ] App launches from release zip (no quarantine block)
- [ ] Full QA checklist pass from fresh Mac
- [ ] Clip markers export: two rapid exports produce distinct filenames
- [ ] Session reports export: two rapid exports produce distinct filenames,
  secrets redacted
- [ ] Adaptive performance reacts to system pressure:
  - thermal state triggers → capture cost lowers
  - recovery → capture quality returns
  - Low Power Mode → adjusts policy
- [ ] Sleep/wake during idle → no crash, state consistent
- [ ] Sleep/wake during active capture → recording/stream state recovers or
  fails cleanly
- [ ] External display connect/disconnect → no crash, screen picker updates
- [ ] Window close with active capture → confirmation alert or clean shutdown
- [ ] Keyboard shortcuts work: Cmd+Shift+L (stream), Cmd+Shift+R (recording),
  Cmd+Shift+M (clip), Cmd+Shift+E (clip export), Cmd+Opt+E (session report)
- [ ] Settings persist across app restarts (preferences, destination, camera/mic
  selections)
- [ ] StudioStore stays consistent: no state leaks between Offline/Live/Recording

---

## Gate Summary

### ⚠️ Highest-Risk Gates (must pass)

| Gate | Why it's high risk |
|------|--------------------|
| Screen+Face RTMP live ingest with remote PiP | First time composited RTMP has been proven against a real endpoint |
| Long-session A/V sync (30+ min) | Drift over time is the most common streaming bug class |
| Fresh-Mac TCC flow with packaged app | Permission UX on a clean Mac hasn't been tested with the final bundle |
| Developer ID → notarization → Gatekeeper | End-to-end release ceremony hasn't been exercised with real credentials |

### Once everything is checked

Tag `v0.2.0` (or the first version that clears all gates), push the tag,
and the release workflow ships a signed, notarized, Gatekeeper-accepted
`MacStream.app`.

Add a launch blog post or release announcement linking to the README, and
you're live.

---

_Last updated: 2026-06-12_
