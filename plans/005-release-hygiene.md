# Plan 005: Pin release automation actions and lock optional dependency resolution

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 03ae477..HEAD -- .github/workflows/ci.yml .github/workflows/release.yml Package.resolved Tests/MacStreamCoreTests/SourceTextGuardrailTests.swift plans/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: plans/001-split-test-monolith.md
- **Category**: security / deps
- **Planned at**: commit `03ae477`, 2026-06-11

## Why this matters

The CI and release workflows execute third-party GitHub Actions by mutable tags
while the release workflow also has release-write token permissions and imports
Developer ID signing/notarization secrets. A retagged or compromised action could
run with privileges that are broader than the step needs. Optional dependency
resolution is also incomplete: the HaishinKit graph is pinned in
`Package.resolved`, but the MLX graph is resolved fresh on CI/release runners.
This plan makes the automation reproducible and narrows the release-write token
to the publish job that actually needs it.

## Current state

- `.github/workflows/ci.yml` — CI for tests, default build, optional feature
  builds, and ad-hoc packaging. It already uses least-privilege workflow-level
  read permissions:

```yaml
# .github/workflows/ci.yml:10-14
permissions:
  contents: read

env:
  FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: "true"
```

- `.github/workflows/ci.yml` currently references mutable action tags and builds
  optional dependency graphs:

```yaml
# .github/workflows/ci.yml:26-28
      - name: Check out repository
        uses: actions/checkout@v6
```

```yaml
# .github/workflows/ci.yml:46-51
      - name: Build optional feature configurations
        shell: bash
        run: |
          set -euo pipefail
          MAC_STREAM_ENABLE_HAISHINKIT=1 swift build -c release --arch arm64
          MAC_STREAM_ENABLE_MLX=1 swift build -c release --arch arm64
```

```yaml
# .github/workflows/ci.yml:70-75
      - name: Store app bundle smoke artifact
        uses: actions/upload-artifact@v7
        with:
          name: MacStream-ci-macos-arm64
          path: dist/MacStream-ci-macos-arm64.zip
          if-no-files-found: error
```

- `.github/workflows/release.yml` currently grants release-write permission at
  workflow scope:

```yaml
# .github/workflows/release.yml:19-23
permissions:
  contents: write

env:
  FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: "true"
```

- `.github/workflows/release.yml` has a single `macos` job that checks out code,
  imports Developer ID signing material, notarizes, uploads the workflow
  artifact, and publishes a GitHub Release. The mutable action tags in this job
  are:

```yaml
# .github/workflows/release.yml:37-41
    steps:
      - name: Check out repository
        uses: actions/checkout@v6
        with:
          fetch-depth: 0
```

```yaml
# .github/workflows/release.yml:197-204
      - name: Upload workflow artifact
        uses: actions/upload-artifact@v7
        with:
          name: ${{ steps.artifact.outputs.artifact_name }}
          path: |
            ${{ steps.artifact.outputs.zip_path }}
            ${{ steps.artifact.outputs.sha256_path }}
          if-no-files-found: error
```

- The same release job imports secrets and later exposes `github.token` to
  `gh release`:

```yaml
# .github/workflows/release.yml:117-136
      - name: Import Developer ID certificate
        shell: bash
        env:
          MAC_STREAM_MACOS_CERTIFICATE_P12_BASE64: ${{ secrets.MAC_STREAM_MACOS_CERTIFICATE_P12_BASE64 }}
          MAC_STREAM_MACOS_CERTIFICATE_PASSWORD: ${{ secrets.MAC_STREAM_MACOS_CERTIFICATE_PASSWORD }}
        run: |
          set -euo pipefail
          keychain_path="$RUNNER_TEMP/macstream-signing.keychain-db"
          keychain_password="$(uuidgen)"
          certificate_path="$RUNNER_TEMP/macstream-developer-id.p12"
```

```yaml
# .github/workflows/release.yml:238-246
      - name: Publish GitHub Release
        if: github.event_name == 'push' || inputs.publish_release == true
        shell: bash
        env:
          GH_TOKEN: ${{ github.token }}
          RELEASE_VERSION: ${{ steps.version.outputs.release_version }}
          ZIP_PATH: ${{ steps.artifact.outputs.zip_path }}
          SHA256_PATH: ${{ steps.artifact.outputs.sha256_path }}
          NOTES_PATH: ${{ steps.notes.outputs.notes_path }}
```

- `Package.swift` only includes optional dependencies when environment flags are
  set. HaishinKit starts at `from: "2.2.0"`; MLX starts at `from: "3.31.3"`:

```swift
# Package.swift:9-19
let packageDependencies: [Package.Dependency] =
    (enableHaishinKitRTMP
     ? [
        .package(url: "https://github.com/HaishinKit/HaishinKit.swift", from: "2.2.0")
     ]
     : [])
    + (enableMLX
       ? [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.3")
       ]
       : [])
```

- `Package.resolved` currently pins only HaishinKit and Logboard; no MLX pins are
  present:

```json
# Package.resolved:3-23
  "pins" : [
    {
      "identity" : "haishinkit.swift",
      "kind" : "remoteSourceControl",
      "location" : "https://github.com/HaishinKit/HaishinKit.swift",
      "state" : {
        "revision" : "dc880cb540b8feeb98f64e8b7dcfaaf320b6b2bd",
        "version" : "2.2.5"
      }
    },
    {
      "identity" : "logboard",
      "kind" : "remoteSourceControl",
      "location" : "https://github.com/shogo4405/Logboard.git",
      "state" : {
        "revision" : "8f41c63afb903040b77049ee2efa8c257b8c0d50",
        "version" : "2.6.0"
      }
    }
  ],
  "version" : 3
```

- After plan 001, the source-text guardrail test lives in
  `Tests/MacStreamCoreTests/SourceTextGuardrailTests.swift`. Its original home
  and line at commit `03ae477` is
  `Tests/MacStreamCoreTests/DirectorEngineTests.swift:577`:
  `releaseAutomationDefinesSignedNotarizedMacPipeline`. The workflow assertions
  that this plan can break are exactly:

```swift
# Tests/MacStreamCoreTests/DirectorEngineTests.swift:599-611
    #expect(ci.contains("runs-on: macos-26"))
    #expect(ci.contains("FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: \"true\""))
    #expect(ci.contains("swift test"))
    #expect(ci.contains("swift build -c release --arch arm64"))
    #expect(ci.contains("MAC_STREAM_ENABLE_HAISHINKIT=1 swift build -c release --arch arm64"))
    #expect(ci.contains("MAC_STREAM_ENABLE_MLX=1 swift build -c release --arch arm64"))
    #expect(ci.contains("MAC_STREAM_REQUIRE_HARDENED_RUNTIME: \"1\""))
    #expect(ci.contains("actions/checkout@v6"))
    #expect(ci.contains("actions/upload-artifact@v7"))
    #expect(release.contains("runs-on: macos-26"))
    #expect(release.contains("FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: \"true\""))
    #expect(release.contains("actions/checkout@v6"))
    #expect(release.contains("actions/upload-artifact@v7"))
```

```swift
# Tests/MacStreamCoreTests/DirectorEngineTests.swift:612-625
    #expect(release.contains("MAC_STREAM_MACOS_CERTIFICATE_P12_BASE64"))
    #expect(release.contains("MAC_STREAM_MACOS_CERTIFICATE_PASSWORD"))
    #expect(release.contains("MAC_STREAM_CODESIGN_IDENTITY"))
    #expect(release.contains("MAC_STREAM_APPLE_ID"))
    #expect(release.contains("MAC_STREAM_APPLE_TEAM_ID"))
    #expect(release.contains("MAC_STREAM_APP_SPECIFIC_PASSWORD"))
    #expect(release.contains("security import \"$certificate_path\""))
    #expect(release.contains("MAC_STREAM_REQUIRE_DEVELOPER_ID: \"1\""))
    #expect(release.contains("MAC_STREAM_REQUIRE_HARDENED_RUNTIME: \"1\""))
    #expect(release.contains("xcrun notarytool submit"))
    #expect(release.contains("xcrun stapler staple"))
    #expect(release.contains("spctl -a -vv --type execute"))
    #expect(release.contains("shasum -a 256"))
    #expect(release.contains("gh release create"))
```

  The assertions that must change are the four mutable-tag checks:
  `actions/checkout@v6` and `actions/upload-artifact@v7` in both workflow
  strings. Keep the other assertions unless a required workflow restructure moves
  equivalent text in a way that still preserves the same release guarantees.

- Unique current action references to pin:

| Workflow | Current `uses:` | Pin command |
|----------|-----------------|-------------|
| `.github/workflows/ci.yml` | `actions/checkout@v6` | `gh api repos/actions/checkout/git/ref/tags/v6 --jq .object.sha` |
| `.github/workflows/ci.yml` | `actions/upload-artifact@v7` | `gh api repos/actions/upload-artifact/git/ref/tags/v7 --jq .object.sha` |
| `.github/workflows/release.yml` | `actions/checkout@v6` | `gh api repos/actions/checkout/git/ref/tags/v6 --jq .object.sha` |
| `.github/workflows/release.yml` | `actions/upload-artifact@v7` | `gh api repos/actions/upload-artifact/git/ref/tags/v7 --jq .object.sha` |

  Each command must print one 40-hex object SHA. If the object is an annotated
  tag object, dereference it to the commit SHA with
  `gh api repos/<owner>/<repo>/git/tags/<sha-from-first-command> --jq .object.sha`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Drift check | `git diff --stat 03ae477..HEAD -- .github/workflows/ci.yml .github/workflows/release.yml Package.resolved Tests/MacStreamCoreTests/SourceTextGuardrailTests.swift plans/README.md` | no output, or only changes you have reviewed against this plan |
| Resolve checkout tag | `gh api repos/actions/checkout/git/ref/tags/v6 --jq .object.sha` | one 40-hex SHA; if annotated, dereference with `gh api repos/actions/checkout/git/tags/<sha> --jq .object.sha` |
| Resolve upload-artifact tag | `gh api repos/actions/upload-artifact/git/ref/tags/v7 --jq .object.sha` | one 40-hex SHA; if annotated, dereference with `gh api repos/actions/upload-artifact/git/tags/<sha> --jq .object.sha` |
| Resolve optional dependencies | `MAC_STREAM_ENABLE_HAISHINKIT=1 MAC_STREAM_ENABLE_MLX=1 swift package resolve` | exit 0; `Package.resolved` gains MLX-related pins |
| Check lockfile stability | `MAC_STREAM_ENABLE_HAISHINKIT=1 MAC_STREAM_ENABLE_MLX=1 swift package resolve && git diff --exit-code Package.resolved` | exit 0 after the lockfile is committed/complete |
| Plain build | `swift build` | exit 0, `Build complete!` |
| Tests | `swift test` (from repo root) | exit 0; final count is at least the count recorded in `plans/README.md` at execution time (233 at planning time) |
| Mutable-action scan | `grep -nE 'uses:.*@(v[0-9]|main|master)' .github/workflows/*.yml` | no matches; grep exits 1 |
| Scope check | `git status --short` | only in-scope files are modified |

## Scope

**In scope** (the only files you should modify):
- `.github/workflows/ci.yml`
- `.github/workflows/release.yml`
- `Package.resolved`
- `Tests/MacStreamCoreTests/SourceTextGuardrailTests.swift` (assertion strings only)
- `plans/README.md` (status row only)

**Out of scope** (do NOT touch):
- `Package.swift` — optional dependency declarations already exist.
- Any file under `Sources/` — no production code changes are needed.
- Any test body except the literal workflow assertion strings in
  `releaseAutomationDefinesSignedNotarizedMacPipeline`.
- Any signing, notarization, stream key, release token, or secret value. Never
  paste a secret into a file, command, note, or plan update.
- Adding new tests. This plan updates the existing source-text guardrail only.

## Git workflow

- Commit directly on `main` (repo convention — no PRs unless asked).
- Message style follows conventional prefixes (`feat:`, `fix:`, `refactor:`,
  `test:`, `ci:`), e.g. `ci: pin release actions and lock optional dependencies`.
- Do NOT push unless the operator explicitly instructed it.

## Steps

### Step 1: Resolve every action tag to a full commit SHA

Resolve the current action tags at execution time. Do **not** reuse SHAs from a
comment, a previous run, a web page, or this plan.

Run:

```bash
gh api repos/actions/checkout/git/ref/tags/v6 --jq .object.sha
gh api repos/actions/upload-artifact/git/ref/tags/v7 --jq .object.sha
```

For each result, confirm it is a 40-character lowercase hex string. If either
result identifies an annotated tag object rather than the commit object, run the
matching dereference command and use the dereferenced commit SHA:

```bash
gh api repos/actions/checkout/git/tags/<sha-from-ref> --jq .object.sha
gh api repos/actions/upload-artifact/git/tags/<sha-from-ref> --jq .object.sha
```

Record the two final commit SHAs in your scratch notes only, then use them in
Steps 2 and 3.

**Verify**: `printf '%s\n%s\n' '<checkout-sha>' '<upload-artifact-sha>' | grep -Ec '^[0-9a-f]{40}$'` → `2`

### Step 2: Pin `ci.yml` actions and add the optional lockfile guard

Edit `.github/workflows/ci.yml`:

1. Replace every mutable action tag with the resolved full SHA and keep the tag
   as a trailing comment, shape only:

```yaml
# shape, adapt to surrounding code
      - name: Check out repository
        uses: actions/checkout@<checkout-40-hex-sha> # v6
```

```yaml
# shape, adapt to surrounding code
      - name: Store app bundle smoke artifact
        uses: actions/upload-artifact@<upload-artifact-40-hex-sha> # v7
```

2. After checkout and before `Show toolchain`, add a lockfile verification step
   that resolves both optional graphs and fails if `Package.resolved` would
   change:

```yaml
# shape, adapt to surrounding code
      - name: Verify optional dependency lockfile
        shell: bash
        run: |
          set -euo pipefail
          MAC_STREAM_ENABLE_HAISHINKIT=1 MAC_STREAM_ENABLE_MLX=1 swift package resolve
          git diff --exit-code Package.resolved
```

Keep the existing workflow-level permissions as `contents: read`.

**Verify**: `grep -nE 'uses:.*@(v[0-9]|main|master)' .github/workflows/ci.yml` → no matches; command exits 1

### Step 3: Split release publish permissions from signing/notarization

Edit `.github/workflows/release.yml` to remove workflow-level
`contents: write` and ensure only the publish job has release-write token
permission.

Because the current release workflow has one job (`jobs.macos`) that both
imports signing/notarization secrets and runs `gh release`, a job-level-only move
would not materially reduce the risk: pinned action code in the signing job would
still have release-write permission. Use a two-job shape instead:

1. Change workflow-level permissions to read-only:

```yaml
# shape, adapt to surrounding code
permissions:
  contents: read
```

2. Keep the existing `macos` job for checkout, tests, optional builds, signing,
   notarization, artifact creation, and workflow artifact upload. Add explicit
   read permissions to that job:

```yaml
# shape, adapt to surrounding code
  macos:
    name: macOS signed release
    runs-on: macos-26
    permissions:
      contents: read
```

3. Pin `actions/checkout` and `actions/upload-artifact` in this job using the
   same SHA/comment shape as Step 2:

```yaml
# shape, adapt to surrounding code
        uses: actions/checkout@<checkout-40-hex-sha> # v6
        uses: actions/upload-artifact@<upload-artifact-40-hex-sha> # v7
```

4. Expose the release metadata needed by a new publish job as job outputs from
   existing step outputs:

```yaml
# shape, adapt to surrounding code
    outputs:
      release_version: ${{ steps.version.outputs.release_version }}
      artifact_name: ${{ steps.artifact.outputs.artifact_name }}
      sha256: ${{ steps.artifact.outputs.sha256 }}
```

5. Leave the `Write release notes` step in `macos` or move equivalent note
   generation to the publish job. If it stays in `macos`, do not pass a notes
   file path across jobs; runner temp paths do not survive between jobs. The
   safer shape is to regenerate release notes in `publish` from `needs.macos`
   outputs.

6. Move the `Publish GitHub Release` logic into a new `publish` job that has no
   signing/notarization secrets, depends on `macos`, and has the only
   release-write permission:

```yaml
# shape, adapt to surrounding code
  publish:
    name: Publish GitHub Release
    needs: macos
    runs-on: macos-26
    if: github.event_name == 'push' || inputs.publish_release == true
    permissions:
      contents: write
      actions: read
    env:
      APP_NAME: MacStream
      BUNDLE_ID: com.ideaplexa.macstream
    steps:
      - name: Download workflow artifact
        shell: bash
        env:
          GH_TOKEN: ${{ github.token }}
          ARTIFACT_NAME: ${{ needs.macos.outputs.artifact_name }}
        run: |
          set -euo pipefail
          mkdir -p "$RUNNER_TEMP/release-artifacts"
          gh run download "$GITHUB_RUN_ID" \
            --name "$ARTIFACT_NAME" \
            --dir "$RUNNER_TEMP/release-artifacts"

      - name: Write release notes
        id: notes
        shell: bash
        env:
          RELEASE_VERSION: ${{ needs.macos.outputs.release_version }}
          ARTIFACT_NAME: ${{ needs.macos.outputs.artifact_name }}
          SHA256: ${{ needs.macos.outputs.sha256 }}
        run: |
          set -euo pipefail
          notes_path="$RUNNER_TEMP/macstream-release-notes.md"
          # Keep the existing release-note body and use these env vars.
          echo "notes_path=$notes_path" >>"$GITHUB_OUTPUT"

      - name: Publish GitHub Release
        shell: bash
        env:
          GH_TOKEN: ${{ github.token }}
          RELEASE_VERSION: ${{ needs.macos.outputs.release_version }}
          ARTIFACT_NAME: ${{ needs.macos.outputs.artifact_name }}
          ZIP_PATH: ${{ runner.temp }}/release-artifacts/${{ needs.macos.outputs.artifact_name }}
          SHA256_PATH: ${{ runner.temp }}/release-artifacts/${{ needs.macos.outputs.artifact_name }}.sha256
          NOTES_PATH: ${{ steps.notes.outputs.notes_path }}
        run: |
          set -euo pipefail
          git rev-parse --verify "refs/tags/$RELEASE_VERSION" >/dev/null
          # Keep the existing gh release view/upload/edit/create logic.
```

7. The `publish` job needs tag verification. Since the new job does not check out
   the repository by default, either pin and add a checkout step with
   `fetch-depth: 0`, or replace `git rev-parse --verify` with an equivalent `gh
   api` tag-ref check. Prefer the `gh api` check to avoid adding another action
   execution to the release-write job:

```bash
# shape inside the Publish GitHub Release step
if ! gh api "repos/${GITHUB_REPOSITORY}/git/ref/tags/$RELEASE_VERSION" >/dev/null; then
  echo "Missing release tag: $RELEASE_VERSION" >&2
  exit 2
fi
```

**Verify**: `grep -nE 'uses:.*@(v[0-9]|main|master)' .github/workflows/release.yml` → no matches; command exits 1

### Step 4: Resolve and commit the full optional SwiftPM graph

Run the flagged resolve from the repo root:

```bash
MAC_STREAM_ENABLE_HAISHINKIT=1 MAC_STREAM_ENABLE_MLX=1 swift package resolve
```

Commit the resulting `Package.resolved` changes. The file should still include
`haishinkit.swift` and `logboard`, and should now also include `mlx-swift-lm`
and its transitive package pins. SwiftPM ignores these extra pins when the flags
are off; do not change `Package.swift`.

If the resolve wants network access, allow it in a normal development/CI
environment. If the current execution environment is sandboxed with no network,
STOP and report that the lockfile cannot be completed without network access.

If the new MLX resolution adds more than 25 total pins or introduces unexpected
non-Apple/non-MLX package families, STOP and list the new package identities for
review before committing the lockfile.

**Verify**: `MAC_STREAM_ENABLE_HAISHINKIT=1 MAC_STREAM_ENABLE_MLX=1 swift package resolve && git diff --exit-code Package.resolved` → exit 0 after the completed lockfile is staged/committed or otherwise accepted as the intended file content

### Step 5: Update the source-text guardrail assertions to the pinned form

Edit only assertion strings in
`Tests/MacStreamCoreTests/SourceTextGuardrailTests.swift`, function
`releaseAutomationDefinesSignedNotarizedMacPipeline` (original line 577 in
`DirectorEngineTests.swift` before plan 001).

Change the four mutable-tag expectations to assert the SHA-pinned shape while
still preserving the tag comment. Use the real SHAs from Step 1:

```swift
// shape, adapt to surrounding code
#expect(ci.contains("actions/checkout@<checkout-40-hex-sha> # v6"))
#expect(ci.contains("actions/upload-artifact@<upload-artifact-40-hex-sha> # v7"))
#expect(release.contains("actions/checkout@<checkout-40-hex-sha> # v6"))
#expect(release.contains("actions/upload-artifact@<upload-artifact-40-hex-sha> # v7"))
```

If Step 3 regenerates release notes in the `publish` job, keep the existing
assertions for `shasum -a 256`, `gh release create`, signing secret names,
notarization commands, and hardening flags by preserving equivalent text in the
workflow. Do not weaken the guardrail by deleting unrelated assertions.

**Verify**: `grep -n 'actions/checkout@v\|actions/upload-artifact@v' Tests/MacStreamCoreTests/SourceTextGuardrailTests.swift` → no matches; grep exits 1

### Step 6: Run final verification and update the plan index

Run the final checks from the repo root:

```bash
swift build
swift test
MAC_STREAM_ENABLE_HAISHINKIT=1 MAC_STREAM_ENABLE_MLX=1 swift package resolve
git diff --exit-code Package.resolved
grep -nE 'uses:.*@(v[0-9]|main|master)' .github/workflows/*.yml
git status --short
```

Expected results:

- `swift build` exits 0.
- `swift test` exits 0; final count is at least the count recorded in
  `plans/README.md` at execution time (233 at planning time).
- The flagged `swift package resolve` exits 0.
- `git diff --exit-code Package.resolved` exits 0 after the intended lockfile is
  complete.
- The mutable-action grep prints no matches and exits 1.
- `git status --short` lists only the in-scope files.

Then update the `plans/README.md` row for Plan 005 to `DONE` unless the
operator/reviewer told you they maintain the index.

**Verify**: `git status --short` → only `.github/workflows/ci.yml`, `.github/workflows/release.yml`, `Package.resolved`, `Tests/MacStreamCoreTests/SourceTextGuardrailTests.swift`, and `plans/README.md` are modified

## Test plan

No new tests.

Use the existing source-text guardrail test as the regression test:
`releaseAutomationDefinesSignedNotarizedMacPipeline`, original line
`Tests/MacStreamCoreTests/DirectorEngineTests.swift:577`, post-plan-001 home
`Tests/MacStreamCoreTests/SourceTextGuardrailTests.swift`. It must keep checking
that CI and release workflows define the signed/notarized pipeline, but its
action assertions must now expect SHA-pinned `uses:` lines with trailing tag
comments.

Verification:

- `swift test` from the repo root → exit 0; final count is at least the count
  recorded in `plans/README.md` at execution time (233 at planning time).
- `MAC_STREAM_ENABLE_HAISHINKIT=1 MAC_STREAM_ENABLE_MLX=1 swift package resolve && git diff --exit-code Package.resolved` → exit 0.
- `grep -nE 'uses:.*@(v[0-9]|main|master)' .github/workflows/*.yml` → no
  matches; grep exits 1.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `.github/workflows/ci.yml` has no `uses:` reference ending in a mutable
  tag (`@vN`, `@main`, or `@master`).
- [ ] `.github/workflows/release.yml` has no `uses:` reference ending in a
  mutable tag (`@vN`, `@main`, or `@master`).
- [ ] Every workflow `uses:` line has a full 40-hex SHA and a trailing tag
  comment such as `# v6` or `# v7`.
- [ ] `.github/workflows/release.yml` has workflow-level `permissions:
  contents: read`; the signing/notarization job has `contents: read`; only the
  publish job has `contents: write`.
- [ ] The release-write publish job does not import or receive Developer ID,
  Apple ID, app-specific password, or notarization secrets.
- [ ] `Package.resolved` includes the MLX optional dependency graph after
  `MAC_STREAM_ENABLE_HAISHINKIT=1 MAC_STREAM_ENABLE_MLX=1 swift package resolve`.
- [ ] `MAC_STREAM_ENABLE_HAISHINKIT=1 MAC_STREAM_ENABLE_MLX=1 swift package resolve && git diff --exit-code Package.resolved` exits 0.
- [ ] `swift build` exits 0.
- [ ] `swift test` exits 0 from the repo root; test count is at least the count
  recorded in `plans/README.md` at execution time (233 at planning time).
- [ ] `grep -nE 'uses:.*@(v[0-9]|main|master)' .github/workflows/*.yml` prints
  no matches and exits 1.
- [ ] `grep -n 'actions/checkout@v\|actions/upload-artifact@v' Tests/MacStreamCoreTests/SourceTextGuardrailTests.swift` prints no matches and exits 1.
- [ ] No files outside the in-scope list are modified (`git status --short`).
- [ ] `plans/README.md` status row for Plan 005 is updated to `DONE` unless a
  reviewer/operator explicitly owns the index update.

## STOP conditions

Stop and report back (do not improvise) if:

- The drift check shows in-scope changes after `03ae477` and the live excerpts no
  longer match this plan's "Current state" assumptions.
- `gh api repos/actions/checkout/git/ref/tags/v6 --jq .object.sha` or
  `gh api repos/actions/upload-artifact/git/ref/tags/v7 --jq .object.sha` cannot
  be resolved to a full 40-hex commit SHA.
- The workflow rewrite would require writing a secret value or token value into
  any file, command, log, test, or plan note.
- `releaseAutomationDefinesSignedNotarizedMacPipeline` asserts a workflow detail
  that cannot remain true after the token-scope split without weakening the
  release security model.
- `MAC_STREAM_ENABLE_HAISHINKIT=1 MAC_STREAM_ENABLE_MLX=1 swift package resolve`
  needs network access and the execution environment is sandboxed/offline.
- MLX resolution adds more than 25 total pins or pulls unexpected package
  families that need human review; stop and list the new package identities.
- The fix appears to require touching an out-of-scope file.
- A verification command fails twice after a narrow fix attempt.

## Maintenance notes

- The trailing tag comments are documentation only; the SHA is the execution
  target. Future action upgrades must repeat the `gh api ... git/ref/tags/...`
  resolution and update both the SHA and comment together.
- GitHub token permissions are job-scoped, not step-scoped. Keeping `gh release`
  in the signing job would preserve the original privilege overlap even if the
  YAML moved `permissions` from workflow to job level.
- The publish job uses `github.token` only for artifact download/release
  publication. It must not receive signing, notarization, Keychain, stream key,
  or Apple credential secrets.
- If a future workflow adds a new `uses:` action, pin it to a full SHA in the
  same commit and add/update the guardrail assertion if the action is part of
  the release security boundary.
- Optional dependency pins in `Package.resolved` are intentional even when flags
  are off. Do not delete MLX pins just because plain `swift build` does not load
  that graph.
