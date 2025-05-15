#!/usr/bin/env bash
set -euo pipefail

echo "▶️  Aggiornamento lista pacchetti…"
sudo apt-get update -y

echo "▶️  Installo pacchetti base (Python, venv, Git)…"
sudo apt-get install -y \
  python3 \
  python3-venv \
  python3-pip \
  build-essential \
  git

echo "✅  Sistema pronto con $(python3 --version)."
