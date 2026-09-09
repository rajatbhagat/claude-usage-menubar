#!/bin/bash
# Builds ClaudeUsageMenuBar.app — no Xcode required, just swiftc via the
# Command Line Tools. Run this after any code change to refresh the app bundle.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="ClaudeUsageMenuBar"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"

echo "Building release binary..."
swift build -c release

echo "Assembling ${APP_BUNDLE}..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>Claude Usage</string>
    <key>CFBundleIdentifier</key>
    <string>com.rajatbhagat.claudeusagemenubar</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "Ad-hoc code signing..."
codesign --force --deep -s - "$APP_BUNDLE"

echo "Done: $(pwd)/$APP_BUNDLE"
echo "Run it with: open \"$APP_BUNDLE\""
echo "Or copy to /Applications and add it to Login Items > Open at Login for it to start automatically."
