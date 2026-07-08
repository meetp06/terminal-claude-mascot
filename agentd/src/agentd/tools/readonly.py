"""Read-only observation tools.

Every function here only READS. They are size/entry capped so an agent cannot
accidentally slurp a huge tree or file. `frontmost_app` reads a value the app
pushes over the socket rather than shelling out, keeping the sidecar exec-free.
"""
from __future__ import annotations

import os
import time
from pathlib import Path
from typing import Any, Optional

import httpx

from .. import config

# Updated by the server whenever the macOS app reports the focused application.
_FRONTMOST: dict[str, Any] = {"app": None, "bundleId": None, "ts": 0.0}


def set_frontmost(app: Optional[str], bundle_id: Optional[str]) -> None:
    _FRONTMOST.update(app=app, bundleId=bundle_id, ts=time.time())


def _safe_path(p: str) -> Path:
    return Path(os.path.expanduser(p)).resolve()


async def list_dir(path: str = "~") -> dict[str, Any]:
    base = _safe_path(path)
    if not base.exists() or not base.is_dir():
        return {"path": str(base), "exists": False, "entries": []}
    entries = []
    for i, child in enumerate(sorted(base.iterdir(), key=lambda c: c.name.lower())):
        if i >= config.MAX_DIR_ENTRIES:
            break
        try:
            st = child.stat()
            entries.append({
                "name": child.name,
                "isDir": child.is_dir(),
                "size": st.st_size,
                "mtime": st.st_mtime,
            })
        except OSError:
            continue
    return {"path": str(base), "exists": True, "entries": entries,
            "count": len(entries)}


async def read_file(path: str, max_bytes: int = config.MAX_READ_BYTES) -> dict[str, Any]:
    p = _safe_path(path)
    if not p.exists() or not p.is_file():
        return {"path": str(p), "exists": False, "text": ""}
    cap = min(int(max_bytes), config.MAX_READ_BYTES)
    data = p.read_bytes()[:cap]
    try:
        text = data.decode("utf-8", errors="replace")
    except Exception:
        text = ""
    return {"path": str(p), "exists": True, "text": text,
            "truncated": p.stat().st_size > cap}


async def stat_path(path: str) -> dict[str, Any]:
    p = _safe_path(path)
    if not p.exists():
        return {"path": str(p), "exists": False}
    st = p.stat()
    return {
        "path": str(p), "exists": True, "isDir": p.is_dir(),
        "size": st.st_size, "mtime": st.st_mtime, "ctime": st.st_ctime,
    }


async def frontmost_app() -> dict[str, Any]:
    return dict(_FRONTMOST)


async def web_fetch(url: str, max_bytes: int = config.MAX_FETCH_BYTES) -> dict[str, Any]:
    if not (url.startswith("http://") or url.startswith("https://")):
        return {"url": url, "ok": False, "error": "only http(s) allowed"}
    cap = min(int(max_bytes), config.MAX_FETCH_BYTES)
    try:
        async with httpx.AsyncClient(timeout=12, follow_redirects=True) as client:
            r = await client.get(url, headers={"User-Agent": "PetOS/0.1 (+read-only)"})
            body = r.content[:cap]
            return {
                "url": str(r.url), "ok": r.is_success, "status": r.status_code,
                "text": body.decode("utf-8", errors="replace"),
                "truncated": len(r.content) > cap,
            }
    except Exception as e:  # network failures must not crash an agent
        return {"url": url, "ok": False, "error": str(e)}
