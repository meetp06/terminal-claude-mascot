from __future__ import annotations

from .base import Worker, Suggestion
from .workers.files import FilesWorker
from .workers.news import NewsWorker
from .workers.editor import EditorWorker

# Maps an agent `type` to its worker implementation.
WORKER_TYPES = {
    "files": FilesWorker,
    "news": NewsWorker,
    "editor": EditorWorker,
}


def make_worker(agent: dict):
    cls = WORKER_TYPES.get(agent["type"])
    if cls is None:
        return None
    return cls(agent)
