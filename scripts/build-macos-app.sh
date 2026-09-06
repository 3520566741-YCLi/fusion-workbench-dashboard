#!/bin/bash
# Assemble a runnable "Fusion Workbench.app" bundle from the release build.
# Ad-hoc signing only — replace "-" with your Developer ID for distribution.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Fusion Workbench"
APP_DIR="dist/$APP_NAME.app"
BIN="$APP_DIR/Contents/MacOS/$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

swift build -c release

cp ".build/arm64-apple-macosx/release/FusionWorkbench" "$BIN"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Fusion Workbench</string>
    <key>CFBundleDisplayName</key><string>Fusion Workbench</string>
    <key>CFBundleIdentifier</key><string>com.fusionworkbench.dashboard</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>Fusion Workbench</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
echo "Built: $APP_DIR"
