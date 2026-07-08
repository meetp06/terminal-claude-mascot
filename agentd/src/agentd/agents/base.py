"""Worker base class and the observation context.

A Worker OBSERVES (read-only) and returns Suggestions. It never acts. The
manager decides what to persist and surface. `ctx.llm()` is best-effort: if no
model is reachable it returns "" and the worker falls back to a deterministic
message, so the whole system works with zero configuration.
"""
from __future__ import annotations

from dataclasses import dataclass, field, asdict
from typing import Any, Awaitable, Callable, Optional

from .. import providers, tools
from ..providers.base import ProviderError

ActivityCallback = Callable[[str, str, str, str], Awaitable[None]]


@dataclass
class Suggestion:
    title: str
    body: str
    proposedAction: str = ""
    score: float = 0.5

    def as_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class AgentContext:
    provider: str = "ollama"
    model: str = "llama3.2"
    frontmost: dict[str, Any] = field(default_factory=dict)
    shared_memory: list[dict[str, Any]] = field(default_factory=list)
    agent_id: str = ""
    activity: Optional[ActivityCallback] = None

    async def tool(self, name: str, **kwargs: Any) -> Any:
        phase, title, detail = _tool_activity(name, kwargs)
        await self.report(phase, title, detail)
        return await tools.run_tool(name, **kwargs)

    async def llm(self, prompt: str, system: str = "") -> str:
        """Best-effort completion; empty string on any failure."""
        await self.report("thinking", "Thinking", "Refining the observation with the model.")
        try:
            return await providers.complete(self.provider, self.model, prompt, system)
        except ProviderError:
            return ""
        except Exception:
            return ""

    async def report(self, phase: str, title: str, detail: str = "") -> None:
        if self.activity and self.agent_id:
            await self.activity(self.agent_id, phase, title, detail)

    def shared_brief(self, max_chars: int = 900) -> str:
        """Return a tiny local handoff brief instead of a full conversation."""
        lines: list[str] = []
        for item in self.shared_memory[:6]:
            title = item.get("title") or item.get("topic") or "Context"
            summary = item.get("summary") or ""
            if summary:
                lines.append(f"- {title}: {summary}")
        text = "\n".join(lines)
        if len(text) <= max_chars:
            return text
        return text[:max_chars - 1].rstrip() + "…"


class Worker:
    #: which read-only tools this worker is allowed to touch
    tools: list[str] = []

    def __init__(self, agent: dict):
        self.agent = agent
        self.id = agent["id"]
        self.name = agent["name"]

    async def observe(self, ctx: AgentContext) -> list[Suggestion]:  # pragma: no cover
        raise NotImplementedError


def _tool_activity(name: str, kwargs: dict[str, Any]) -> tuple[str, str, str]:
    if name in {"list_dir", "stat", "read_file"}:
        target = kwargs.get("path", "")
        detail = f"Checking {target}" if target else "Checking local files"
        return ("reading_files", "Reading files", detail)
    if name == "frontmost_app":
        return ("checking_editor", "Checking active app", "Reading the focused application.")
    if name == "web_fetch":
        return ("researching_web", "Researching web", "Fetching a read-only source.")
    return ("observing", "Observing", f"Using {name}")
