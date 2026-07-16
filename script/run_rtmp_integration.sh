#!/usr/bin/env bash
set -euo pipefail

DURATION="${MAC_STREAM_RTMP_INTEGRATION_DURATION:-5}"
FPS="${MAC_STREAM_RTMP_INTEGRATION_FPS:-15}"
PORT="${MAC_STREAM_RTMP_INTEGRATION_PORT:-19350}"
STREAM_NAME="${MAC_STREAM_RTMP_INTEGRATION_STREAM_NAME:-macstream-integration}"

if [[ ! "$DURATION" =~ ^[1-9][0-9]*$ ]]; then
  echo "MAC_STREAM_RTMP_INTEGRATION_DURATION must be a positive integer." >&2
  exit 2
fi
if [[ ! "$FPS" =~ ^[1-9][0-9]*$ ]] || (( FPS < 10 || FPS > 30 )); then
  echo "MAC_STREAM_RTMP_INTEGRATION_FPS must be between 10 and 30." >&2
  exit 2
fi
if [[ ! "$PORT" =~ ^[1-9][0-9]*$ ]] || (( PORT > 65535 )); then
  echo "MAC_STREAM_RTMP_INTEGRATION_PORT must be a valid TCP port." >&2
  exit 2
fi

for command_name in ffmpeg ffprobe swift; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name" >&2
    exit 2
  fi
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macstream-rtmp-integration.XXXXXX")"
INGEST_LOG="$WORK_DIR/ffmpeg-ingest.log"
CAPTURE_PATH="$WORK_DIR/ingest.flv"
CONNECTION_URL="rtmp://127.0.0.1:$PORT/live"
PUBLISH_URL="$CONNECTION_URL/$STREAM_NAME"
INGEST_PID=""

cleanup() {
  if [[ -n "$INGEST_PID" ]] && kill -0 "$INGEST_PID" 2>/dev/null; then
    kill "$INGEST_PID" 2>/dev/null || true
    wait "$INGEST_PID" 2>/dev/null || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

ffmpeg \
  -hide_banner \
  -loglevel warning \
  -nostdin \
  -listen 1 \
  -timeout -1 \
  -i "$PUBLISH_URL" \
  -c copy \
  -y \
  "$CAPTURE_PATH" >"$INGEST_LOG" 2>&1 &
INGEST_PID=$!

sleep 1
if ! kill -0 "$INGEST_PID" 2>/dev/null; then
  cat "$INGEST_LOG" >&2
  echo "Local RTMP ingest failed to start." >&2
  exit 1
fi

PUBLISH_STATUS=0
(
  cd "$ROOT_DIR"
  MAC_STREAM_ENABLE_HAISHINKIT=1 \
  MAC_STREAM_RUN_RTMP_INTEGRATION=1 \
  MAC_STREAM_RTMP_INTEGRATION_URL="$CONNECTION_URL" \
  MAC_STREAM_RTMP_INTEGRATION_STREAM_NAME="$STREAM_NAME" \
  MAC_STREAM_RTMP_INTEGRATION_DURATION="$DURATION" \
  MAC_STREAM_RTMP_INTEGRATION_FPS="$FPS" \
  swift test --filter haishinKitPublisherSendsSyntheticVideoToConfiguredRTMPIngest
) || PUBLISH_STATUS=$?

if (( PUBLISH_STATUS != 0 )); then
  cat "$INGEST_LOG" >&2
  echo "RTMP publisher integration test failed." >&2
  exit "$PUBLISH_STATUS"
fi

INGEST_STATUS=0
wait "$INGEST_PID" || INGEST_STATUS=$?
INGEST_PID=""

if [[ ! -s "$CAPTURE_PATH" ]]; then
  cat "$INGEST_LOG" >&2
  echo "Local RTMP ingest did not produce a capture file." >&2
  exit 1
fi

if ! probe_output="$(
  ffprobe \
    -v error \
    -count_frames \
    -select_streams v:0 \
    -show_entries stream=codec_name,width,height,nb_read_frames \
    -of csv=p=0 \
    "$CAPTURE_PATH"
)"; then
  cat "$INGEST_LOG" >&2
  echo "Local RTMP ingest capture could not be decoded." >&2
  exit 1
fi
read -r codec_name width height frame_count <<<"$(tr ',' ' ' <<<"$probe_output")"

minimum_frames=$((DURATION * FPS * 9 / 10))
if [[ "$codec_name" != "h264" || "$width" != "640" || "$height" != "360" ]]; then
  echo "Unexpected ingest video: codec=$codec_name size=${width}x${height}" >&2
  exit 1
fi
if [[ ! "$frame_count" =~ ^[0-9]+$ ]] || (( frame_count < minimum_frames )); then
  echo "Expected at least $minimum_frames decoded frames, got '$frame_count'." >&2
  exit 1
fi

if (( INGEST_STATUS != 0 )); then
  echo "RTMP listener exited with status $INGEST_STATUS after publisher disconnect; decoded media validation passed." >&2
fi
echo "RTMP integration passed: $frame_count H.264 frames at ${width}x${height}."
