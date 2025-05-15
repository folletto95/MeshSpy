#!/usr/bin/env bash
set -euo pipefail

source backend/.venv/bin/activate

echo "▶️  Lancio pytest…"
export PYTHONPATH="$PWD"
pytest -q

echo "✅  Tutti i test sono passati."
