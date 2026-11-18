#!/usr/bin/env bash
# Builds and starts a development copy. Set LOWKEY_CONFIG=/tmp/x.json to keep real settings untouched.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/Scripts/package_app.sh" "${1:-debug}"
if [[ -n "${LOWKEY_CONFIG:-}" ]]; then
  # `open` does not pass the environment; start the binary directly.
  "$ROOT/build/Lowkey.app/Contents/MacOS/Lowkey" >/dev/null 2>&1 &
else
  open "$ROOT/build/Lowkey.app"
fi
