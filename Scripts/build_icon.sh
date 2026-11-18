#!/usr/bin/env bash
# Builds Icon.icns from Assets/AppIcon.png (1024×1024) with tools included in macOS.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
MASTER="$ROOT/Assets/AppIcon.png"
OUTPUT=${1:-"$ROOT/.build/Icon.icns"}
[[ -f "$MASTER" ]] || { echo "ERROR: Assets/AppIcon.png is missing" >&2; exit 1; }
WORK=$(mktemp -d "${TMPDIR:-/tmp}/lowkey-icon.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/Icon.iconset"
mkdir -p "$ICONSET" "$(dirname "$OUTPUT")"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns "$ICONSET" --output "$OUTPUT"
