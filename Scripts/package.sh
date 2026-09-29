#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/SpaceX Live Wallpaper.app"
DIST="$ROOT/Dist"
mkdir -p "$DIST"
STAGE="$(mktemp -d /private/tmp/spacex-package.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$STAGE/SpaceX Live Wallpaper.app"
# Desktop/iCloud can reattach FinderInfo after a build; do not export that metadata.
ditto --norsrc --noextattr "$APP" "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE"
ditto -c -k --norsrc --noextattr --keepParent "$BUNDLE" "$DIST/SpaceX-Live-Wallpaper-macOS-arm64.zip"
cp "$ROOT/SpaceX-4K-Loop.mp4" "$DIST/SpaceX-4K-Loop.mp4"
cd "$DIST"
shasum -a 256 SpaceX-Live-Wallpaper-macOS-arm64.zip SpaceX-4K-Loop.mp4 > SHA256SUMS.txt
echo "Release files: $DIST"
