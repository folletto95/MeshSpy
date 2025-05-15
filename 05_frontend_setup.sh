#!/usr/bin/env bash
set -euo pipefail
ROOT="$(dirname "$(realpath "$0")")"
rsync -a "$ROOT/frontend_files/" "$ROOT/meshspy-ui/"
cd "$ROOT/meshspy-ui"
[ -f src/index.css ] || cat > src/index.css <<'TAILWIND'
@tailwind base;
@tailwind components;
@tailwind utilities;
TAILWIND
npm install
VITE_API=http://192.168.10.89:8000\n
npm run dev -- --host 0.0.0.0 --port 5173
