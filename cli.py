#!/usr/bin/env python3
"""Backward-compatible command-line entry point for the Atten backend."""

import argparse
import json
import os
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import warnings

from atten_backend.catalog import VOICES
from atten_backend.service import GenerationRequest, GenerationService
from play import play_audio_file

warnings.filterwarnings("ignore")

SILENT_MODE = False
JSON_MODE = False


def emit(event, **payload):
    if JSON_MODE:
        print(json.dumps({"event": event, **payload}), flush=True)


def log_info(message, emoji="ℹ️"):
    if JSON_MODE:
        emit("info", message=message)
    elif not SILENT_MODE:
        print(f"{emoji} {message}")


def log_success(message, emoji="✅"):
    if JSON_MODE:
        emit("success", message=message)
    elif not SILENT_MODE:
        print(f"{emoji} {message}")


def log_error(message, emoji="❌"):
    if JSON_MODE:
        emit("error", message=message)
    else:
        print(f"{emoji} {message}", file=sys.stderr)


def log_progress(message, emoji="⏳"):
    if JSON_MODE:
        emit("progress", message=message)
    elif not SILENT_MODE:
        print(f"{emoji} {message}")


def process_input(args, service=None):
    """Load input, generate one file, optionally play it, and return its path."""
    if args.mps:
        os.environ["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"
        log_info("GPU acceleration (MPS) enabled", "🚀")

    if args.source:
        text = Path(args.source).read_text(encoding="utf-8")
        log_info(f"Loaded text from: {args.source}", "📄")
    else:
        text = args.text

    service = service or GenerationService()

    def segment_progress(count):
        emit("segment", count=count)

    if args.play_only:
        with TemporaryDirectory(prefix="atten-preview-") as output_directory:
            log_progress("Generating audio preview...", "🎵")
            result = service.generate(
                GenerationRequest(
                    text=text,
                    voice=args.voice,
                    speed=args.speed,
                    output_format=args.format,
                    output_directory=Path(output_directory),
                    filename="preview",
                ),
                progress=segment_progress,
            )
            log_progress("Playing audio preview...", "🔊")
            if not play_audio_file(str(result.output_path), args.silent):
                raise RuntimeError("Audio preview could not be played.")
            log_success("Preview completed successfully!", "🎉")
            emit("completed", path=str(result.output_path), preview=True)
            return result.output_path

    log_progress("Generating audio...", "🎵")
    result = service.generate(
        GenerationRequest(
            text=text,
            voice=args.voice,
            speed=args.speed,
            output_format=args.format,
            output_directory=Path(args.output),
            filename=args.filename,
        ),
        progress=segment_progress,
    )
    log_success(f"Audio saved: {result.output_path.name}", "💾")

    if args.play:
        log_progress("Playing generated audio...", "🔊")
        if not play_audio_file(str(result.output_path), args.silent):
            raise RuntimeError("Generated audio could not be played.")

    log_success("Process completed successfully!", "🎉")
    emit(
        "completed",
        path=str(result.output_path),
        segments=result.segment_count,
        sample_rate=result.sample_rate,
        preview=False,
    )
    return result.output_path


def build_parser():
    parser = argparse.ArgumentParser(
        description="Atten offline text-to-speech command-line tool"
    )
    parser.add_argument("text", nargs="?", help="Raw text to synthesize.")
    parser.add_argument(
        "-f", "--source", help="Path to a UTF-8 source document file."
    )
    parser.add_argument(
        "-s", "--speed", type=float, default=1.0, help="Speech speed (default: 1.0)."
    )
    parser.add_argument(
        "-v", "--voice", default="af_heart", help="Kokoro voice (default: af_heart)."
    )
    parser.add_argument("--mps", action="store_true", help="Enable macOS MPS fallback.")
    parser.add_argument(
        "--format", choices=["mp3", "wav"], default="mp3", help="Output format."
    )
    parser.add_argument(
        "-o", "--output", default="outputs", help="Output directory (default: outputs)."
    )
    parser.add_argument("--filename", help="Output filename without extension.")
    parser.add_argument("--play", action="store_true", help="Play after generation.")
    parser.add_argument(
        "--play-only", action="store_true", help="Generate and play without saving."
    )
    parser.add_argument(
        "--silent", action="store_true", help="Suppress output except errors."
    )
    parser.add_argument(
        "--json", action="store_true", help="Emit newline-delimited JSON events."
    )
    parser.add_argument(
        "--list-voices", action="store_true", help="Print the supported voice catalog."
    )
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    global SILENT_MODE, JSON_MODE
    SILENT_MODE = args.silent
    JSON_MODE = args.json

    if args.list_voices:
        if args.json:
            emit("voices", voices=VOICES)
        else:
            for voice in VOICES:
                print(f"{voice['id']}\t{voice['name']}\t{voice['language']}")
        return 0

    if not args.text and not args.source:
        log_error("Please provide either raw text or a source file path.")
        if not args.silent and not args.json:
            build_parser().print_help()
        return 2

    try:
        with warnings.catch_warnings():
            process_input(args)
        return 0
    except (OSError, RuntimeError, ValueError) as error:
        log_error(str(error))
        return 1


if __name__ == "__main__":
    sys.exit(main())
