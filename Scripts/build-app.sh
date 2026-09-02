#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ReadBook.app packaging requires macOS." >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_VERSION="${READBOOK_VERSION:-0.2.3}"
APP_BUILD="${READBOOK_BUILD:-15}"

if [[ "${READBOOK_SKIP_BUILD:-0}" == "1" ]]; then
  if [[ ! -x "$ROOT/.build/release/ReadBook" ]]; then
    echo "READBOOK_SKIP_BUILD=1 requires an existing .build/release/ReadBook executable." >&2
    exit 1
  fi
else
  swift build -c release
fi

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

# MLX SwiftPM CLI 构建不产出 metallib，但运行时要求与可执行文件同目录。
# 固定资源来自 DesignAssets/MLX/README.md 中锁定的 mlx-swift revision。
if [[ ! -f "$ROOT/DesignAssets/MLX/mlx.metallib" ]]; then
  echo "Missing DesignAssets/MLX/mlx.metallib; MLX audio would fail to load." >&2
  exit 1
fi
cp "$ROOT/DesignAssets/MLX/mlx.metallib" "$APP/Contents/MacOS/mlx.metallib"

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
# Re-sign the completed bundle so Info.plist, icon, resources, and the colocated
# MLX Metal kernel library (a Mach-O subcomponent) are all sealed.
codesign --force --deep --sign - --timestamp=none "$APP"

printf 'Built %s (v%s build %s)\n' "$APP" "$APP_VERSION" "$APP_BUILD"
