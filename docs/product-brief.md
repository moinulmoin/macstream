# MacStream Product Brief

MacStream is a native macOS streaming studio for solo creators who combine a
screen or window with a webcam. The primary product promise is:

> Configure the output, prove it in preview, and keep it reliable while live.

## Audience

- coding and development streams;
- product and design demos;
- workshops and teaching;
- founder livestreams;
- screen-share podcasts and presentations.

## Core Workflow

1. Select the camera, microphone, and display or window.
2. Confirm permissions, source readiness, audio input, and destination preflight.
3. Configure the canvas background, padding, source split, viewport, and preview cost.
4. Preview Webcam, Screen + Webcam, Screen, or BRB.
5. Optionally make a short local proof recording.
6. Start RTMP/RTMPS publishing, optionally recording the same session locally.
7. Monitor throughput, dropped frames, A/V drift, queue pressure, and recovery state.
8. Stop cleanly and review the exported session diagnostics when needed.

## Product Boundaries

MacStream is deliberately narrower than OBS:

- streaming is the primary workflow;
- recording is a companion capability, not an editing pipeline;
- multi-destination publishing is planned but not implemented;
- video editing and post-production are out of scope;
- automatic camera effects are optional future enhancements;
- AI features are deferred until long-session reliability and performance gates pass.

## Reliability Principle

The live media path must be deterministic, observable, and bounded. Capture,
composition, recording, publishing, and reconnect behavior cannot depend on a
model provider or perform unbounded work on sample-buffer callbacks.

The app should fail explicitly and recover when possible. It must never hide
stream-key errors, queue saturation, recording failure, or unhealthy A/V timing
behind a cosmetic "live" state.

## Future AI Principle

Future setup assistance, transcription, summaries, and cue explanations may be
provider-backed, but they must remain optional and outside the live hot path.
Model output must not control live scene switching.
