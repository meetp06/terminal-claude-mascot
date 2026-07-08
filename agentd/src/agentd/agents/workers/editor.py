"""Editor worker: wakes when a code editor is the frontmost app.

Read-only: it only reads the last frontmost-app value the macOS app reported.
When a known editor is focused it offers to help.
"""
from __future__ import annotations

from ..base import Worker, Suggestion, AgentContext

EDITOR_HINTS = [
    "code", "cursor", "xcode", "sublime", "intellij", "pycharm", "webstorm",
    "vim", "nvim", "neovim", "emacs", "zed", "android studio", "fleet",
]


class EditorWorker(Worker):
    tools = ["frontmost_app"]

    async def observe(self, ctx: AgentContext) -> list[Suggestion]:
        info = await ctx.tool("frontmost_app")
        app = (info.get("app") or "").lower()
        if not app:
            return []
        if not any(h in app for h in EDITOR_HINTS):
            return []

        body = f"{info.get('app')} is in focus. I can watch for TODOs or explain code (read-only)."
        shared = ctx.shared_brief()
        prompt = f"The user just focused {info.get('app')}. Offer a small helpful nudge."
        if shared:
            prompt += "\n\nRelevant shared local notes:\n" + shared
        refined = await ctx.llm(
            system="You are a friendly pair-programmer pet. One short sentence.",
            prompt=prompt,
        )
        if refined:
            body = refined.strip()

        return [Suggestion(
            title="Ready to pair",
            body=body,
            proposedAction="Summarize the open project's structure (read-only in phase 1).",
            score=0.6,
        )]
