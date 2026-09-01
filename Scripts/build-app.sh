#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ReadBook.app packaging requires macOS." >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_VERSION="${READBOOK_VERSION:-0.1.10}"
APP_BUILD="${READBOOK_BUILD:-11}"

swift build -c release

BRAND_DIR="$ROOT/dist/branding"
rm -rf "$BRAND_DIR"
mkdir -p "$BRAND_DIR"
xcrun swift "$ROOT/Scripts/render-branding.swift" "$BRAND_DIR"
iconutil -c icns "$BRAND_DIR/ReadBook.iconset" -o "$BRAND_DIR/ReadBook.icns"

APP="$ROOT/dist/ReadBook.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Licenses/Tabler"
cp "$ROOT/.build/release/ReadBook" "$APP/Contents/MacOS/ReadBook"
cp "$BRAND_DIR/ReadBook.icns" "$APP/Contents/Resources/ReadBook.icns"
cp "$BRAND_DIR/ReadBookMenuTemplate.png" "$APP/Contents/Resources/ReadBookMenuTemplate.png"
cp "$ROOT/DesignAssets/Tabler/LICENSE" "$APP/Contents/Resources/Licenses/Tabler/LICENSE"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>ReadBook</string>
  <key>CFBundleIdentifier</key><string>com.coderlife.readbook</string>
  <key>CFBundleName</key><string>ReadBook</string>
  <key>CFBundleDisplayName</key><string>ReadBook</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${APP_VERSION}</string>
  <key>CFBundleVersion</key><string>${APP_BUILD}</string>
  <key>CFBundleIconFile</key><string>ReadBook.icns</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# SwiftPM's linker ad-hoc signs the raw executable before the .app bundle exists.
# Re-sign the completed bundle so Info.plist, icon, and resources are sealed.
codesign --force --sign - --timestamp=none "$APP"

printf 'Built %s (v%s build %s)\n' "$APP" "$APP_VERSION" "$APP_BUILD"
