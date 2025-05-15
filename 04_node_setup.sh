#!/usr/bin/env bash
set -euo pipefail

# ▶️  Aggiunge il repo ufficiale NodeSource e installa Node 20 LTS + npm
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

echo "✅  Node $(node -v) e npm $(npm -v) installati."
