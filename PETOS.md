# PetOS - local agent pets for macOS (phase 1: read-only)

A native macOS app where animated "pet" agents live on your screen, coordinated
by a **Manager** agent. Worker agents observe your system with **local Ollama**
models (or a cloud provider you plug in) and surface suggestions. A SwiftUI
**Control Center** lets you administer the whole team.

> Phase 1 is strictly **read-only**: agents can look at things (folders, news,
> the focused app) but cannot edit, move, delete, or run anything. Approving a
> suggestion starts a managed read-only work item and saves the result as compact
> local context for the other agents.

## Layout

```
app/       PetOS macOS app (SwiftUI + AppKit overlay). SwiftPM package.
agentd/    Python sidecar: manager + workers, WebSocket server, LLM providers.
shared/    protocol.md - the WebSocket message contract.
scripts/   dev-agentd.sh, run-app.sh
```

Architecture and the full protocol live in [shared/protocol.md](shared/protocol.md).

## Quick start (dev)

Prereqs: macOS 13+, Xcode command line tools (`swiftc`), Python 3.11+, and
(optional) [Ollama](https://ollama.com) running locally for real LLM output.

```bash
# one command: builds the app, creates the sidecar venv, runs everything
./scripts/run-app.sh
```

Then click the **pawprint** icon in the menu bar and choose *Open Control
Center*. The pets appear up the right edge of your screen.

To run just the sidecar (e.g. to develop agents):

```bash
./scripts/dev-agentd.sh
```

## What ships in phase 1

- **Manager** agent orchestrates a timed observation loop.
- Workers:
  - **Filer** (files) - flags cluttered `~/Downloads` / `~/Desktop`.
  - **Scout** (news) - summarizes market/trading headlines.
  - **Pair** (editor) - wakes when a code editor is focused.
- **Control Center**: live agent list, create/delete agents, add/remove skills,
  hide/show on screen, pause/resume, a suggestions inbox with approved work
  progress, shared agent memory, and a chat with the manager.
- **Providers**: Ollama (default, no key), plus OpenAI / Gemini / Groq via an API
  key stored in the macOS **Keychain**. Everything works with zero config - if
  no model is reachable, agents fall back to deterministic suggestions.
- **Lifecycle**: menu-bar accessory (no Dock icon), launch-at-login toggle, and
  agents pause on system sleep / resume on wake.

## Read-only guarantee

The sidecar's tool registry (`agentd/src/agentd/tools/`) contains only
`list_dir, read_file, stat, frontmost_app, web_fetch`. There is no write/move/
delete/exec tool anywhere, and `run_tool` refuses any name not on the read-only
allowlist while `SAFE_MODE=readonly`. `GET /health` and the `snapshot` message
both report the active safe mode and tool list.

## Data & secrets

- State (agents, skills, suggestions, approved work, shared memory, chat,
  settings) -> SQLite at `~/.petos/petos.db`.
- Connection token -> `~/.petos/token` (0600); the app reads it to authenticate.
- API keys -> macOS Keychain (via the optional `keyring` dep) or a 0600 fallback
  file. Keys are never stored in SQLite and never sent back over the socket.

## Build a real .app

```bash
./scripts/build-app.sh            # -> app/dist/PetOS.app
./scripts/build-app.sh --install  # also copies to /Applications
open app/dist/PetOS.app
```

This produces a double-clickable, ad-hoc codesigned `PetOS.app` (menu-bar
`LSUIElement` app, bundle id `com.petos.app`) with the Python sidecar vendored at
`Contents/Resources/agentd-venv` + `Contents/Resources/agentd/src`.
`SidecarManager` prefers that bundled venv, so the app runs with no dev checkout.
For public distribution, replace the ad-hoc signature with a Developer ID and
notarize.

## Roadmap (phase 2+)

- Opt-in **write/action** tools behind explicit per-suggestion approval. The
  approval path already runs a read-only managed work item; mutating executors
  remain intentionally absent.
- Per-agent model overrides and richer skill triggers.
- More workers (calendar, mail triage, project scaffolding).
