#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICONSET="$ROOT/Build/AppIcon.iconset"
mkdir -p "$ICONSET" "$ROOT/Build/ModuleCache"
xcrun swift -module-cache-path "$ROOT/Build/ModuleCache" "$ROOT/Scripts/render-icon.swift" "$ROOT/Resources/AppIcon.svg" "$ROOT/Resources/AppIcon.png"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" "$ROOT/Resources/AppIcon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "$DOUBLE" "$DOUBLE" "$ROOT/Resources/AppIcon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
