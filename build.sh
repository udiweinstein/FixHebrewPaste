#!/bin/bash
# בונה את FixHebrewPaste.app מתוך main.swift (דורש Xcode Command Line Tools:  xcode-select --install)
# הבינארי הוא Universal (Apple Silicon + Intel) כשאפשר.
#   מספר הגרסה נלקח מהקובץ VERSION (אפשר לעקוף: VERSION=1.2.0 ./build.sh)
set -e
cd "$(dirname "$0")"

VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION 2>/dev/null || echo 1.0.0)}"
VERSION="${VERSION#v}"
APP="FixHebrewPaste.app"
BIN="FixHebrewPaste"

rm -rf "$APP" build
mkdir -p "$APP/Contents/MacOS" build

built=()
for arch in arm64 x86_64; do
    if swiftc -O -target "$arch-apple-macos11.0" main.swift -o "build/$BIN-$arch" \
        -framework Cocoa -framework Carbon -framework ServiceManagement -framework Vision; then
        built+=("build/$BIN-$arch")
    else
        echo "⚠️  הבנייה ל-$arch נכשלה — ממשיך בלעדיה"
    fi
done
[ ${#built[@]} -gt 0 ] || { echo "❌ הבנייה נכשלה"; exit 1; }
lipo -create "${built[@]}" -output "$APP/Contents/MacOS/$BIN"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>FixHebrewPaste</string>
    <key>CFBundleDisplayName</key><string>FixHebrewPaste</string>
    <key>CFBundleIdentifier</key><string>local.fixhebrewpaste</string>
    <key>CFBundleExecutable</key><string>$BIN</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "✓ נבנה: $(pwd)/$APP  (גרסה $VERSION, $(lipo -archs "$APP/Contents/MacOS/$BIN"))"
echo "  להפעלה:  open $APP     (או גרור לתיקיית Applications)"
