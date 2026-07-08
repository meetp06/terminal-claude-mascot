"""Tool registry.

Phase 1 exposes ONLY read-only observation tools. There is no write, move,
delete, or exec tool anywhere in this package, so an agent literally cannot
mutate the system even if its LLM asks it to. `run_tool` additionally refuses
any name that is not in the read-only allowlist while SAFE_MODE == 'readonly'.
"""
from __future__ import annotations

from typing import Any, Callable

from .. import config
from . import readonly

# name -> (callable, is_read_only)
_REGISTRY: dict[str, tuple[Callable[..., Any], bool]] = {
    "list_dir": (readonly.list_dir, True),
    "read_file": (readonly.read_file, True),
    "stat": (readonly.stat_path, True),
    "frontmost_app": (readonly.frontmost_app, True),
    "web_fetch": (readonly.web_fetch, True),
}

READ_ONLY_TOOLS = [name for name, (_, ro) in _REGISTRY.items() if ro]


class ToolDenied(Exception):
    pass


def available_tools() -> list[str]:
    if config.SAFE_MODE == "readonly":
        return list(READ_ONLY_TOOLS)
    return list(_REGISTRY.keys())


async def run_tool(name: str, **kwargs: Any) -> Any:
    if name not in _REGISTRY:
        raise ToolDenied(f"unknown tool: {name}")
    fn, is_ro = _REGISTRY[name]
    if config.SAFE_MODE == "readonly" and not is_ro:
        raise ToolDenied(f"tool '{name}' blocked: SAFE_MODE=readonly")
    return await fn(**kwargs)
