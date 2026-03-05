#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="DimmerFlow"
APP_DIR="$HOME/Desktop/${APP_NAME}.app"
LEGACY_SETUP_DIR="$ROOT_DIR/setup"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
swift build -c release

BIN_SRC="$ROOT_DIR/.build/release/DimmerFlow"

rm -rf "$LEGACY_SETUP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

cp "$BIN_SRC" "$MACOS_DIR/DimmerFlow"
chmod +x "$MACOS_DIR/DimmerFlow"

echo "Generating app icon..."
ICONSET_DIR=$(swift "$ROOT_DIR/scripts/generate_icon.swift")
iconutil -c icns "$ICONSET_DIR" -o "$RES_DIR/AppIcon.icns"
rm -rf "$ICONSET_DIR"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>DimmerFlow</string>
    <key>CFBundleDisplayName</key>
    <string>DimmerFlow</string>
    <key>CFBundleExecutable</key>
    <string>DimmerFlow</string>
    <key>CFBundleIdentifier</key>
    <string>com.dogu.DimmerFlow</string>
    <key>CFBundleVersion</key>
    <string>1.1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"

echo "Packaged app: $APP_DIR"
