#!/usr/bin/env bash
# Run the PetOS agent runtime (sidecar) on its own for development.
# Creates a venv on first run. The macOS app can also spawn this automatically.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/agentd"

if [ ! -d .venv ]; then
  echo "Creating venv..."
  python3 -m venv .venv
  ./.venv/bin/pip install -q -e .
fi

echo "Starting agentd on ws://127.0.0.1:8765/ws"
exec ./.venv/bin/python -m agentd
