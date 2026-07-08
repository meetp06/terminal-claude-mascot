"""API key storage.

Prefers the macOS Keychain (via the optional `keyring` dependency). If keyring
is unavailable it falls back to a 0600 file under ~/.petos so the app still
works in a bare dev checkout. Keys are never written to the SQLite DB.
"""
from __future__ import annotations

import json
import os
from typing import Optional

from . import config

_SERVICE = "com.petos.agentd"
_FALLBACK = config.BASE_DIR / "keys.json"

try:  # optional dependency
    import keyring  # type: ignore
    _HAS_KEYRING = True
except Exception:  # pragma: no cover - environment dependent
    _HAS_KEYRING = False


def _fallback_load() -> dict[str, str]:
    if _FALLBACK.exists():
        try:
            return json.loads(_FALLBACK.read_text())
        except Exception:
            return {}
    return {}


def _fallback_save(data: dict[str, str]) -> None:
    config.ensure_base_dir()
    _FALLBACK.write_text(json.dumps(data))
    os.chmod(_FALLBACK, 0o600)


def set_key(provider: str, key: str) -> None:
    if _HAS_KEYRING:
        keyring.set_password(_SERVICE, provider, key)
        return
    data = _fallback_load()
    data[provider] = key
    _fallback_save(data)


def get_key(provider: str) -> Optional[str]:
    # An env var always wins so CI / power users can inject keys.
    env = os.environ.get(f"{provider.upper()}_API_KEY")
    if env:
        return env
    if _HAS_KEYRING:
        try:
            return keyring.get_password(_SERVICE, provider)
        except Exception:
            return None
    return _fallback_load().get(provider)


def has_key(provider: str) -> bool:
    return bool(get_key(provider))
