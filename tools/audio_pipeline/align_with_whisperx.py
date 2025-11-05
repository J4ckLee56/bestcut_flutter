#!/usr/bin/env python3

"""Align Whisper segments with WhisperX forced alignment.

Usage:
    python align_with_whisperx.py \
        --audio cleaned.wav \
        --whisper-json output.json \
        --language ko \
        --device auto \
        --output-json aligned.json \
        --output-vtt aligned.vtt

The script expects Whisper JSON output generated with --output-json and
--output-wts flags so that segment timing and token data are present.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any, Dict

import torch
import whisperx

try:
    from whisperx.utils import write_vtt as whisperx_write_vtt  # type: ignore
except ImportError:  # WhisperX versions without write_vtt helper
    whisperx_write_vtt = None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Align Whisper segments with WhisperX")
    parser.add_argument("--audio", required=True, help="Path to preprocessed WAV audio")
    parser.add_argument("--whisper-json", required=True, help="Path to whisper-cli JSON output")
    parser.add_argument("--language", default="ko", help="ISO language code (default: ko)")
    parser.add_argument(
        "--device",
        default="auto",
        choices=["auto", "cuda", "cpu"],
        help="Device selection for WhisperX alignment",
    )
    parser.add_argument("--output-json", required=True, help="Path to write aligned JSON data")
    parser.add_argument("--output-vtt", help="Optional path to write aligned VTT file")
    parser.add_argument(
        "--model-cache",
        help="Optional directory for WhisperX model cache (XDG_CACHE_HOME override)",
    )
    parser.add_argument(
        "--align-model",
        default="kresnik/wav2vec2-large-xlsr-korean",
        help="WhisperX alignment model identifier (default: kresnik/wav2vec2-large-xlsr-korean)",
    )
    return parser.parse_args()


def resolve_device(choice: str) -> str:
    if choice == "cuda":
        if torch.cuda.is_available():
            return "cuda"
        raise RuntimeError("CUDA requested but not available")
    if choice == "cpu":
        return "cpu"
    return "cuda" if torch.cuda.is_available() else "cpu"


def load_whisper_segments(path: str) -> Dict[str, Any]:
    with open(path, "r", encoding="utf-8") as fp:
        data = json.load(fp)

    segments = data.get("segments")
    if not segments:
        # whisper.cpp uses 'transcription' as top-level list
        segments = data.get("transcription")
        if segments:
            data["segments"] = segments

    if not segments:
        raise ValueError("Whisper JSON missing 'segments' or 'transcription' array")

    for segment in segments:
        if "start" not in segment or "end" not in segment:
            start = _extract_timestamp(segment, "from")
            end = _extract_timestamp(segment, "to")
            if start is None or end is None:
                raise ValueError("Segment missing start/end timestamps")
            segment["start"] = start
            segment["end"] = end

    # Ensure language field exists for WhisperX compatibility
    if "language" not in data:
        data["language"] = data.get("detected_language", "unknown")

    return data


def _extract_timestamp(segment: Dict[str, Any], key: str) -> float | None:
    timestamps = segment.get("timestamps") or {}
    value = timestamps.get(key)

    if value is None:
        # fallback to offsets (milliseconds)
        offsets = segment.get("offsets") or {}
        value = offsets.get(key)

    if value is None:
        return None

    if isinstance(value, (int, float)):
        # whisper.cpp uses milliseconds for numeric timestamps
        return float(value) / 1000.0

    if isinstance(value, str):
        # formats like 00:00:03,300
        hms, _, ms = value.partition(",")
        hours, minutes, seconds = hms.split(":")
        total = int(hours) * 3600 + int(minutes) * 60 + float(seconds)
        if ms:
            total += int(ms) / 1000.0
        return total

    return None


def _write_vtt_fallback(segments: list[dict[str, Any]], path: str) -> None:
    def format_ts(seconds: float) -> str:
        ms = int(round(seconds * 1000))
        h = ms // 3600000
        m = (ms % 3600000) // 60000
        s = (ms % 60000) // 1000
        ms = ms % 1000
        return f"{h:02d}:{m:02d}:{s:02d}.{ms:03d}"

    lines = ["WEBVTT", ""]
    for idx, seg in enumerate(segments, start=1):
        start = float(seg["start"])
        end = float(seg["end"])
        text = seg.get("text", "")
        lines.append(str(idx))
        lines.append(f"{format_ts(start)} --> {format_ts(end)}")
        lines.append(text.strip())
        lines.append("")

    with open(path, "w", encoding="utf-8") as fp:
        fp.write("\n".join(lines))


def main() -> None:
    args = parse_args()

    if args.model_cache:
        os.environ["XDG_CACHE_HOME"] = args.model_cache

    if not os.path.exists(args.audio):
        raise FileNotFoundError(f"Audio file not found: {args.audio}")

    whisper_output = load_whisper_segments(args.whisper_json)
    device = resolve_device(args.device)

    print(f"Loading WhisperX alignment model on {device}…")
    load_kwargs = {
        "language_code": args.language,
        "device": device,
    }

    model_identifier = args.align_model
    if args.model_cache:
        local_candidate = os.path.join(args.model_cache, args.align_model)
        if os.path.isdir(local_candidate):
            model_identifier = local_candidate

    align_model = None
    metadata = None
    try:
        # Newer versions support align_model keyword
        load_kwargs["align_model"] = model_identifier
        align_model, metadata = whisperx.load_align_model(**load_kwargs)
    except TypeError:
        # Fall back to older signature (model_name)
        load_kwargs.pop("align_model", None)
        load_kwargs["model_name"] = model_identifier
        align_model, metadata = whisperx.load_align_model(**load_kwargs)

    segments = whisper_output.get("segments", [])
    if not segments:
        raise ValueError("No segments found in Whisper JSON output")

    print(f"Aligning {len(segments)} segments…")
    alignment = whisperx.align(
        segments,
        align_model,
        metadata,
        args.audio,
        device=device,
    )

    alignment["language"] = args.language
    alignment["source"] = {
        "whisper_json": os.path.abspath(args.whisper_json),
        "audio": os.path.abspath(args.audio),
    }

    with open(args.output_json, "w", encoding="utf-8") as fp:
        json.dump(alignment, fp, ensure_ascii=False, indent=2)
    print(f"Aligned JSON written to {args.output_json}")

    if args.output_vtt:
        if whisperx_write_vtt:
            whisperx_write_vtt(alignment["segments"], args.output_vtt)  # type: ignore[arg-type]
        else:
            _write_vtt_fallback(alignment["segments"], args.output_vtt)
        print(f"Aligned VTT written to {args.output_vtt}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # pylint: disable=broad-except
        print(f"Alignment failed: {exc}", file=sys.stderr)
        sys.exit(1)

