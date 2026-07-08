#!/usr/bin/env bash
# Build and run the PetOS macOS app. It will auto-spawn the Python sidecar using
# the agentd venv (created by scripts/dev-agentd.sh or on demand here).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Ensure the sidecar venv exists so the app can spawn it.
if [ ! -d "$ROOT/agentd/.venv" ]; then
  (cd "$ROOT/agentd" && python3 -m venv .venv && ./.venv/bin/pip install -q -e .)
fi

export PETOS_REPO="$ROOT"
export PETOS_PYTHON="$ROOT/agentd/.venv/bin/python"

cd "$ROOT/app"
echo "Building PetOS..."
swift build
echo "Launching PetOS (menu-bar app). Click the pawprint in the menu bar to open the Control Center."
exec ./.build/debug/PetOS
