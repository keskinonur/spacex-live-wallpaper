#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FINAL="$ROOT/SpaceX Live Wallpaper.app"
# Sign outside Desktop/iCloud so File Provider cannot race the signer by
# reattaching FinderInfo while the bundle is being assembled.
STAGE="$(mktemp -d /private/tmp/spacex-build.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/SpaceX Live Wallpaper.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/Build/ModuleCache"
test -s "$ROOT/SpaceX-4K-Loop.mp4" || { echo 'Run Scripts/render.sh first.' >&2; exit 1; }
xcrun swiftc -swift-version 5 -O -module-cache-path "$ROOT/Build/ModuleCache" \
  -target arm64-apple-macosx13.0 -framework AppKit -framework AVFoundation -framework AVKit \
  "$ROOT/Sources/main.swift" -o "$APP/Contents/MacOS/SpaceXWallpaper"
cp "$ROOT/SpaceX-4K-Loop.mp4" "$APP/Contents/Resources/SpaceX-4K-Loop.mp4"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SpaceXWallpaper</string>
<key>CFBundleIdentifier</key><string>local.onur.spacex-live-wallpaper</string>
<key>CFBundleName</key><string>SpaceX Live Wallpaper</string>
<key>CFBundleDisplayName</key><string>SpaceX Live Wallpaper</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Photography credited to SpaceX. Video provenance unverified. See REFERENCES.md.</string>
</dict></plist>
PLIST
cp "$ROOT/REFERENCES.md" "$APP/Contents/Resources/REFERENCES.md"
# Finder/iCloud may attach FinderInfo to a new .app on Desktop.
# Remove only signing-incompatible metadata from this generated bundle.
xattr -dr com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$APP" 2>/dev/null || true
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
ditto --noextattr --norsrc "$APP" "$FINAL"
xattr -dr com.apple.FinderInfo "$FINAL" 2>/dev/null || true
codesign --verify --deep --strict "$FINAL"
echo "Built: $FINAL"
