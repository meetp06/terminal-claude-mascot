"""Files worker: notices clutter in common folders and suggests organizing.

Read-only: it only lists directories and reads file metadata. The proposed
action is a description; nothing is moved or deleted in phase 1.
"""
from __future__ import annotations

import time
from collections import Counter

from ..base import Worker, Suggestion, AgentContext

WATCH = ["~/Downloads", "~/Desktop"]
CLUTTER_THRESHOLD = 25


class FilesWorker(Worker):
    tools = ["list_dir", "stat"]

    async def observe(self, ctx: AgentContext) -> list[Suggestion]:
        out: list[Suggestion] = []
        for folder in WATCH:
            res = await ctx.tool("list_dir", path=folder)
            if not res.get("exists"):
                continue
            entries = res["entries"]
            files = [e for e in entries if not e["isDir"]]
            n = len(files)
            if n < CLUTTER_THRESHOLD:
                continue

            exts = Counter()
            for e in files:
                name = e["name"]
                ext = name.rsplit(".", 1)[-1].lower() if "." in name else "no-ext"
                exts[ext] += 1
            top = ", ".join(f"{c} .{x}" for x, c in exts.most_common(4))

            now = time.time()
            old = [e for e in files if now - e["mtime"] > 30 * 86400]

            body = (f"{folder} has {n} loose files ({top}). "
                    f"{len(old)} are older than 30 days.")
            shared = ctx.shared_brief()
            prompt = (f"My folder {folder} has {n} loose files. Types: {top}. "
                      f"{len(old)} older than 30 days. Suggest how to organize it.")
            if shared:
                prompt += "\n\nRelevant shared local notes:\n" + shared
            refined = await ctx.llm(
                system="You are a tidy, concise desktop assistant. One sentence.",
                prompt=prompt,
            )
            if refined:
                body = refined.strip()

            score = min(1.0, 0.4 + n / 200 + len(old) / 100)
            out.append(Suggestion(
                title=f"Tidy {folder.split('/')[-1]}",
                body=body,
                proposedAction=(f"Group {folder} into subfolders by type/date "
                                "(read-only preview only in phase 1)."),
                score=round(score, 3),
            ))
        return out
