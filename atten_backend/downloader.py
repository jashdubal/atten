"""On-demand model downloading with resume, live speed, ETA, and metrics."""

import os
from pathlib import Path
import sys
import time
from typing import Callable, Dict, List, Optional
import urllib.request
import json

XTTS_V2_REPO = "coqui/XTTS-v2"
XTTS_V2_FILES = [
    ("config.json", "https://huggingface.co/coqui/XTTS-v2/raw/main/config.json", 3_000),
    ("vocab.json", "https://huggingface.co/coqui/XTTS-v2/raw/main/vocab.json", 160_000),
    ("speakers_xtts.pth", "https://huggingface.co/coqui/XTTS-v2/resolve/main/speakers_xtts.pth", 250_000),
    ("model.pth", "https://huggingface.co/coqui/XTTS-v2/resolve/main/model.pth", 1_870_000_000),
]


def format_bytes(size: float) -> str:
    """Formats bytes to a human-readable string (KB, MB, GB)."""
    if size >= 1024 * 1024 * 1024:
        return f"{size / (1024 * 1024 * 1024):.2f} GB"
    elif size >= 1024 * 1024:
        return f"{size / (1024 * 1024):.1f} MB"
    elif size >= 1024:
        return f"{size / 1024:.0f} KB"
    return f"{size:.0f} B"


def format_time(seconds: float) -> str:
    """Formats seconds into readable remaining time."""
    if seconds <= 0 or seconds > 86400:
        return "--"
    mins, secs = divmod(int(seconds), 60)
    hours, mins = divmod(mins, 60)
    if hours > 0:
        return f"{hours}h {mins}m"
    if mins > 0:
        return f"{mins}m {secs}s"
    return f"{secs}s"


def get_models_directory() -> Path:
    """Returns user-writable models directory in local app data or environment override."""
    env_root = os.environ.get("ATTEN_MODELS_DIR")
    if env_root:
        path = Path(env_root)
    elif sys.platform == "win32":
        local_app_data = os.environ.get("LOCALAPPDATA") or Path.home() / "AppData" / "Local"
        path = Path(local_app_data) / "Atten" / "Models"
    else:
        path = Path.home() / ".local" / "share" / "atten" / "models"
    path.mkdir(parents=True, exist_ok=True)
    return path


def is_xtts_installed() -> bool:
    """Checks whether the XTTS-v2 model files are present and valid."""
    xtts_dir = get_models_directory() / "XTTS-v2"
    if not xtts_dir.is_dir():
        return False
    required = ["config.json", "vocab.json", "model.pth"]
    for filename in required:
        file_path = xtts_dir / filename
        if not file_path.is_file() or file_path.stat().st_size == 0:
            return False
    return True


def is_model_installed(model_id: str) -> bool:
    """Whether a Hugging Face model has already been downloaded in full.

    Atten never reaches the network to synthesize, so this is what decides
    between speaking and explaining which model is missing.
    """
    if model_id.strip().lower() in ("xtts-v2", "coqui/xtts-v2"):
        return is_xtts_installed()

    directory = get_models_directory() / model_id.strip().replace("/", "--")
    if not directory.is_dir():
        return False
    if (directory / ".atten_complete").is_file():
        return True
    if any(directory.glob("*.part")) or any(directory.glob(".*.part")):
        return False
    weights = (".bin", ".pt", ".pth", ".safetensors", ".onnx", ".gguf")
    return any(
        path.is_file() and path.stat().st_size > 1024 * 1024 and path.suffix in weights
        for path in directory.iterdir()
    )


def download_xtts_model(progress_callback: Optional[Callable[[dict], None]] = None) -> Path:
    """Downloads XTTS-v2 weights with resumable downloads, live speed, ETA, and progress."""
    xtts_dir = get_models_directory() / "XTTS-v2"
    xtts_dir.mkdir(parents=True, exist_ok=True)

    # Calculate total expected size
    total_model_bytes = sum(expected for _, _, expected in XTTS_V2_FILES)
    total_files = len(XTTS_V2_FILES)

    for idx, (filename, url, expected_size) in enumerate(XTTS_V2_FILES):
        target = xtts_dir / filename
        if target.is_file() and target.stat().st_size > 0:
            if progress_callback:
                progress_callback({
                    "model": "xtts-v2",
                    "file": filename,
                    "file_index": idx + 1,
                    "total_files": total_files,
                    "percent": int(((idx + 1) / total_files) * 100),
                    "status": f"Verified {filename}",
                    "speed": "0 MB/s",
                    "eta": "",
                    "size_text": f"{format_bytes(target.stat().st_size)} / {format_bytes(expected_size)}",
                })
            continue

        temp_target = xtts_dir / f".{filename}.part"
        existing_bytes = temp_target.stat().st_size if temp_target.exists() else 0

        headers = {"User-Agent": "Atten/0.4.0"}
        if existing_bytes > 0:
            headers["Range"] = f"bytes={existing_bytes}-"

        req = urllib.request.Request(url, headers=headers)
        
        try:
            response = urllib.request.urlopen(req)
        except urllib.error.HTTPError as e:
            # If 416 Range Not Satisfiable, restart file
            if e.code == 416:
                existing_bytes = 0
                headers.pop("Range", None)
                req = urllib.request.Request(url, headers=headers)
                response = urllib.request.urlopen(req)
            else:
                raise

        content_length = response.headers.get("content-length")
        if response.status == 206:
            # Partial content
            file_total = existing_bytes + (int(content_length) if content_length else expected_size)
            mode = "ab"
        else:
            file_total = int(content_length) if content_length else expected_size
            existing_bytes = 0
            mode = "wb"

        downloaded_in_file = existing_bytes
        chunk_size = 1024 * 512  # 512 KB chunks

        # Speed and ETA tracking
        start_time = time.time()
        session_downloaded = 0
        last_update_time = start_time
        speed_bps = 0.0

        with open(temp_target, mode) as out_file:
            while True:
                chunk = response.read(chunk_size)
                if not chunk:
                    break
                out_file.write(chunk)
                downloaded_in_file += len(chunk)
                session_downloaded += len(chunk)

                now = time.time()
                elapsed = now - last_update_time
                if elapsed >= 0.25:  # Update progress 4 times per second
                    total_elapsed = now - start_time
                    if total_elapsed > 0:
                        speed_bps = session_downloaded / total_elapsed

                    remaining_bytes = max(0, file_total - downloaded_in_file)
                    eta_seconds = (remaining_bytes / speed_bps) if speed_bps > 0 else 0

                    file_fraction = downloaded_in_file / file_total if file_total > 0 else 0
                    overall_percent = int(((idx + file_fraction) / total_files) * 100)

                    if progress_callback:
                        progress_callback({
                            "model": "xtts-v2",
                            "file": filename,
                            "file_index": idx + 1,
                            "total_files": total_files,
                            "downloaded_bytes": downloaded_in_file,
                            "total_bytes": file_total,
                            "percent": overall_percent,
                            "speed": f"{format_bytes(speed_bps)}/s",
                            "eta": format_time(eta_seconds),
                            "size_text": f"{format_bytes(downloaded_in_file)} / {format_bytes(file_total)}",
                            "status": f"Downloading {filename} ({idx + 1}/{total_files})",
                        })
                    last_update_time = now

        response.close()

        if temp_target.exists():
            if target.exists():
                target.unlink()
            temp_target.rename(target)

    try:
        (xtts_dir / ".atten_complete").write_text("complete\n")
    except Exception:
        pass

    if progress_callback:
        progress_callback({
            "model": "xtts-v2",
            "percent": 100,
            "speed": "",
            "eta": "",
            "size_text": f"{format_bytes(total_model_bytes)}",
            "status": "XTTS-v2 model download complete!",
            "installed": True,
        })

    return xtts_dir


def get_hf_repo_files(clean_id: str) -> List[tuple]:
    """Retrieves and filters repository files to only essential model weights and configs."""
    all_files = []
    
    # Try tree endpoint first (has accurate file sizes and all files recursively)
    try:
        tree_url = f"https://huggingface.co/api/models/{clean_id}/tree/main?recursive=true"
        req = urllib.request.Request(tree_url, headers={"User-Agent": "Atten/0.4.0"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            all_files = [(item["path"], int(item.get("size", 0))) for item in data if item.get("type") == "file"]
    except Exception:
        pass

    # Fallback to model info endpoint
    if not all_files:
        try:
            info_url = f"https://huggingface.co/api/models/{clean_id}"
            req = urllib.request.Request(info_url, headers={"User-Agent": "Atten/0.4.0"})
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                all_files = [(s.get("rfilename", ""), 0) for s in data.get("siblings", [])]
        except Exception:
            pass

    if not all_files:
        return []

    # Smart filtering
    ignored_exts = ('.png', '.jpg', '.jpeg', '.gif', '.mp4', '.wav', '.flac', '.mp3', '.gitattributes', '.gitignore')
    safetensor_stems = {fname[:-len('.safetensors')] for fname, _ in all_files if fname.lower().endswith('.safetensors')}
    
    gguf_files = []
    filtered = []

    for fname, size in all_files:
        lower = fname.lower()
        if any(lower.endswith(ext) for ext in ignored_exts) or 'assets/' in lower or 'demo/' in lower or 'examples/' in lower:
            continue
            
        if lower.endswith('.gguf'):
            gguf_files.append((fname, size))
            continue
            
        # If it's a pytorch/bin file and a safetensor version exists, skip it
        if lower.endswith('.pt') or lower.endswith('.bin') or lower.endswith('.pth') or lower.endswith('.ckpt'):
            stem = fname.rsplit('.', 1)[0]
            if stem in safetensor_stems:
                continue
                
        filtered.append((fname, size))

    # For GGUF repos: select optimal quantization (Q4_K_M > Q8_0 > BF16 > F16 > others) for each model part
    if gguf_files:
        import re
        quant_pattern = re.compile(r'[-_](q[0-9]_[a-z0-9_]+|bf16|f16|f32|q8_0|q4_k_m|q5_k_m)\.gguf$', re.I)
        groups = {}
        for fname, size in gguf_files:
            match = quant_pattern.search(fname)
            if match:
                base = fname[:match.start()]
                groups.setdefault(base, []).append((fname, size, match.group(1).upper()))
            else:
                groups.setdefault(fname, []).append((fname, size, 'RAW'))
                
        pref_order = ['Q4_K_M', 'Q8_0', 'BF16', 'Q5_K_M', 'Q6_K', 'F16', 'F32']
        for base, items in groups.items():
            chosen = None
            for p in pref_order:
                for f, s, q in items:
                    if q == p:
                        chosen = (f, s)
                        break
                if chosen:
                    break
            if not chosen:
                chosen = (items[0][0], items[0][1])
            filtered.append(chosen)

    return filtered


def download_hf_model(model_id: str, progress_callback: Optional[Callable[[dict], None]] = None) -> Path:
    """Downloads any model from Hugging Face with live progress metrics and resumable chunk streams."""
    clean_id = model_id.strip()
    if clean_id.lower() in ("xtts-v2", "coqui/xtts-v2"):
        return download_xtts_model(progress_callback)

    models_dir = get_models_directory()
    dest_dir = models_dir / clean_id.replace('/', '--')
    dest_dir.mkdir(parents=True, exist_ok=True)

    if progress_callback:
        progress_callback({
            "model": clean_id,
            "percent": 0,
            "status": f"Fetching repository file manifest for {clean_id}...",
            "speed": "",
            "eta": "",
            "size_text": "",
        })

    files = get_hf_repo_files(clean_id)
    total_repo_bytes = sum(size for _, size in files)
    total_files = len(files)

    if total_files == 0:
        raise ValueError(f"No files found for Hugging Face repository {clean_id}")

    total_downloaded = 0
    start_time = time.time()
    last_update_time = start_time
    session_downloaded = 0
    # A file that could not be fetched must not be forgotten: a model that is
    # missing a piece has to look unfinished, or the app will offer a voice
    # that cannot speak and fail on it later with an opaque error.
    failed_files = []

    for idx, (filename, file_size) in enumerate(files):
        target = dest_dir / filename
        target.parent.mkdir(parents=True, exist_ok=True)
        
        if target.is_file() and target.stat().st_size > 0:
            total_downloaded += target.stat().st_size
            continue

        url = f"https://huggingface.co/{clean_id}/resolve/main/{filename}"
        temp_target = dest_dir / f".{filename.replace('/', '_')}.part"
        existing_bytes = temp_target.stat().st_size if temp_target.exists() else 0

        headers = {"User-Agent": "Atten/0.4.0"}
        if existing_bytes > 0:
            headers["Range"] = f"bytes={existing_bytes}-"

        req = urllib.request.Request(url, headers=headers)
        try:
            response = urllib.request.urlopen(req)
        except urllib.error.HTTPError as e:
            if e.code == 416:
                existing_bytes = 0
                headers.pop("Range", None)
                req = urllib.request.Request(url, headers=headers)
                response = urllib.request.urlopen(req)
            else:
                failed_files.append(filename)
                continue
        except Exception:
            failed_files.append(filename)
            continue

        content_length = response.headers.get("content-length")
        if response.status == 206:
            file_total = existing_bytes + (int(content_length) if content_length else file_size)
            mode = "ab"
        else:
            file_total = int(content_length) if content_length else file_size
            existing_bytes = 0
            mode = "wb"

        downloaded_in_file = existing_bytes
        total_downloaded += existing_bytes
        chunk_size = 1024 * 512

        with open(temp_target, mode) as out_file:
            while True:
                chunk = response.read(chunk_size)
                if not chunk:
                    break
                out_file.write(chunk)
                downloaded_in_file += len(chunk)
                total_downloaded += len(chunk)
                session_downloaded += len(chunk)

                now = time.time()
                elapsed = now - last_update_time
                if elapsed >= 0.25:
                    total_elapsed = now - start_time
                    speed_bps = (session_downloaded / total_elapsed) if total_elapsed > 0 else 0
                    
                    if total_repo_bytes > 0:
                        overall_percent = int((total_downloaded / total_repo_bytes) * 100)
                        remaining_bytes = max(0, total_repo_bytes - total_downloaded)
                        size_text = f"{format_bytes(total_downloaded)} / {format_bytes(total_repo_bytes)}"
                    else:
                        file_fraction = (downloaded_in_file / file_total) if file_total > 0 else 0
                        overall_percent = int(((idx + file_fraction) / total_files) * 100)
                        remaining_bytes = max(0, file_total - downloaded_in_file)
                        size_text = f"{format_bytes(downloaded_in_file)} / {format_bytes(file_total)}"

                    eta_seconds = (remaining_bytes / speed_bps) if speed_bps > 0 else 0

                    if progress_callback:
                        progress_callback({
                            "model": clean_id,
                            "file": filename,
                            "file_index": idx + 1,
                            "total_files": total_files,
                            "percent": min(99, overall_percent),
                            "speed": f"{speed_bps / (1024 * 1024):.1f} MB/s",
                            "eta": format_time(eta_seconds),
                            "size_text": size_text,
                            "status": f"Downloading {filename} ({idx + 1}/{total_files})",
                        })
                    last_update_time = now

        response.close()
        if temp_target.exists():
            if target.exists():
                target.unlink()
            temp_target.rename(target)

    if failed_files:
        raise RuntimeError(
            f"{clean_id} did not download completely; {len(failed_files)} file(s) "
            f"could not be fetched, starting with {failed_files[0]}. Try the "
            "download again — the parts already on disk are kept and resumed."
        )

    # Write completion marker
    try:
        (dest_dir / ".atten_complete").write_text("complete\n")
    except Exception:
        pass

    if progress_callback:
        progress_callback({
            "model": clean_id,
            "percent": 100,
            "speed": "",
            "eta": "",
            "size_text": format_bytes(total_downloaded) if total_downloaded > 0 else "",
            "status": f"{clean_id} downloaded successfully!",
            "installed": True,
        })

    return dest_dir
