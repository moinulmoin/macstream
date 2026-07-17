# Contributing to MacStream

MacStream is a streaming-first macOS prototype. Contributions should improve
capture, composition, publishing, performance, reliability, or the core studio
workflow. AI, editing, and broad production-suite features remain deferred.

## Development Setup

Requirements:

- Apple Silicon Mac
- Xcode with the macOS 26 SDK
- Swift 6

Run the baseline checks from the repository root:

```bash
swift build
swift test
MAC_STREAM_ENABLE_HAISHINKIT=1 swift build
MAC_STREAM_ENABLE_HAISHINKIT=1 swift test
```

The default build does not publish media. Enable HaishinKit when changing the
real RTMP/RTMPS path. See [the release guide](docs/releasing.md) for all build
variants and packaging checks.

## Change Guidelines

- Keep `StudioStore` as the single `@MainActor @Observable` source of truth.
- Keep sample-buffer callbacks free of per-frame allocations and main-thread
  hops.
- Never expose stream keys in UI, logs, events, reports, or test fixtures.
- Keep AI providers optional and outside the live capture path.
- Prefer focused behavior tests using Swift Testing and injected fakes.
- Do not add source-text assertion tests.
- Do not commit `.build/`, `.swiftpm/`, `dist/`, credentials, certificates, or
  private keys.

## Pull Requests

By submitting a contribution, you confirm that you have the right to submit it
and agree that it is licensed under the project's
[GNU AGPL v3.0-only license](LICENSE).

Before opening a pull request:

1. Rebase or merge the latest `main` without rewriting shared history.
2. Run the checks relevant to the changed build variants.
3. Add or update behavior tests for user-visible or lifecycle changes.
4. Update `CHANGELOG.md` under `Unreleased` for notable changes.
5. Describe manual capture, streaming, or UI validation that cannot run in CI.

Use conventional commit prefixes such as `feat:`, `fix:`, `perf:`, `test:`,
`docs:`, `refactor:`, `style:`, `ci:`, and `chore:`.

## Bug Reports

Include the macOS version, Mac model, MacStream version, selected sources,
output profile, expected behavior, actual behavior, and reproducible steps.
Attach a redacted session report when useful. Never include stream keys,
credentials, private ingest URLs, or signing material.
