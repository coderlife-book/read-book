#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ReadBook.app packaging requires macOS." >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release

APP="$ROOT/dist/ReadBook.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/ReadBook" "$APP/Contents/MacOS/ReadBook"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>ReadBook</string>
  <key>CFBundleIdentifier</key><string>com.coderlife.readbook</string>
  <key>CFBundleName</key><string>ReadBook</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.1</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# SwiftPM's linker ad-hoc signs the raw executable before the .app bundle exists.
# Re-sign the completed bundle so Info.plist and resources are sealed into the
# final code signature. A Developer ID identity can replace '-' in the future.
codesign --force --sign - --timestamp=none "$APP"

printf 'Built %s\n' "$APP"
