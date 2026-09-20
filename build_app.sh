#!/bin/bash
# Build "Calendar.app" — an LSUIElement (no Dock) menu-bar calendar.
# Mirrors the build form of the sibling prompt-qy project.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Calendar"
APP="$ROOT/dist/$APP_NAME.app"
ICONSET="$ROOT/dist/icon.iconset"
VERSION="$(cat "$ROOT/VERSION")"

echo "==> Cleaning $APP"
rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

echo "==> Generating app icon (iconset → icns)"
mkdir -p "$ICONSET"
swift "$ROOT/generate_icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "==> Compiling Swift binary"
DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-11.0}"
swiftc -O -target "$(uname -m)-apple-macos${DEPLOYMENT_TARGET}" \
    -framework EventKit \
    -o "$APP/Contents/MacOS/Calendar" "$ROOT/calendar.swift"

echo "==> Writing Info.plist (version $VERSION)"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Calendar</string>
    <key>CFBundleDisplayName</key>     <string>Calendar</string>
    <key>CFBundleIdentifier</key>      <string>io.github.calendar</string>
    <key>CFBundleExecutable</key>      <string>Calendar</string>
    <key>CFBundleVersion</key>         <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key> <string>${VERSION}</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>CFBundleIconName</key>        <string>AppIcon</string>
    <key>LSUIElement</key>             <true/>
    <key>LSApplicationCategoryType</key> <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>  <string>11.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSHumanReadableCopyright</key> <string>Based on Emil Kreutzman's Calendar. MIT License.</string>
    <key>NSRemindersUsageDescription</key>
    <string>用于在日历上显示未完成的提醒事项。</string>
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>用于在日历上显示未完成的提醒事项。</string>
</dict>
</plist>
PLIST

CERT_NAME="Calendar Dev"
DEV_KEYCHAIN="$HOME/Library/Keychains/calendar-dev.keychain-db"
if security find-certificate -c "$CERT_NAME" "$DEV_KEYCHAIN" >/dev/null 2>&1; then
    echo "==> Code signing with stable identity: $CERT_NAME"
    security unlock-keychain -p "calendar-dev" "$DEV_KEYCHAIN" 2>/dev/null || true
    codesign --force --keychain "$DEV_KEYCHAIN" --sign "$CERT_NAME" "$APP"
else
    echo "==> Code signing (ad-hoc; run ./setup_signing.sh for a stable identity)"
    codesign --force --sign - "$APP"
fi
codesign -dvv "$APP" 2>&1 | grep -E "Identifier|Authority|Signature" || true

echo "==> Done: $APP"
echo
echo "Run with:    open \"$APP\""
echo "Install via: cp -R \"$APP\" /Applications/"
