#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if bash scripts/build.sh --dmg; then
    open "output/$(uname -m)"
else
    echo "Build failed. Read the error above; see Mac/README.md for setup."
fi
read -r -p "Press Return to close…"
