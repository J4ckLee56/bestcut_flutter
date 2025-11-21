#!/bin/bash

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <input_audio_or_video_path> <output_wav_path>" >&2
  exit 1
fi

INPUT_PATH="$1"
OUTPUT_PATH="$2"

# Allow overriding via env. Otherwise fall back to bundled FFmpeg.
if [[ -n "${FFMPEG_PATH:-}" ]]; then
  FFMPEG_BIN="$FFMPEG_PATH"
else
  PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    FFMPEG_BIN="$PROJECT_ROOT/ffmpeg/macos/ffmpeg"
  elif [[ "$(uname -s)" == "Linux" ]]; then
    FFMPEG_BIN="${PROJECT_ROOT}/ffmpeg/linux/ffmpeg"
  else
    FFMPEG_BIN="ffmpeg"
  fi
fi

if [[ ! -x "$FFMPEG_BIN" ]]; then
  echo "Error: FFmpeg executable not found at '$FFMPEG_BIN'." >&2
  echo "Set FFMPEG_PATH environment variable or ensure bundled FFmpeg exists." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

"$FFMPEG_BIN" \
  -hide_banner \
  -y \
  -i "$INPUT_PATH" \
  -ac 1 \
  -ar 16000 \
  -af "highpass=f=200,lowpass=f=3000,afftdn=nf=-25,loudnorm" \
  "$OUTPUT_PATH"

echo "Preprocessed audio saved to $OUTPUT_PATH"






