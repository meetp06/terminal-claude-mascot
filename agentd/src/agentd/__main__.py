"""Entry point: `python -m agentd` (or the `agentd` console script).

Prints the loopback URL + token line the app looks for on stdout, then serves.
"""
from __future__ import annotations

import uvicorn

from . import config


def main() -> None:
    config.ensure_base_dir()
    token = config.load_or_create_token()
    # The app parses this line from the sidecar's stdout to learn the token.
    print(f"PETOS_READY ws://{config.HOST}:{config.PORT}/ws token={token}", flush=True)
    uvicorn.run(
        "agentd.server:app",
        host=config.HOST,
        port=config.PORT,
        log_level="warning",
    )


if __name__ == "__main__":
    main()
