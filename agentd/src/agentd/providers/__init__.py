"""LLM provider abstraction.

`complete()` routes to the configured provider. Ollama is the default and needs
no key; the cloud providers read their key from the Keychain. Every provider
returns plain text and raises ProviderError on failure so callers can fall back
to deterministic behavior when no model is reachable.
"""
from __future__ import annotations

from .base import ProviderError
from . import ollama, openai_compat, gemini


async def complete(provider: str, model: str, prompt: str,
                   system: str = "") -> str:
    provider = (provider or "ollama").lower()
    if provider == "ollama":
        return await ollama.complete(model, prompt, system)
    if provider == "openai":
        return await openai_compat.complete("openai", model, prompt, system)
    if provider == "groq":
        return await openai_compat.complete("groq", model, prompt, system)
    if provider == "gemini":
        return await gemini.complete(model, prompt, system)
    raise ProviderError(f"unknown provider: {provider}")


async def list_ollama_models() -> list[str]:
    return await ollama.list_models()
