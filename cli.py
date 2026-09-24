#!/usr/bin/env python3
"""Backward-compatible command-line entry point for the Atten backend."""

import argparse
from collections import deque
import json
import os
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import threading
import warnings

from atten_backend.catalog import VOICES
from atten_backend.device import SUPPORTED_DEVICE_MODES, model_status, resolve_device
from atten_backend.service import (
    PAUSE_LENGTHS,
    GenerationRequest,
    GenerationService,
    SoundFileAudioIO,
)
from play import play_audio_file

warnings.filterwarnings("ignore")

SILENT_MODE = False
JSON_MODE = False
# `serve` sends events here instead of stdout, which it hands to stderr.
EVENT_STREAM = None
_request = threading.local()
_emit_lock = threading.Lock()


def emit(event, **payload):
    if JSON_MODE:
        # While serving, every event belongs to the request that caused it.
        request_id = getattr(_request, "id", None)
        tag = {} if request_id is None else {"id": request_id}
        line = json.dumps({"event": event, **tag, **payload})
        with _emit_lock:
            try:
                print(line, file=EVENT_STREAM, flush=True)
            except BrokenPipeError:
                # A serving process whose client has gone is about to see its
                # stdin close and exit; a one-shot run still fails as before.
                if EVENT_STREAM is None:
                    raise


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


class RequestCancelled(Exception):
    """The serving client cancelled the request it is waiting on."""


def process_input(args, service=None, should_stop=None):
    """Load input, generate one file, optionally play it, and return its path."""
    if args.mps:
        args.device = "mps"
        log_info("--mps is deprecated; use --device mps instead.", "ℹ️")

    if args.source:
        text = Path(args.source).read_text(encoding="utf-8")
        log_info(f"Loaded text from: {args.source}", "📄")
    else:
        text = args.text

    service = service or GenerationService(device_mode=args.device, model_id=args.model)
    device_info = getattr(service.provider, "device_info", None)
    if device_info and device_info.warning:
        emit("warning", message=device_info.warning)
    if device_info and device_info.selected_device != "cpu":
        log_info(f"Acceleration enabled: {device_info.selected_device}", "🚀")

    def segment_progress(count):
        if args.segments_dir is None:
            emit("segment", count=count)
        if should_stop and should_stop():
            raise RequestCancelled()

    def segment_ready(payload):
        emit("segment", **payload)

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
                    segments_directory=args.segments_dir,
                    pause=args.pause,
                ),
                progress=segment_progress,
                segment_ready=segment_ready,
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
            segments_directory=args.segments_dir,
            pause=args.pause,
        ),
        progress=segment_progress,
        segment_ready=segment_ready,
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
    parser.add_argument("--mps", action="store_true", help="Deprecated alias for --device mps.")
    parser.add_argument(
        "--device",
        choices=SUPPORTED_DEVICE_MODES,
        default="auto",
        help="Acceleration device: auto, cpu, cuda, or mps.",
    )
    parser.add_argument(
        "--engine",
        choices=["auto", "kokoro", "xtts-v2"],
        default="auto",
        help="Speech synthesis engine: auto, kokoro, or xtts-v2.",
    )
    parser.add_argument(
        "--model",
        help="Hugging Face repository of a downloaded model to synthesize with "
        "(e.g. facebook/mms-tts-ara). Defaults to the bundled Kokoro model.",
    )
    parser.add_argument(
        "--download-model",
        help="Download on-demand model weights from Hugging Face (e.g. xtts-v2, facebook/mms-tts-ara, etc.).",
    )
    parser.add_argument(
        "--format", choices=["mp3", "wav"], default="mp3", help="Output format."
    )
    parser.add_argument(
        "-o", "--output", default="outputs", help="Output directory (default: outputs)."
    )
    parser.add_argument("--segments-dir", type=Path, help="Keep WAV segments and emit word timings.")
    parser.add_argument("--filename", help="Output filename without extension.")
    parser.add_argument(
        "--pause",
        choices=PAUSE_LENGTHS,
        help="Pause after each paragraph: short, normal, or long (default: the voice's own).",
    )
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
    parser.add_argument(
        "--backend-info",
        action="store_true",
        help="Print backend platform, model, and acceleration information.",
    )
    return parser


def backend_info(device_mode="auto"):
    from atten_backend.downloader import is_xtts_installed
    device = resolve_device(device_mode)
    return {
        **device.to_dict(),
        **model_status(),
        "xtts_installed": is_xtts_installed(),
        "voice_count": len(VOICES),
    }


# The generate arguments a `serve` request may carry, named as on the command line.
SERVE_REQUEST_FIELDS = (
    "text", "source", "voice", "speed", "format", "output", "filename",
    "segments_dir", "device", "model", "pause",
)


class RequestServer:
    """Answers NDJSON requests one at a time, keeping every service it builds,
    and so every model it loads, for the life of the process."""

    def __init__(self, service_factory=GenerationService):
        self._service_factory = service_factory
        self._services = {}
        self._queue = deque()
        self._condition = threading.Condition()
        self._current = None
        self._stop = threading.Event()
        self._closed = False

    def read(self, lines):
        """Takes requests from a binary stream until it closes, which also
        stops the request in progress: nobody is left to hear the result."""
        for raw in iter(lines.readline, b""):
            self._receive(raw)
        with self._condition:
            self._closed = True
            self._queue.clear()
            self._stop.set()
            self._condition.notify_all()

    def _receive(self, raw):
        if not raw.strip():
            return
        try:
            request = json.loads(raw)
            if not isinstance(request, dict):
                raise ValueError
        except ValueError:
            emit("error", id=None, message="Unreadable request: send one JSON object per line.")
            return
        request_id, op = request.get("id"), request.get("op")
        if op == "ping":
            emit("pong", id=request_id)
        elif op == "generate":
            with self._condition:
                self._queue.append(request)
                self._condition.notify_all()
        elif op == "cancel":
            with self._condition:
                if request_id is not None and request_id == self._current:
                    self._stop.set()
                    return
                waiting = next((r for r in self._queue if r.get("id") == request_id), None)
                if waiting is not None:
                    self._queue.remove(waiting)
            if waiting is not None:
                emit("cancelled", id=request_id)
        else:
            emit("error", id=request_id, message=f"Unknown request op: {op!r}")

    def run(self):
        while True:
            with self._condition:
                while not self._queue and not self._closed:
                    self._condition.wait()
                if not self._queue:
                    return
                request = self._queue.popleft()
                self._current = request.get("id")
                self._stop = threading.Event()
            try:
                self._perform(request)
            finally:
                with self._condition:
                    self._current = None

    def _perform(self, request):
        _request.id = request.get("id")
        try:
            args = build_parser().parse_args([])
            for field in SERVE_REQUEST_FIELDS:
                if request.get(field) is not None:
                    setattr(args, field, request[field])
            if args.segments_dir is not None:
                args.segments_dir = Path(args.segments_dir)
            if not args.text and not args.source:
                raise ValueError("Please provide either raw text or a source file path.")
            key = (args.device, args.model)
            if key not in self._services:
                self._services[key] = self._service_factory(
                    device_mode=args.device, model_id=args.model
                )
            with warnings.catch_warnings():
                process_input(args, self._services[key], should_stop=self._stop.is_set)
        except RequestCancelled:
            emit("cancelled")
        except Exception as error:
            log_error(str(error))
        finally:
            _request.id = None


def serve():
    global JSON_MODE, EVENT_STREAM
    # Events keep the real stdout; anything else printed to it, by Python or by
    # a native library, lands on stderr instead of corrupting the stream.
    EVENT_STREAM = os.fdopen(os.dup(sys.stdout.fileno()), "w", buffering=1)
    sys.stdout.flush()
    os.dup2(sys.stderr.fileno(), sys.stdout.fileno())
    JSON_MODE = True
    server = RequestServer()
    emit("ready")
    threading.Thread(target=server.read, args=(sys.stdin.buffer,), daemon=True).start()
    server.run()
    return 0


def main(argv=None):
    global SILENT_MODE, JSON_MODE
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv and argv[0] == "serve":
        argparse.ArgumentParser(
            description="Serve newline-delimited JSON generation requests on stdin."
        ).parse_args(argv[1:])
        return serve()
    if argv and argv[0] == "transcode":
        parser = argparse.ArgumentParser(description="Transcode local audio to MP3 or WAV.")
        parser.add_argument("--input", required=True, type=Path)
        parser.add_argument("--output", required=True, type=Path)
        parser.add_argument("--json", action="store_true")
        args = parser.parse_args(argv[1:])
        SILENT_MODE, JSON_MODE = False, args.json
        try:
            path = SoundFileAudioIO().transcode(args.input, args.output)
            emit("completed", path=str(path))
            return 0
        except Exception as error:
            log_error(str(error))
            return 1
    args = build_parser().parse_args(argv)
    SILENT_MODE = args.silent
    JSON_MODE = args.json

    if args.download_model:
        from atten_backend.downloader import download_hf_model
        log_info(f"Starting download for {args.download_model}...", "⬇️")

        def download_progress(payload):
            if JSON_MODE:
                emit("download_progress", **payload)
            elif not SILENT_MODE:
                print(f"⏳ {payload.get('status', '')} [{payload.get('percent', 0)}%]")

        try:
            download_hf_model(args.download_model, download_progress)
            log_success(f"Model {args.download_model} downloaded successfully!", "🎉")
            emit("download_completed", model=args.download_model)
            return 0
        except Exception as error:
            log_error(f"Download failed: {error}")
            return 1

    if args.list_voices:
        if args.json:
            emit("voices", voices=VOICES)
        else:
            for voice in VOICES:
                print(f"{voice['id']}\t{voice['name']}\t{voice['language']}")
        return 0

    if args.backend_info:
        try:
            info = backend_info(args.device)
        except (RuntimeError, ValueError) as error:
            log_error(str(error))
            return 1
        if args.json:
            emit("backend_info", **info)
        else:
            print(f"Platform: {info['platform']}")
            print(f"Python: {info['python_version']}")
            print(f"PyTorch: {info['torch_version'] or 'unavailable'}")
            print(f"Device: {info['selected_device']} (requested {info['requested_device']})")
            print(f"CUDA available: {info['cuda_available']}")
            print(f"MPS available: {info['mps_available']}")
            print(f"Model root valid: {info['model_root_valid']}")
            print(f"XTTS-v2 installed: {info.get('xtts_installed', False)}")
            print(f"Voices: {info['voice_count']}")
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
    except Exception as error:
        log_error(str(error))
        return 1


if __name__ == "__main__":
    sys.exit(main())
