#!/bin/bash
# בונה את FixHebrewPaste.app מתוך main.swift (דורש Xcode Command Line Tools:  xcode-select --install)
set -e
cd "$(dirname "$0")"

APP="FixHebrewPaste.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O main.swift -o "$APP/Contents/MacOS/FixHebrewPaste" -framework Cocoa -framework Carbon

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>FixHebrewPaste</string>
    <key>CFBundleDisplayName</key><string>FixHebrewPaste</string>
    <key>CFBundleIdentifier</key><string>local.fixhebrewpaste</string>
    <key>CFBundleExecutable</key><string>FixHebrewPaste</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "✓ נבנה: $(pwd)/$APP"
echo "  להפעלה:  open $APP     (או גרור לתיקיית Applications)"
