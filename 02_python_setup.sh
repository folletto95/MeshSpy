#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(dirname "$(realpath "$0")")"
cd "$PROJECT_ROOT"

echo "▶️  (Re)creo virtual‑env con dipendenze aggiornate…"
rm -rf backend/.venv
python3 -m venv --upgrade-deps backend/.venv

source backend/.venv/bin/activate
echo "▶️  pip version: $(pip --version)"

echo "▶️  Installo requirements..."
pip install -r requirements.txt
pip install -r requirements-dev.txt

echo "✅  Ambiente Python pronto. Attivalo con:"
echo "   source backend/.venv/bin/activate"
