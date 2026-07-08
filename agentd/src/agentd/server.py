"""FastAPI WebSocket server: the single entry point the macOS app talks to.

Protocol is newline-free JSON objects, each with a `type`. See shared/protocol.md.
Connections must present the shared token (?token=...) that lives in
~/.petos/token, which the app reads from the same file.
"""
from __future__ import annotations

import asyncio
import json
from typing import Any

from fastapi import FastAPI, WebSocket, WebSocketDisconnect

from . import config, keychain, providers
from .agents.manager import Manager
from .store import Store
from .tools import available_tools, readonly

app = FastAPI(title="PetOS agentd")

_store = Store()
_clients: set[WebSocket] = set()
_clients_lock = asyncio.Lock()


async def broadcast(msg: dict[str, Any]) -> None:
    dead = []
    async with _clients_lock:
        targets = list(_clients)
    payload = json.dumps(msg)
    for ws in targets:
        try:
            await ws.send_text(payload)
        except Exception:
            dead.append(ws)
    if dead:
        async with _clients_lock:
            for ws in dead:
                _clients.discard(ws)


_manager = Manager(_store, broadcast)


@app.on_event("startup")
async def _startup() -> None:
    _manager.start()


@app.on_event("shutdown")
async def _shutdown() -> None:
    await _manager.stop()


@app.get("/health")
async def health() -> dict:
    return {"ok": True, "safeMode": config.SAFE_MODE, "tools": available_tools()}


def _snapshot() -> dict:
    return {
        "type": "snapshot",
        "agents": _store.list_agents(),
        "suggestions": _store.list_suggestions(status="new"),
        "workItems": _store.list_work_items(),
        "agentMemory": _store.list_memory(limit=100),
        "messages": _store.list_messages(),
        "settings": _settings_public(),
        "safeMode": config.SAFE_MODE,
        "tools": available_tools(),
    }


def _settings_public() -> dict:
    s = _store.get_settings()
    # never send secrets; only report which providers have a key
    s["keys"] = {
        p: keychain.has_key(p) for p in ("openai", "gemini", "groq")
    }
    return s


@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket) -> None:
    token = ws.query_params.get("token", "")
    if token != config.load_or_create_token():
        await ws.close(code=4401)
        return
    await ws.accept()
    async with _clients_lock:
        _clients.add(ws)
    await ws.send_text(json.dumps(_snapshot()))
    try:
        while True:
            raw = await ws.receive_text()
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                await ws.send_text(json.dumps({"type": "error", "text": "bad json"}))
                continue
            await _handle(ws, msg)
    except WebSocketDisconnect:
        pass
    finally:
        async with _clients_lock:
            _clients.discard(ws)


async def _handle(ws: WebSocket, msg: dict) -> None:
    t = msg.get("type")

    if t == "list_agents":
        await ws.send_text(json.dumps({"type": "agents", "agents": _store.list_agents()}))

    elif t == "create_agent":
        a = msg.get("agent", {})
        agent = _store.create_agent(
            name=a.get("name", "Newbie"),
            role=a.get("role", "worker"),
            type=a.get("type", "custom"),
            rank=a.get("rank", "newbie"),
            config_obj=a.get("config"),
        )
        await broadcast({"type": "agents", "agents": _store.list_agents()})
        await broadcast({"type": "agent_update", "agent": agent})

    elif t == "delete_agent":
        _store.delete_agent(msg.get("id", ""))
        await broadcast({"type": "agents", "agents": _store.list_agents()})

    elif t == "update_agent":
        agent = _store.update_agent(msg.get("id", ""), msg.get("patch", {}))
        if agent:
            await broadcast({"type": "agent_update", "agent": agent})

    elif t == "add_skill":
        sk = msg.get("skill", {})
        _store.add_skill(msg.get("agentId", ""), sk.get("name", "Skill"),
                         sk.get("trigger", "manual"), sk.get("tools", []),
                         sk.get("prompt", ""))
        await broadcast({"type": "agents", "agents": _store.list_agents()})

    elif t == "remove_skill":
        _store.remove_skill(msg.get("skillId", ""))
        await broadcast({"type": "agents", "agents": _store.list_agents()})

    elif t == "suggestion_action":
        action = msg.get("action")
        status = "approved" if action == "approve" else "dismissed"
        row = _store.set_suggestion_status(msg.get("id", ""), status)
        if row:
            await broadcast({"type": "suggestion_update", "suggestion": row})
        if action == "approve" and row:
            asyncio.create_task(_manager.handle_approved_suggestion(row))

    elif t == "chat":
        await _manager.handle_chat(msg.get("text", ""))

    elif t == "get_settings":
        await ws.send_text(json.dumps({"type": "settings", "settings": _settings_public()}))

    elif t == "update_settings":
        _store.update_settings(msg.get("patch", {}))
        await broadcast({"type": "settings", "settings": _settings_public()})

    elif t == "set_api_key":
        keychain.set_key(msg.get("provider", ""), msg.get("key", ""))
        await broadcast({"type": "settings", "settings": _settings_public()})

    elif t == "list_ollama_models":
        models = await providers.list_ollama_models()
        await ws.send_text(json.dumps({"type": "ollama_models", "models": models}))

    elif t == "frontmost":
        readonly.set_frontmost(msg.get("app"), msg.get("bundleId"))

    elif t == "system":
        state = msg.get("state")
        _manager.set_paused(state == "sleep")
        await broadcast({"type": "log", "level": "info", "text": f"system {state}"})

    elif t == "subscribe":
        await ws.send_text(json.dumps(_snapshot()))

    else:
        await ws.send_text(json.dumps({"type": "error", "text": f"unknown type: {t}"}))
