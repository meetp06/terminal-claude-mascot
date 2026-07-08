"""News worker: fetches finance/markets headlines and summarizes.

Read-only: it only performs an HTTP GET against a public headlines feed and
summarizes. It never trades or acts on anything.
"""
from __future__ import annotations

import re

from ..base import Worker, Suggestion, AgentContext

# Public RSS feed; no key required. Falls back gracefully if offline.
FEED = "https://news.google.com/rss/search?q=stock+market+trading&hl=en-US&gl=US&ceid=US:en"
_TITLE_RE = re.compile(r"<title>(.*?)</title>", re.S)


class NewsWorker(Worker):
    tools = ["web_fetch"]

    async def observe(self, ctx: AgentContext) -> list[Suggestion]:
        res = await ctx.tool("web_fetch", url=FEED)
        if not res.get("ok"):
            return []
        titles = [_clean(t) for t in _TITLE_RE.findall(res["text"])]
        # first title is the feed name; keep a handful of real headlines
        headlines = [t for t in titles[1:] if t][:6]
        if not headlines:
            return []

        joined = "; ".join(headlines[:5])
        body = f"Top market headlines: {joined}"
        shared = ctx.shared_brief()
        prompt = "Summarize these trading headlines for a busy user:\n" + \
                 "\n".join(f"- {h}" for h in headlines)
        if shared:
            prompt += "\n\nRelevant shared local notes:\n" + shared
        refined = await ctx.llm(
            system="You are a market news scout. 2 sentences, neutral, no advice.",
            prompt=prompt,
        )
        if refined:
            body = refined.strip()

        return [Suggestion(
            title="Market pulse",
            body=body,
            proposedAction="Open a full market briefing (read-only in phase 1).",
            score=0.55,
        )]


def _clean(s: str) -> str:
    s = re.sub(r"<!\[CDATA\[(.*?)\]\]>", r"\1", s, flags=re.S)
    s = re.sub(r"<.*?>", "", s)
    return s.strip()
