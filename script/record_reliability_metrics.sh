#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./script/record_reliability_metrics.sh --pid PID [options]

Options:
  --duration SECONDS   Total sampling duration. Default: 3600
  --interval SECONDS   Delay between samples. Default: 5
  --output PATH        CSV output path. Default: benchmarks/<date>-<host>-<pid>.csv
  --help               Show this help.
EOF
}

pid=""
duration=3600
interval=5
output=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pid)
      pid="${2:-}"
      shift 2
      ;;
    --duration)
      duration="${2:-}"
      shift 2
      ;;
    --interval)
      interval="${2:-}"
      shift 2
      ;;
    --output)
      output="${2:-}"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! "$pid" =~ ^[1-9][0-9]*$ ]]; then
  echo "--pid must be a positive process ID." >&2
  exit 2
fi
if [[ ! "$duration" =~ ^[1-9][0-9]*$ ]]; then
  echo "--duration must be a positive number of seconds." >&2
  exit 2
fi
if [[ ! "$interval" =~ ^[1-9][0-9]*$ ]]; then
  echo "--interval must be a positive number of seconds." >&2
  exit 2
fi
if ! kill -0 "$pid" 2>/dev/null; then
  echo "Process $pid is not running." >&2
  exit 2
fi

if [[ -z "$output" ]]; then
  host_name="$(hostname -s | tr -cs '[:alnum:]._' '-')"
  output="benchmarks/$(date +%Y-%m-%d)-${host_name}-${pid}.csv"
fi

mkdir -p "$(dirname "$output")"
printf 'timestamp_utc,elapsed_seconds,cpu_percent,rss_kb,threads,process_elapsed\n' >"$output"

started_at="$(date +%s)"
deadline=$((started_at + duration))

while true; do
  now="$(date +%s)"
  elapsed_seconds=$((now - started_at))

  if ! kill -0 "$pid" 2>/dev/null; then
    echo "Process $pid exited after ${elapsed_seconds}s; partial metrics remain at $output." >&2
    exit 3
  fi

  sample="$(ps -p "$pid" -o %cpu=,rss=,etime= | awk 'NF { print $1, $2, $3; exit }')"
  if [[ -z "$sample" ]]; then
    echo "Unable to sample process $pid." >&2
    exit 3
  fi

  read -r cpu_percent rss_kb process_elapsed <<<"$sample"
  threads="$(ps -M "$pid" | awk 'NR > 1 { count += 1 } END { print count + 0 }')"
  timestamp_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s,%s,%s,%s,%s,%s\n' \
    "$timestamp_utc" \
    "$elapsed_seconds" \
    "$cpu_percent" \
    "$rss_kb" \
    "$threads" \
    "$process_elapsed" >>"$output"

  if (( now >= deadline )); then
    break
  fi
  remaining_seconds=$((deadline - now))
  sleep_seconds="$interval"
  if (( remaining_seconds < interval )); then
    sleep_seconds="$remaining_seconds"
  fi
  sleep "$sleep_seconds"
done

echo "Reliability metrics written to $output"
