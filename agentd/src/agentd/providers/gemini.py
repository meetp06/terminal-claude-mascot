"""Google Gemini provider (generateContent REST API)."""
from __future__ import annotations

import httpx

from .. import keychain
from .base import ProviderError

_BASE = "https://generativelanguage.googleapis.com/v1beta/models"


async def complete(model: str, prompt: str, system: str = "") -> str:
    key = keychain.get_key("gemini")
    if not key:
        raise ProviderError("no API key for gemini")
    model = model or "gemini-1.5-flash"
    url = f"{_BASE}/{model}:generateContent?key={key}"
    body: dict = {
        "contents": [{"role": "user", "parts": [{"text": prompt}]}],
        "generationConfig": {"temperature": 0.4},
    }
    if system:
        body["systemInstruction"] = {"parts": [{"text": system}]}
    try:
        async with httpx.AsyncClient(timeout=60) as client:
            r = await client.post(url, json=body)
            if r.status_code != 200:
                raise ProviderError(f"gemini {r.status_code}: {r.text[:200]}")
            data = r.json()
            cands = data.get("candidates", [])
            if not cands:
                return ""
            parts = cands[0].get("content", {}).get("parts", [])
            return "".join(p.get("text", "") for p in parts).strip()
    except ProviderError:
        raise
    except Exception as e:
        raise ProviderError(f"gemini error: {e}")
