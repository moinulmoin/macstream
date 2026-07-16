#!/usr/bin/env bash
set -euo pipefail

DURATION="${MAC_STREAM_RTMP_INTEGRATION_DURATION:-5}"
WARMUP_DURATION="${MAC_STREAM_RTMP_INTEGRATION_WARMUP_DURATION:-5}"
FPS="${MAC_STREAM_RTMP_INTEGRATION_FPS:-15}"
PORT="${MAC_STREAM_RTMP_INTEGRATION_PORT:-19350}"
STREAM_NAME="${MAC_STREAM_RTMP_INTEGRATION_STREAM_NAME:-macstream-integration}"
MEDIAMTX_VERSION="1.18.2"
MEDIAMTX_BIN="${MAC_STREAM_MEDIAMTX_BIN:-}"
SWIFT_SCRATCH_PATH="${MAC_STREAM_RTMP_INTEGRATION_SWIFT_SCRATCH_PATH:-}"

if [[ ! "$DURATION" =~ ^[1-9][0-9]*$ ]]; then
  echo "MAC_STREAM_RTMP_INTEGRATION_DURATION must be a positive integer." >&2
  exit 2
fi
if [[ ! "$WARMUP_DURATION" =~ ^[1-9][0-9]*$ ]]; then
  echo "MAC_STREAM_RTMP_INTEGRATION_WARMUP_DURATION must be a positive integer." >&2
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

for command_name in curl ffmpeg ffprobe shasum swift tar; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name" >&2
    exit 2
  fi
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macstream-rtmp-integration.XXXXXX")"
SERVER_LOG="$WORK_DIR/mediamtx.log"
PUBLISH_LOG="$WORK_DIR/publisher.log"
INGEST_LOG="$WORK_DIR/ffmpeg-reader.log"
CAPTURE_PATH="$WORK_DIR/ingest.flv"
CONNECTION_URL="rtmp://127.0.0.1:$PORT/live"
PUBLISH_URL="$CONNECTION_URL/$STREAM_NAME"
SERVER_PID=""
PUBLISH_PID=""

cleanup() {
  for process_id in "$PUBLISH_PID" "$SERVER_PID"; do
    if [[ -n "$process_id" ]] && kill -0 "$process_id" 2>/dev/null; then
      kill "$process_id" 2>/dev/null || true
      wait "$process_id" 2>/dev/null || true
    fi
  done
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [[ -z "$MEDIAMTX_BIN" ]]; then
  case "$(uname -m)" in
    arm64)
      mediamtx_arch="arm64"
      mediamtx_sha256="6a9273ae22a9d0ba85d00d03fdd1b13b9eeaf129ea8b90999ec746367f20449a"
      ;;
    x86_64)
      mediamtx_arch="amd64"
      mediamtx_sha256="d0f9b2f67da6bbed0b8e01d6baea07d9e5e9b2b617d6c421fc9b1a98d232bfca"
      ;;
    *)
      echo "Unsupported MediaMTX architecture: $(uname -m)" >&2
      exit 2
      ;;
  esac

  mediamtx_archive="mediamtx_v${MEDIAMTX_VERSION}_darwin_${mediamtx_arch}.tar.gz"
  curl -fsSL \
    "https://github.com/bluenviron/mediamtx/releases/download/v${MEDIAMTX_VERSION}/${mediamtx_archive}" \
    -o "$WORK_DIR/$mediamtx_archive"
  printf '%s  %s\n' "$mediamtx_sha256" "$WORK_DIR/$mediamtx_archive" | shasum -a 256 -c -
  tar -xzf "$WORK_DIR/$mediamtx_archive" -C "$WORK_DIR"
  MEDIAMTX_BIN="$WORK_DIR/mediamtx"
fi

if [[ ! -x "$MEDIAMTX_BIN" ]]; then
  echo "MediaMTX executable is not available: $MEDIAMTX_BIN" >&2
  exit 2
fi

MTX_RTSP=no \
MTX_RTMP=yes \
MTX_RTMPADDRESS=":$PORT" \
MTX_HLS=no \
MTX_WEBRTC=no \
MTX_SRT=no \
MTX_PATHS_ALL_SOURCE=publisher \
"$MEDIAMTX_BIN" >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

for _ in {1..100}; do
  if grep -q "listener opened on :$PORT" "$SERVER_LOG"; then
    break
  fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    cat "$SERVER_LOG" >&2
    echo "Local MediaMTX server failed to start." >&2
    exit 1
  fi
  sleep 0.05
done
if ! grep -q "listener opened on :$PORT" "$SERVER_LOG"; then
  cat "$SERVER_LOG" >&2
  echo "Timed out waiting for the local MediaMTX server." >&2
  exit 1
fi

(
  cd "$ROOT_DIR"
  swift_test_command=(swift test)
  if [[ -n "$SWIFT_SCRATCH_PATH" ]]; then
    swift_test_command+=(--scratch-path "$SWIFT_SCRATCH_PATH")
  fi
  MAC_STREAM_ENABLE_HAISHINKIT=1 \
  MAC_STREAM_RUN_RTMP_INTEGRATION=1 \
  MAC_STREAM_RTMP_INTEGRATION_URL="$CONNECTION_URL" \
  MAC_STREAM_RTMP_INTEGRATION_STREAM_NAME="$STREAM_NAME" \
  MAC_STREAM_RTMP_INTEGRATION_DURATION="$DURATION" \
  MAC_STREAM_RTMP_INTEGRATION_WARMUP_DURATION="$WARMUP_DURATION" \
  MAC_STREAM_RTMP_INTEGRATION_FPS="$FPS" \
  "${swift_test_command[@]}" --filter haishinKitPublisherSendsSyntheticVideoToConfiguredRTMPIngest
) >"$PUBLISH_LOG" 2>&1 &
PUBLISH_PID=$!

for _ in {1..2400}; do
  if grep -q "is publishing to path 'live/$STREAM_NAME'" "$SERVER_LOG"; then
    break
  fi
  if ! kill -0 "$PUBLISH_PID" 2>/dev/null; then
    cat "$PUBLISH_LOG" >&2
    cat "$SERVER_LOG" >&2
    echo "RTMP publisher exited before MediaMTX confirmed the stream." >&2
    exit 1
  fi
  sleep 0.05
done
if ! grep -q "is publishing to path 'live/$STREAM_NAME'" "$SERVER_LOG"; then
  cat "$PUBLISH_LOG" >&2
  cat "$SERVER_LOG" >&2
  echo "Timed out waiting for MediaMTX to confirm the published stream." >&2
  exit 1
fi

INGEST_STATUS=0
ffmpeg \
  -hide_banner \
  -loglevel warning \
  -nostdin \
  -i "$PUBLISH_URL" \
  -c copy \
  -y \
  "$CAPTURE_PATH" >"$INGEST_LOG" 2>&1 || INGEST_STATUS=$?

PUBLISH_STATUS=0
wait "$PUBLISH_PID" || PUBLISH_STATUS=$?
PUBLISH_PID=""

if (( PUBLISH_STATUS != 0 )); then
  cat "$PUBLISH_LOG" >&2
  cat "$SERVER_LOG" >&2
  cat "$INGEST_LOG" >&2
  echo "RTMP publisher integration test failed." >&2
  exit "$PUBLISH_STATUS"
fi

if [[ ! -s "$CAPTURE_PATH" ]]; then
  cat "$PUBLISH_LOG" >&2
  cat "$SERVER_LOG" >&2
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
  cat "$PUBLISH_LOG" >&2
  cat "$SERVER_LOG" >&2
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
