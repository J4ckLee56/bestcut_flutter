#!/bin/bash

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <input_wav_path> <output_basename>" >&2
  echo "Outputs <output_basename>.srt, .json, .wts.json" >&2
  exit 1
fi

INPUT_WAV="$1"
OUTPUT_BASE="$2"

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

WHISPER_BIN="${WHISPER_CLI_PATH:-$PROJECT_ROOT/whisper.cpp/build/bin/whisper-cli}"
MODEL_PATH="${WHISPER_MODEL_PATH:-$PROJECT_ROOT/whisper.cpp/models/ggml-large-v3-turbo.bin}"

if [[ ! -x "$WHISPER_BIN" ]]; then
  echo "Error: whisper-cli executable not found at '$WHISPER_BIN'." >&2
  echo "Build whisper.cpp or set WHISPER_CLI_PATH environment variable." >&2
  exit 1
fi

if [[ ! -f "$MODEL_PATH" ]]; then
  echo "Error: Whisper model not found at '$MODEL_PATH'." >&2
  echo "Download ggml-large-v3(-turbo).bin and set WHISPER_MODEL_PATH if needed." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_BASE")"

"$WHISPER_BIN" \
  -m "$MODEL_PATH" \
  -f "$INPUT_WAV" \
  -l ko \
  -osrt \
  -oj \
  -owts \
  -tp 0 \
  -ng \
  --beam-size 5 \
  --best-of 5 \
  --max-len 16 \
  --split-on-word \
  --no-speech-thold 0.3 \
  --word-thold 0.15 \
  --output-file "$OUTPUT_BASE"

echo "whisper-cli outputs saved to ${OUTPUT_BASE}.[srt|json|wts.json]"

