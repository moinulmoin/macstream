# Performance baseline

MacStream treats capture topology and frame latency as release behavior, not
implementation detail. Re-run this baseline on the same machine before and
after capture or compositor changes.

## Baseline scenario

Measured on July 9, 2026 with the release arm64 build, 1080p/60 FPS output,
and Sharp preview selected. CPU samples came from five one-second `top`
intervals after the scene had settled. A five-second `sample` trace was used
to identify active stacks.

| Scenario | CPU after warm-up | Resident memory | Active threads |
| --- | ---: | ---: | ---: |
| BRB, source meter active | 13.7-26.7% | about 106 MB | 13 |
| Screen + Webcam preview | 17.8-26.6% | about 64 MB | 18 |

The July 10 post-change release build measured 16.4-25.0% CPU, about 98 MB,
and 17 threads for the matching Screen + Webcam preview. A 1080p/60 FPS
Screen + Webcam local recording, including the canonical output-frame preview,
measured 26.8-44.0% CPU, about 244 MB, and 25-26 threads. The recording row is
an operational ceiling sample, not a direct comparison with the preview-only
baseline.

Memory is informational because macOS compression and framework reclamation
make short samples noisy. CPU, frame cadence, dropped frames, and capture
topology are the primary comparison points.

## Baseline worst-case topology

With preview, RTMP, recording, and director sampling active at once, the
pre-change architecture could create:

- Four screen streams: preview, publishing, recording, and motion sampling.
- Three camera sessions: preview, publishing, and recording.
- Two encoded compositors: publishing and recording.
- A separate microphone session for the level meter in addition to media
  capture.

## Implemented topology

The canvas/performance pass changes the active capture graph as follows:

- RTMP and recording converge on one `SCStream`, one camera session, one
  microphone session, and one compositor regardless of which starts first.
- Stopping either RTMP or recording transfers ownership without stopping the
  capture still in use by the other output.
- Active preview displays sampled frames accepted by the recording/RTMP output
  path. Its single-slot delivery queue replaces pending frames instead of
  starting separate screen and camera preview sessions.
- Screen-only and Screen + Webcam both render through the same fixed 16:9
  compositor contract. Screen-only does not start a camera session.
- Offline setup preview still uses low-cost native screen and camera previews.
  Director screen-motion sampling remains an independent optional producer.

## Acceptance gates

1. Preview, recording, and RTMP use the same canvas geometry and source
   transform contract.
2. Matching RTMP and recording outputs share one screen producer, one camera
   producer, and one composed frame.
3. Preview quality changes preview display cost without changing stream
   resolution or stream FPS.
4. Source-only layout changes do not reconfigure `SCStream`.
5. The live callback path performs no main-actor hops and no unbounded queue
   growth.
6. Compare steady-state CPU against this baseline on the same machine. Do not
   turn hardware-specific percentages into CI pass/fail thresholds.

The existing health snapshot tracks capture FPS, dropped frames, publish state,
bitrate, and outbound throughput. Per-stage compositor latency and pixel-buffer
allocation counters remain follow-up observability work.

## Repeatable local commands

Use CUA Driver to select a scene without foregrounding the application, then
collect process metrics with:

```sh
top -l 5 -s 1 -pid <pid> -stats pid,cpu,mem,time,threads
sample <pid> 5 -file /tmp/macstream.sample.txt
```

Run the default and HaishinKit-enabled test suites after every topology
change:

```sh
swift test
MAC_STREAM_ENABLE_HAISHINKIT=1 swift test
```
