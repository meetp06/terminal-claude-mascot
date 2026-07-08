"""SQLite persistence for agents, skills, suggestions, chat and settings.

Deliberately tiny: a single connection guarded by a lock. The volumes here are
minuscule (a handful of agents, a stream of short suggestions) so a real ORM
would be overkill.
"""
from __future__ import annotations

import json
import sqlite3
import threading
import time
import uuid
from typing import Any, Optional

from . import config

_SCHEMA = """
CREATE TABLE IF NOT EXISTS agents (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    role TEXT NOT NULL,          -- manager | worker
    type TEXT NOT NULL,          -- files | news | editor | custom
    rank TEXT NOT NULL,          -- newbie | senior
    status TEXT NOT NULL,        -- alive | sleeping | working | paused
    visible INTEGER NOT NULL DEFAULT 1,
    config TEXT NOT NULL DEFAULT '{}',
    created_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS skills (
    id TEXT PRIMARY KEY,
    agent_id TEXT NOT NULL,
    name TEXT NOT NULL,
    trigger TEXT NOT NULL,       -- schedule | appFocus | manual
    tools TEXT NOT NULL DEFAULT '[]',
    prompt TEXT NOT NULL DEFAULT '',
    config TEXT NOT NULL DEFAULT '{}'
);
CREATE TABLE IF NOT EXISTS suggestions (
    id TEXT PRIMARY KEY,
    agent_id TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    proposed_action TEXT NOT NULL DEFAULT '',
    score REAL NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'new',   -- new | approved | dismissed
    created_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS agent_memory (
    id TEXT PRIMARY KEY,
    source_agent_id TEXT NOT NULL,
    target_agent_id TEXT NOT NULL DEFAULT '',
    topic TEXT NOT NULL DEFAULT '',
    title TEXT NOT NULL,
    summary TEXT NOT NULL,
    kind TEXT NOT NULL DEFAULT 'handoff',
    token_estimate INTEGER NOT NULL DEFAULT 0,
    created_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS work_items (
    id TEXT PRIMARY KEY,
    suggestion_id TEXT NOT NULL,
    agent_id TEXT NOT NULL,
    title TEXT NOT NULL,
    objective TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'queued', -- queued | working | completed | failed
    result TEXT NOT NULL DEFAULT '',
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY,
    sender TEXT NOT NULL,        -- user | manager
    text TEXT NOT NULL,
    created_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
"""

_DEFAULT_SETTINGS = {
    "provider": "ollama",          # ollama | openai | gemini | groq
    "model": "qwen2.5:7b-instruct",
    "safe_mode": "readonly",
    "launch_at_login": "false",
}


def _nid() -> str:
    return uuid.uuid4().hex[:12]


def _compact(text: str, max_chars: int = 700) -> str:
    cleaned = " ".join((text or "").split())
    if len(cleaned) <= max_chars:
        return cleaned
    return cleaned[:max_chars - 1].rstrip() + "…"


def _estimate_tokens(text: str) -> int:
    # Cheap local estimate: English-ish text averages around 4 chars/token.
    return max(1, (len(text or "") + 3) // 4)


class Store:
    def __init__(self, path: Optional[str] = None):
        config.ensure_base_dir()
        self._path = str(path or config.DB_PATH)
        self._lock = threading.RLock()
        self._db = sqlite3.connect(self._path, check_same_thread=False)
        self._db.row_factory = sqlite3.Row
        with self._lock:
            self._db.executescript(_SCHEMA)
            self._db.commit()
        self._seed_settings()
        self._seed_agents()

    # -- settings -----------------------------------------------------------
    def _seed_settings(self) -> None:
        with self._lock:
            for k, v in _DEFAULT_SETTINGS.items():
                self._db.execute(
                    "INSERT OR IGNORE INTO settings(key, value) VALUES(?, ?)",
                    (k, v),
                )
            self._db.commit()

    def get_settings(self) -> dict[str, Any]:
        with self._lock:
            rows = self._db.execute("SELECT key, value FROM settings").fetchall()
        return {r["key"]: r["value"] for r in rows}

    def update_settings(self, patch: dict[str, Any]) -> dict[str, Any]:
        with self._lock:
            for k, v in patch.items():
                self._db.execute(
                    "INSERT INTO settings(key, value) VALUES(?, ?) "
                    "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                    (k, str(v)),
                )
            self._db.commit()
        return self.get_settings()

    # -- agents -------------------------------------------------------------
    def _seed_agents(self) -> None:
        with self._lock:
            n = self._db.execute("SELECT COUNT(*) c FROM agents").fetchone()["c"]
        if n:
            return
        # A manager plus three read-only newbie workers.
        manager = self.create_agent(
            name="Manager", role="manager", type="custom", rank="senior"
        )
        files = self.create_agent(name="Filer", role="worker", type="files")
        news = self.create_agent(name="Scout", role="worker", type="news")
        editor = self.create_agent(name="Pair", role="worker", type="editor")
        self.add_skill(files["id"], "Tidy watch", "schedule",
                       ["list_dir", "stat"], "Spot cluttered folders.")
        self.add_skill(news["id"], "Market pulse", "schedule",
                       ["web_fetch"], "Summarize relevant trading headlines.")
        self.add_skill(editor["id"], "Editor helper", "appFocus",
                       ["frontmost_app"], "Offer help when a code editor is focused.")

    def create_agent(self, name: str, role: str = "worker", type: str = "custom",
                     rank: str = "newbie", config_obj: Optional[dict] = None) -> dict:
        aid = _nid()
        now = time.time()
        with self._lock:
            self._db.execute(
                "INSERT INTO agents(id,name,role,type,rank,status,visible,config,created_at)"
                " VALUES(?,?,?,?,?,?,?,?,?)",
                (aid, name, role, type, rank, "sleeping", 1,
                 json.dumps(config_obj or {}), now),
            )
            self._db.commit()
        return self.get_agent(aid)  # type: ignore[return-value]

    def get_agent(self, aid: str) -> Optional[dict]:
        with self._lock:
            row = self._db.execute("SELECT * FROM agents WHERE id=?", (aid,)).fetchone()
        return self._agent_row(row) if row else None

    def list_agents(self) -> list[dict]:
        with self._lock:
            rows = self._db.execute(
                "SELECT * FROM agents ORDER BY role='worker', created_at"
            ).fetchall()
        return [self._agent_row(r) for r in rows]

    def update_agent(self, aid: str, patch: dict[str, Any]) -> Optional[dict]:
        allowed = {"name", "status", "visible", "rank", "config"}
        sets, vals = [], []
        for k, v in patch.items():
            if k not in allowed:
                continue
            if k == "config":
                v = json.dumps(v)
            if k == "visible":
                v = 1 if v else 0
            sets.append(f"{k}=?")
            vals.append(v)
        if not sets:
            return self.get_agent(aid)
        vals.append(aid)
        with self._lock:
            self._db.execute(f"UPDATE agents SET {', '.join(sets)} WHERE id=?", vals)
            self._db.commit()
        return self.get_agent(aid)

    def delete_agent(self, aid: str) -> None:
        with self._lock:
            self._db.execute("DELETE FROM agents WHERE id=?", (aid,))
            self._db.execute("DELETE FROM skills WHERE agent_id=?", (aid,))
            self._db.commit()

    def _agent_row(self, r: sqlite3.Row) -> dict:
        return {
            "id": r["id"], "name": r["name"], "role": r["role"], "type": r["type"],
            "rank": r["rank"], "status": r["status"], "visible": bool(r["visible"]),
            "config": json.loads(r["config"] or "{}"),
            "skills": self.list_skills(r["id"]),
            "createdAt": r["created_at"],
        }

    # -- skills -------------------------------------------------------------
    def add_skill(self, agent_id: str, name: str, trigger: str,
                  tools: list[str], prompt: str = "") -> dict:
        sid = _nid()
        with self._lock:
            self._db.execute(
                "INSERT INTO skills(id,agent_id,name,trigger,tools,prompt,config)"
                " VALUES(?,?,?,?,?,?,?)",
                (sid, agent_id, name, trigger, json.dumps(tools), prompt, "{}"),
            )
            self._db.commit()
        return self.get_skill(sid)  # type: ignore[return-value]

    def get_skill(self, sid: str) -> Optional[dict]:
        with self._lock:
            r = self._db.execute("SELECT * FROM skills WHERE id=?", (sid,)).fetchone()
        return self._skill_row(r) if r else None

    def list_skills(self, agent_id: str) -> list[dict]:
        with self._lock:
            rows = self._db.execute(
                "SELECT * FROM skills WHERE agent_id=?", (agent_id,)
            ).fetchall()
        return [self._skill_row(r) for r in rows]

    def remove_skill(self, sid: str) -> None:
        with self._lock:
            self._db.execute("DELETE FROM skills WHERE id=?", (sid,))
            self._db.commit()

    def _skill_row(self, r: sqlite3.Row) -> dict:
        return {
            "id": r["id"], "agentId": r["agent_id"], "name": r["name"],
            "trigger": r["trigger"], "tools": json.loads(r["tools"] or "[]"),
            "prompt": r["prompt"],
        }

    # -- suggestions --------------------------------------------------------
    def add_suggestion(self, agent_id: str, title: str, body: str,
                       proposed_action: str = "", score: float = 0.0) -> dict:
        sid = _nid()
        now = time.time()
        with self._lock:
            self._db.execute(
                "INSERT INTO suggestions(id,agent_id,title,body,proposed_action,score,status,created_at)"
                " VALUES(?,?,?,?,?,?,?,?)",
                (sid, agent_id, title, body, proposed_action, score, "new", now),
            )
            self._db.commit()
        return self.get_suggestion(sid)  # type: ignore[return-value]

    def get_suggestion(self, sid: str) -> Optional[dict]:
        with self._lock:
            r = self._db.execute("SELECT * FROM suggestions WHERE id=?", (sid,)).fetchone()
        return self._sugg_row(r) if r else None

    def list_suggestions(self, status: Optional[str] = None, limit: int = 100) -> list[dict]:
        with self._lock:
            if status:
                rows = self._db.execute(
                    "SELECT * FROM suggestions WHERE status=? ORDER BY score DESC, created_at DESC LIMIT ?",
                    (status, limit),
                ).fetchall()
            else:
                rows = self._db.execute(
                    "SELECT * FROM suggestions ORDER BY created_at DESC LIMIT ?",
                    (limit,),
                ).fetchall()
        return [self._sugg_row(r) for r in rows]

    def set_suggestion_status(self, sid: str, status: str) -> Optional[dict]:
        with self._lock:
            self._db.execute("UPDATE suggestions SET status=? WHERE id=?", (status, sid))
            self._db.commit()
        return self.get_suggestion(sid)

    def recent_suggestion_titles(self, agent_id: str, within_s: float = 3600) -> set[str]:
        cutoff = time.time() - within_s
        with self._lock:
            rows = self._db.execute(
                "SELECT title FROM suggestions WHERE agent_id=? AND created_at>?",
                (agent_id, cutoff),
            ).fetchall()
        return {r["title"] for r in rows}

    def _sugg_row(self, r: sqlite3.Row) -> dict:
        return {
            "id": r["id"], "agentId": r["agent_id"], "title": r["title"],
            "body": r["body"], "proposedAction": r["proposed_action"],
            "score": r["score"], "status": r["status"], "createdAt": r["created_at"],
        }

    # -- shared agent memory -----------------------------------------------
    def add_memory(self, source_agent_id: str, title: str, summary: str,
                   target_agent_id: str = "", topic: str = "",
                   kind: str = "handoff") -> dict:
        mid = _nid()
        now = time.time()
        compact = _compact(summary)
        token_estimate = _estimate_tokens(compact)
        with self._lock:
            self._db.execute(
                "INSERT INTO agent_memory(id,source_agent_id,target_agent_id,topic,title,summary,kind,token_estimate,created_at)"
                " VALUES(?,?,?,?,?,?,?,?,?)",
                (mid, source_agent_id, target_agent_id or "", topic or title,
                 title, compact, kind, token_estimate, now),
            )
            self._db.commit()
        return self.get_memory(mid)  # type: ignore[return-value]

    def get_memory(self, mid: str) -> Optional[dict]:
        with self._lock:
            r = self._db.execute("SELECT * FROM agent_memory WHERE id=?", (mid,)).fetchone()
        return self._memory_row(r) if r else None

    def list_memory(self, agent_id: Optional[str] = None, limit: int = 100) -> list[dict]:
        with self._lock:
            if agent_id:
                rows = self._db.execute(
                    "SELECT * FROM agent_memory "
                    "WHERE source_agent_id=? OR target_agent_id=? OR target_agent_id='' "
                    "ORDER BY created_at DESC LIMIT ?",
                    (agent_id, agent_id, limit),
                ).fetchall()
            else:
                rows = self._db.execute(
                    "SELECT * FROM agent_memory ORDER BY created_at DESC LIMIT ?",
                    (limit,),
                ).fetchall()
        return [self._memory_row(r) for r in rows]

    def _memory_row(self, r: sqlite3.Row) -> dict:
        return {
            "id": r["id"], "sourceAgentId": r["source_agent_id"],
            "targetAgentId": r["target_agent_id"], "topic": r["topic"],
            "title": r["title"], "summary": r["summary"], "kind": r["kind"],
            "tokenEstimate": r["token_estimate"], "createdAt": r["created_at"],
        }

    # -- approved work queue ------------------------------------------------
    def add_work_item(self, suggestion: dict) -> dict:
        wid = _nid()
        now = time.time()
        objective = suggestion.get("proposedAction") or suggestion.get("body") or ""
        with self._lock:
            self._db.execute(
                "INSERT INTO work_items(id,suggestion_id,agent_id,title,objective,status,result,created_at,updated_at)"
                " VALUES(?,?,?,?,?,?,?,?,?)",
                (wid, suggestion["id"], suggestion["agentId"], suggestion["title"],
                 objective, "queued", "", now, now),
            )
            self._db.commit()
        return self.get_work_item(wid)  # type: ignore[return-value]

    def get_work_item(self, wid: str) -> Optional[dict]:
        with self._lock:
            r = self._db.execute("SELECT * FROM work_items WHERE id=?", (wid,)).fetchone()
        return self._work_row(r) if r else None

    def list_work_items(self, status: Optional[str] = None, limit: int = 50) -> list[dict]:
        with self._lock:
            if status:
                rows = self._db.execute(
                    "SELECT * FROM work_items WHERE status=? ORDER BY updated_at DESC LIMIT ?",
                    (status, limit),
                ).fetchall()
            else:
                rows = self._db.execute(
                    "SELECT * FROM work_items ORDER BY updated_at DESC LIMIT ?",
                    (limit,),
                ).fetchall()
        return [self._work_row(r) for r in rows]

    def update_work_item(self, wid: str, patch: dict[str, Any]) -> Optional[dict]:
        allowed = {"status", "result"}
        sets, vals = [], []
        for k, v in patch.items():
            if k not in allowed:
                continue
            sets.append(f"{k}=?")
            vals.append(str(v))
        if not sets:
            return self.get_work_item(wid)
        sets.append("updated_at=?")
        vals.append(time.time())
        vals.append(wid)
        with self._lock:
            self._db.execute(f"UPDATE work_items SET {', '.join(sets)} WHERE id=?", vals)
            self._db.commit()
        return self.get_work_item(wid)

    def _work_row(self, r: sqlite3.Row) -> dict:
        return {
            "id": r["id"], "suggestionId": r["suggestion_id"],
            "agentId": r["agent_id"], "title": r["title"],
            "objective": r["objective"], "status": r["status"],
            "result": r["result"], "createdAt": r["created_at"],
            "updatedAt": r["updated_at"],
        }

    # -- messages -----------------------------------------------------------
    def add_message(self, sender: str, text: str) -> dict:
        mid = _nid()
        now = time.time()
        with self._lock:
            self._db.execute(
                "INSERT INTO messages(id,sender,text,created_at) VALUES(?,?,?,?)",
                (mid, sender, text, now),
            )
            self._db.commit()
        return {"id": mid, "sender": sender, "text": text, "createdAt": now}

    def list_messages(self, limit: int = 100) -> list[dict]:
        with self._lock:
            rows = self._db.execute(
                "SELECT * FROM messages ORDER BY created_at ASC LIMIT ?", (limit,)
            ).fetchall()
        return [
            {"id": r["id"], "sender": r["sender"], "text": r["text"],
             "createdAt": r["created_at"]}
            for r in rows
        ]
