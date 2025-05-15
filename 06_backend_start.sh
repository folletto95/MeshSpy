#!/usr/bin/env bash
set -euo pipefail
ROOT="$(dirname "$(realpath "$0")")"

# attiva la venv
source "$ROOT/backend/.venv/bin/activate"

echo "▶️  Avvio backend FastAPI su http://localhost:8000 ..."
# Path modulare completo; esecuzione dalla root → il reloader non perde PYTHONPATH
uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000 &
echo "ℹ️  Backend PID: $!"
