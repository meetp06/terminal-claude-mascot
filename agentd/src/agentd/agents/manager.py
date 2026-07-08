"""Manager agent: orchestrates the read-only workers.

Responsibilities:
- On a timer, wake each alive worker, let it observe, dedupe + score the
  results, persist and broadcast new suggestions.
- Flip worker status (sleeping <-> working) and broadcast it so on-screen pets
  animate while thinking.
- Answer the user's chat messages (best-effort LLM, deterministic fallback).

The manager itself has no write tools; it only coordinates.
"""
from __future__ import annotations

import asyncio
import contextlib
import time
from typing import Awaitable, Callable

from .. import config, providers
from ..providers.base import ProviderError
from ..store import Store
from . import make_worker
from .base import AgentContext

Broadcast = Callable[[dict], Awaitable[None]]


def _format_memory(items: list[dict], max_chars: int = 1200) -> str:
    lines = []
    for item in items[:8]:
        title = item.get("title") or item.get("topic") or "Context"
        summary = item.get("summary") or ""
        if summary:
            lines.append(f"- {title}: {summary}")
    text = "\n".join(lines)
    if len(text) <= max_chars:
        return text
    return text[:max_chars - 1].rstrip() + "…"


class Manager:
    def __init__(self, store: Store, broadcast: Broadcast):
        self.store = store
        self.broadcast = broadcast
        self._task: asyncio.Task | None = None
        self._paused = False

    # -- lifecycle ----------------------------------------------------------
    def start(self) -> None:
        if self._task is None:
            self._task = asyncio.create_task(self._loop())

    async def stop(self) -> None:
        if self._task:
            self._task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self._task
            self._task = None

    def set_paused(self, paused: bool) -> None:
        # Used by the app on system sleep/wake so agents don't churn while the
        # laptop is closed.
        self._paused = paused

    # -- context ------------------------------------------------------------
    def _ctx(self, agent_id: str = "") -> AgentContext:
        s = self.store.get_settings()
        from ..tools import readonly
        return AgentContext(
            provider=s.get("provider", "ollama"),
            model=s.get("model", "llama3.2"),
            frontmost=dict(readonly._FRONTMOST),
            shared_memory=self.store.list_memory(agent_id, limit=6) if agent_id else [],
            agent_id=agent_id,
            activity=self._activity,
        )

    # -- scheduler ----------------------------------------------------------
    async def _loop(self) -> None:
        # small initial delay so the app has time to subscribe
        await asyncio.sleep(3)
        while True:
            try:
                if not self._paused:
                    await self.observe_all()
            except asyncio.CancelledError:
                raise
            except Exception as e:  # never let the loop die
                await self.broadcast({"type": "log", "level": "error",
                                      "text": f"observe cycle failed: {e}"})
            await asyncio.sleep(config.OBSERVE_INTERVAL)

    async def observe_all(self) -> None:
        for agent in self.store.list_agents():
            if agent["role"] != "worker":
                continue
            if agent["status"] == "paused":
                continue
            worker = make_worker(agent)
            if worker is None:
                continue
            await self._set_status(agent["id"], "working")
            await self._activity(
                agent["id"], "observing", "Starting scan",
                f"{agent['name']} is checking {agent['type']} signals.",
            )
            ctx = self._ctx(agent["id"])
            try:
                suggestions = await worker.observe(ctx)
            except Exception as e:
                await self.broadcast({"type": "log", "level": "error",
                                      "text": f"{agent['name']} failed: {e}"})
                await self._activity(agent["id"], "error", "Scan failed", str(e)[:120])
                suggestions = []
            saved = await self._persist(agent, suggestions)
            if saved:
                await self._activity(
                    agent["id"], "suggestion_found", "Suggestion found",
                    f"{saved} new item{'s' if saved != 1 else ''} ready for review.",
                )
            else:
                await self._activity(
                    agent["id"], "waiting", "Nothing new",
                    "Standing by until the next scan.",
                )
            await self._set_status(agent["id"], "sleeping")

    async def _persist(self, agent: dict, suggestions: list) -> int:
        recent = self.store.recent_suggestion_titles(agent["id"])
        saved = 0
        for s in suggestions:
            if s.title in recent:
                continue  # avoid spamming the same nudge every cycle
            row = self.store.add_suggestion(
                agent["id"], s.title, s.body, s.proposedAction, s.score
            )
            await self.broadcast({"type": "suggestion", "suggestion": row})
            memory = self.store.add_memory(
                agent["id"],
                title=s.title,
                summary=f"{agent['name']} observed: {s.body} Proposed: {s.proposedAction}",
                topic=s.title,
                kind="suggestion",
            )
            await self.broadcast({"type": "agent_memory", "memory": memory})
            saved += 1
        return saved

    async def _set_status(self, agent_id: str, status: str) -> None:
        row = self.store.update_agent(agent_id, {"status": status})
        if row:
            await self.broadcast({"type": "agent_update", "agent": row})

    async def _activity(self, agent_id: str, phase: str, title: str, detail: str = "") -> None:
        await self.broadcast({
            "type": "agent_activity",
            "activity": {
                "agentId": agent_id,
                "phase": phase,
                "title": title,
                "detail": detail,
                "createdAt": time.time(),
            },
        })

    # -- approved work ------------------------------------------------------
    async def handle_approved_suggestion(self, suggestion: dict) -> None:
        """Turn an approved suggestion into a visible, read-only work item."""
        work = self.store.add_work_item(suggestion)
        await self.broadcast({"type": "work_item", "workItem": work})
        agent = self.store.get_agent(suggestion["agentId"])
        agent_name = agent["name"] if agent else "Agent"
        work_id = work["id"]

        try:
            work = self.store.update_work_item(work_id, {"status": "working"}) or work
            await self.broadcast({"type": "work_item_update", "workItem": work})
            await self._set_status(suggestion["agentId"], "working")
            await self._activity(
                suggestion["agentId"],
                "work_started",
                "Approved work started",
                f"{agent_name} is working on: {suggestion['title']}",
            )
            await self._activity(
                suggestion["agentId"],
                "sharing_context",
                "Sharing context",
                "Loading compact handoffs from the local team memory.",
            )

            result = await self._complete_approved_work(suggestion, agent_name)
            memory = self.store.add_memory(
                suggestion["agentId"],
                title=f"Approved: {suggestion['title']}",
                summary=result,
                topic=suggestion["title"],
                kind="approved_work",
            )
            await self.broadcast({"type": "agent_memory", "memory": memory})

            work = self.store.update_work_item(
                work_id, {"status": "completed", "result": result}
            ) or work
            await self.broadcast({"type": "work_item_update", "workItem": work})
            msg = self.store.add_message(
                "manager",
                f"{agent_name} finished approved work: {suggestion['title']}\n\n{result}",
            )
            await self.broadcast({"type": "chat", "message": msg})
            await self._activity(
                suggestion["agentId"],
                "work_complete",
                "Work complete",
                "Result saved to shared memory for the other agents.",
            )
        except Exception as e:
            detail = str(e)[:240]
            work = self.store.update_work_item(
                work_id, {"status": "failed", "result": detail}
            ) or work
            await self.broadcast({"type": "work_item_update", "workItem": work})
            await self._activity(suggestion["agentId"], "error", "Work failed", detail)
        finally:
            current = self.store.get_agent(suggestion["agentId"])
            if current and current["status"] != "paused":
                await self._set_status(suggestion["agentId"], "sleeping")

    async def _complete_approved_work(self, suggestion: dict, agent_name: str) -> str:
        s = self.store.get_settings()
        shared = _format_memory(self.store.list_memory(suggestion["agentId"], limit=8))
        roster = ", ".join(
            f"{a['name']}({a['type']})"
            for a in self.store.list_agents()
            if a["role"] == "worker" and a["id"] != suggestion["agentId"]
        )
        system = (
            "You are the PetOS manager coordinating read-only pet agents. "
            "The user approved a suggestion, so produce a concrete work result. "
            "Do not claim to edit files, run commands, trade, send messages, or mutate state. "
            "Use compact local memory if relevant. Keep the result under 120 words."
        )
        prompt = (
            f"Approved suggestion from {agent_name}:\n"
            f"Title: {suggestion['title']}\n"
            f"Observation: {suggestion['body']}\n"
            f"Requested work: {suggestion['proposedAction'] or suggestion['body']}\n\n"
            f"Other available agents: {roster or 'none'}\n"
            f"Shared local memory:\n{shared or '- No prior handoffs.'}\n\n"
            "Return: what was worked through, the read-only result, and the next safest user action."
        )
        try:
            reply = await providers.complete(
                s.get("provider", "ollama"), s.get("model", "llama3.2"),
                prompt, system,
            )
        except ProviderError:
            reply = ""
        except Exception:
            reply = ""
        if reply.strip():
            return reply.strip()
        return (
            f"Worked through '{suggestion['title']}' in read-only mode. "
            f"Observation: {suggestion['body']} "
            f"Recommended next action: {suggestion['proposedAction'] or 'review the suggestion details'}."
        )

    # -- chat ---------------------------------------------------------------
    async def handle_chat(self, text: str) -> dict:
        self.store.add_message("user", text)
        s = self.store.get_settings()
        agents = self.store.list_agents()
        roster = ", ".join(f"{a['name']}({a['type']})" for a in agents if a["role"] == "worker")
        shared = _format_memory(self.store.list_memory(limit=8))
        system = (
            "You are the Manager of a team of read-only desktop pet agents. "
            "You can observe the user's system (files, news, focused app) but in "
            "phase 1 you may NOT edit or run anything; explain that if asked to act. "
            "Use compact shared memory instead of replaying full conversations. "
            f"Your workers: {roster}. Shared local memory: {shared or 'none'}."
        )
        reply = ""
        try:
            reply = await providers.complete(
                s.get("provider", "ollama"), s.get("model", "llama3.2"),
                text, system,
            )
        except ProviderError:
            reply = ""
        except Exception:
            reply = ""
        if not reply:
            reply = (
                "Noted. I'm in read-only mode (phase 1), so I can look into this and "
                "prepare suggestions, but I can't change or run anything yet. "
                f"I'll have {roster or 'my workers'} observe and report back."
            )
        msg = self.store.add_message("manager", reply)
        await self.broadcast({"type": "chat", "message": msg})
        return msg
