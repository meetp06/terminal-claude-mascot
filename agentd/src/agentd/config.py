"""Runtime configuration and paths.

Everything the sidecar persists lives under ~/.petos so it is independent of
the app bundle and survives reinstalls.
"""
from __future__ import annotations

import os
import secrets
from pathlib import Path

HOME = Path(os.path.expanduser("~"))
BASE_DIR = Path(os.environ.get("PETOS_HOME", HOME / ".petos"))
DB_PATH = BASE_DIR / "petos.db"
TOKEN_PATH = BASE_DIR / "token"

HOST = os.environ.get("PETOS_HOST", "127.0.0.1")
PORT = int(os.environ.get("PETOS_PORT", "8765"))

# Phase 1 is hard-locked to read-only. This is intentionally not overridable
# from the network protocol; only an env var an operator sets can change it,
# and even then the tool registry must gain write tools (it has none yet).
SAFE_MODE = os.environ.get("PETOS_SAFE_MODE", "readonly")

# How often (seconds) the manager wakes each active worker to observe.
OBSERVE_INTERVAL = float(os.environ.get("PETOS_OBSERVE_INTERVAL", "45"))

# Caps that keep read-only tools cheap and safe.
MAX_READ_BYTES = 64 * 1024
MAX_DIR_ENTRIES = 500
MAX_FETCH_BYTES = 256 * 1024


def ensure_base_dir() -> None:
    BASE_DIR.mkdir(parents=True, exist_ok=True)


def load_or_create_token() -> str:
    """A shared secret the app must present to connect. Prevents other local
    processes from driving the agents."""
    ensure_base_dir()
    if TOKEN_PATH.exists():
        tok = TOKEN_PATH.read_text().strip()
        if tok:
            return tok
    tok = secrets.token_urlsafe(24)
    TOKEN_PATH.write_text(tok)
    os.chmod(TOKEN_PATH, 0o600)
    return tok
