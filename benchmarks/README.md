# Reliability benchmark evidence

Store repeatable MacStream performance and long-session results here. Do not
commit stream keys, full RTMP URLs, credentials, or recordings containing
private information.

## Capture process metrics

Launch the signed app, find its process ID, and start a timed CSV capture:

```sh
pgrep -x MacStream
./script/record_reliability_metrics.sh \
  --pid <pid> \
  --duration 3600 \
  --interval 5
```

The CSV records UTC time, elapsed time, process CPU, resident memory in KB,
thread count, and process elapsed time. During the same run, use MacStream's
Health view and export a session report after stopping capture. The session
report contains capture FPS, dropped frames, outbound bitrate, audio delivery,
RTMP audio rejection, recovery, and A/V drift metrics.

## Result notes

Create a Markdown file next to each CSV with:

- Mac model, memory, macOS version, power state, and connected displays.
- MacStream version and output resolution/FPS/performance mode.
- Camera, microphone, screen target, and enabled audio sources.
- Ingest service or local test server name without credentials.
- Scenario and planned duration.
- Network interruptions or device changes with timestamps.
- Remote-output and local-recording validation results.
- Final session-report filename.
- Comparison with the matching OBS run when available.

Use `docs/v0.3-reliability-goal.md` as the v0.3 pass bar.

Current release-gate evidence and remaining work are tracked in
[`v0.3-validation.md`](v0.3-validation.md).

## Local RTMP integration

Run the actual HaishinKit publisher against an FFmpeg localhost listener:

```sh
./script/run_rtmp_integration.sh
```

The wrapper sends paced synthetic video through MacStream, records the incoming
RTMP stream, and verifies the H.264 dimensions and decoded frame count. Increase
`MAC_STREAM_RTMP_INTEGRATION_DURATION` for longer publisher-only runs. This does
not replace packaged ScreenCaptureKit, microphone, compositor, or remote-ingest QA.
