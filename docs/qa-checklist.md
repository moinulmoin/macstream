# MacStream QA Checklist

Use this checklist before release promotion and after any media-pipeline change. Prefer testing the packaged app from `dist/MacStream.app` or a release zip, not a raw executable.

## Build And Launch

- Run `swift test`.
- Run `./script/build_and_run.sh --verify`.
- Confirm `dist/MacStream.app` launches.
- Confirm bundle identifier is `com.ideaplexa.macstream`.
- Confirm the icon renders correctly in Finder/Dock.
- Confirm no source files changed after build except intentional edits: `git status --short`.

## Fresh Install And Permissions

- Launch from a clean app install.
- Start on `BRB` without camera/screen capture activating.
- Select `Face`; camera permission state is clear.
- Select `Screen`; Screen Recording state is clear.
- Select `Screen + Face`; both camera and screen readiness are clear.
- Grant Camera and confirm preview works without extra restart.
- Grant Microphone and confirm mic level/speech signal works.
- Grant Screen Recording, quit/reopen, and confirm the relaunch-scoped row resolves.
- Deny each permission and confirm recovery routes to the right System Settings pane.

## Source Setup

- Confirm default sources: camera on, screen on, mic on, system audio off.
- Toggle optional mic/system audio while idle.
- Confirm required sources cannot be turned off while active capture depends on them.
- Confirm source levels are persisted across relaunch.
- Confirm screen target preference persists across relaunch.
- Confirm camera mirror, rotation, and auto light settings persist across relaunch.

## Preview Scenes

- `BRB`: no camera or screen capture starts.
- `Face`: camera preview is live, nonblack, correct orientation.
- `Screen`: selected screen/window preview is live and nonblack.
- `Screen + Face`: screen preview plus camera PiP render correctly.
- Disable camera and confirm camera preview stops/placeholder appears.
- Disable screen or set screen level to zero and confirm screen preview/sampling stops.
- Switch scenes repeatedly while idle and confirm no permission prompts loop.

## Recording

- Start local recording from `Screen`.
- Stop recording and verify the `.mov` exists under Movies/MacStream.
- Play the file and verify video is not black.
- Verify microphone audio is present when mic is enabled.
- Verify system audio is present only when system audio is enabled.
- Verify A/V sync at 5, 10, and 30 minutes.
- Start local recording from `Screen + Face` and confirm the camera PiP is baked into the `.mov`.
- While recording from `Screen + Face`, confirm the camera mirror/rotation/light settings match the selected camera settings.
- Start recording, then try to change required scene/source/target; confirm unsafe changes are blocked.
- Cancel a pending recording start and confirm no corrupt session remains.

## RTMP / Preview Transport

- Start and stop Preview mode.
- Switch destination to RTMP with a malformed URL and confirm start is blocked.
- Use a valid RTMP URL in default build and confirm wording says Endpoint Check, not Go Live.
- In a HaishinKit build, connect to a test RTMP server and verify real Screen media arrives, then verify `Screen + Face` arrives remotely with the camera PiP included.
- Cancel an RTMP connection attempt and confirm late success does not mark the stream live.
- Verify stream key never appears in events, exports, release notes, or visible reports.

## Health And Performance

- Run 30 minute `Screen + Face` recording with mic and optional system audio.
- Run 30 minute screen-only recording with mic and system audio.
- Track capture FPS, dropped frames, memory, CPU, and thermal pressure.
- Trigger Low Power Mode or thermal pressure where possible; confirm Adaptive mode lowers capture cost.
- Confirm dropped frames or low FPS move capture to degraded state and later recover.
- Sleep/wake during idle and active capture; record behavior.
- Connect/disconnect external display while idle; confirm target list updates after rescan.
- Close selected window while idle and while capture is active; record recovery behavior.

## Clip And Report Export

- Mark a manual clip while recording.
- Attempt clip mark while offline; confirm warning is not spammed.
- Export clip markers twice quickly; filenames must not collide.
- Export session report twice quickly; filenames must not collide.
- Confirm report includes transport, health, sources, selected capture target, events, and recording path.
- Confirm report excludes RTMP secrets.

## AI Provider Behavior

- Confirm setup assistance is visible only while capture is idle.
- Confirm starting preview, streaming, recording, connecting, or stopping disables setup generation.
- Confirm the default rules provider produces a setup plan without a configured model provider.
- Confirm provider offline/error states surface as fallback status instead of blocking capture.
- Confirm director cues during live capture come from deterministic signals, not model output.

## Release Artifact

- Download the GitHub release zip.
- Unzip and launch outside the repo.
- Verify Gatekeeper accepts the app.
- Verify notarization/stapling if this is a signed release.
- Repeat the permission and recording smoke checks from the release artifact.
