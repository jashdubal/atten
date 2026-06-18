"""Local Kokoro backend used by the Atten CLI and macOS application."""

from .service import GenerationRequest, GenerationResult, GenerationService

__all__ = ["GenerationRequest", "GenerationResult", "GenerationService"]
