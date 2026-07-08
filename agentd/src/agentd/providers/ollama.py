"""Local Ollama provider (default). Talks to http://localhost:11434."""
from __future__ import annotations

import os

import httpx

from .base import ProviderError

BASE = os.environ.get("OLLAMA_HOST", "http://localhost:11434")


async def complete(model: str, prompt: str, system: str = "") -> str:
    payload = {
        "model": model or "llama3.2",
        "prompt": prompt,
        "system": system,
        "stream": False,
        "options": {"temperature": 0.4},
    }
    try:
        async with httpx.AsyncClient(timeout=60) as client:
            r = await client.post(f"{BASE}/api/generate", json=payload)
            if r.status_code != 200:
                raise ProviderError(f"ollama {r.status_code}: {r.text[:200]}")
            return (r.json().get("response") or "").strip()
    except ProviderError:
        raise
    except Exception as e:
        raise ProviderError(f"ollama unreachable: {e}")


async def list_models() -> list[str]:
    try:
        async with httpx.AsyncClient(timeout=8) as client:
            r = await client.get(f"{BASE}/api/tags")
            if r.status_code != 200:
                return []
            return [m["name"] for m in r.json().get("models", [])]
    except Exception:
        return []
