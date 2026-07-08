"""OpenAI and Groq share the same chat-completions wire format."""
from __future__ import annotations

import httpx

from .. import keychain
from .base import ProviderError

_ENDPOINTS = {
    "openai": "https://api.openai.com/v1/chat/completions",
    "groq": "https://api.groq.com/openai/v1/chat/completions",
}


async def complete(provider: str, model: str, prompt: str, system: str = "") -> str:
    key = keychain.get_key(provider)
    if not key:
        raise ProviderError(f"no API key for {provider}")
    url = _ENDPOINTS[provider]
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})
    payload = {"model": model, "messages": messages, "temperature": 0.4}
    try:
        async with httpx.AsyncClient(timeout=60) as client:
            r = await client.post(
                url, json=payload,
                headers={"Authorization": f"Bearer {key}"},
            )
            if r.status_code != 200:
                raise ProviderError(f"{provider} {r.status_code}: {r.text[:200]}")
            data = r.json()
            return (data["choices"][0]["message"]["content"] or "").strip()
    except ProviderError:
        raise
    except Exception as e:
        raise ProviderError(f"{provider} error: {e}")
