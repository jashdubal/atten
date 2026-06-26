"""Platform-aware PyTorch device selection for the Kokoro backend."""

from dataclasses import asdict, dataclass
from pathlib import Path
import os
import platform
import sys


SUPPORTED_DEVICE_MODES = ("auto", "cpu", "cuda", "mps")


@dataclass(frozen=True)
class DeviceInfo:
    requested_device: str
    selected_device: str
    platform: str
    python_version: str
    torch_version: str | None
    cuda_available: bool
    cuda_version: str | None
    mps_available: bool
    warning: str | None = None

    def to_dict(self):
        return asdict(self)


def _torch_info():
    try:
        import torch
    except Exception:
        return None
    return torch


def _mps_available(torch):
    backend = getattr(getattr(torch, "backends", None), "mps", None)
    return bool(backend and backend.is_available())


def _cuda_available(torch):
    cuda = getattr(torch, "cuda", None)
    return bool(cuda and cuda.is_available())


def resolve_device(mode="auto") -> DeviceInfo:
    requested = (mode or "auto").lower()
    if requested not in SUPPORTED_DEVICE_MODES:
        raise ValueError(
            "Device must be one of: " + ", ".join(SUPPORTED_DEVICE_MODES)
        )

    torch = _torch_info()
    if torch is None:
        if requested in {"cuda", "mps"}:
            raise RuntimeError(f"PyTorch is not available; cannot use {requested}.")
        return DeviceInfo(
            requested_device=requested,
            selected_device="cpu",
            platform=sys.platform,
            python_version=platform.python_version(),
            torch_version=None,
            cuda_available=False,
            cuda_version=None,
            mps_available=False,
            warning="PyTorch is unavailable; using CPU.",
        )

    cuda_available = _cuda_available(torch)
    mps_available = _mps_available(torch)
    cuda_version = getattr(getattr(torch, "version", None), "cuda", None)

    if requested == "cpu":
        selected = "cpu"
        warning = None
    elif requested == "cuda":
        if not cuda_available:
            raise RuntimeError("CUDA was requested, but PyTorch cannot use CUDA.")
        selected = "cuda"
        warning = None
    elif requested == "mps":
        if not mps_available:
            raise RuntimeError("MPS was requested, but PyTorch cannot use MPS.")
        selected = "mps"
        warning = None
    elif sys.platform == "darwin" and mps_available:
        selected = "mps"
        warning = None
    elif sys.platform != "darwin" and cuda_available:
        selected = "cuda"
        warning = None
    else:
        selected = "cpu"
        warning = None

    if selected == "mps":
        os.environ["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"

    return DeviceInfo(
        requested_device=requested,
        selected_device=selected,
        platform=sys.platform,
        python_version=platform.python_version(),
        torch_version=getattr(torch, "__version__", None),
        cuda_available=cuda_available,
        cuda_version=cuda_version,
        mps_available=mps_available,
        warning=warning,
    )


def model_status(model_root=None):
    configured_root = model_root or os.environ.get("ATTEN_MODEL_ROOT")
    if not configured_root:
        return {
            "model_root": None,
            "model_root_valid": False,
            "missing_model_files": [],
        }

    root = Path(configured_root).expanduser().resolve()
    required = [
        root / "config.json",
        root / "kokoro-v1_0.pth",
        root / "voices",
    ]
    missing = [str(path) for path in required if not path.exists()]
    return {
        "model_root": str(root),
        "model_root_valid": not missing,
        "missing_model_files": missing,
    }
