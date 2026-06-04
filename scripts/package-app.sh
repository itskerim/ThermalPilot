#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
APP_DIR="$ROOT/build/Thermal Pilot.app"
EXECUTABLE="$ROOT/.build/arm64-apple-macosx/$CONFIGURATION/FanUsage"
ICONSET_DIR="$ROOT/build/AppIcon.iconset"
ICON_FILE="$APP_DIR/Contents/Resources/AppIcon.icns"
DOWNLOAD_ZIP="$ROOT/build/ThermalPilot-0.1.0.zip"
DMG_STAGING_DIR="$ROOT/build/dmg-staging"
DOWNLOAD_DMG="$ROOT/build/ThermalPilot-0.1.0.dmg"
DMG_BACKGROUND="$ROOT/build/dmg-background.png"
DMG_RW="$ROOT/build/ThermalPilot-0.1.0-rw.dmg"

cd "$ROOT"
mkdir -p "$ROOT/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache"
swift build -c "$CONFIGURATION"

detach_existing_thermal_pilot_volumes() {
    while IFS= read -r device; do
        hdiutil detach "$device" >/dev/null 2>&1 || true
    done < <(hdiutil info | awk '/\/Volumes\/Thermal Pilot/ { print $1 }')
}

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/FanUsage"
swift "$ROOT/scripts/generate-app-icon.swift" "$ICONSET_DIR" "$ROOT/assets/AppIcon.png"
iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>FanUsage</string>
    <key>CFBundleIdentifier</key>
    <string>local.thermalpilot.app</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Thermal Pilot</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"
rm -f "$DOWNLOAD_ZIP"
ditto -c -k --keepParent --norsrc "$APP_DIR" "$DOWNLOAD_ZIP"
rm -rf "$DMG_STAGING_DIR" "$DOWNLOAD_DMG"
mkdir -p "$DMG_STAGING_DIR"
ditto --norsrc "$APP_DIR" "$DMG_STAGING_DIR/Thermal Pilot.app"
ln -s /Applications "$DMG_STAGING_DIR/Applications"
swift "$ROOT/scripts/generate-dmg-background.swift" "$DMG_BACKGROUND" "$ROOT/assets/dmg-background-source.png"
mkdir -p "$DMG_STAGING_DIR/.background"
cp "$DMG_BACKGROUND" "$DMG_STAGING_DIR/.background/dmg-background.png"
chflags hidden "$DMG_STAGING_DIR/.background"
rm -f "$DMG_RW"
detach_existing_thermal_pilot_volumes
hdiutil create -volname "Thermal Pilot" -srcfolder "$DMG_STAGING_DIR" -ov -format UDRW "$DMG_RW"
ATTACH_OUTPUT="$(hdiutil attach "$DMG_RW" -readwrite -noverify -noautoopen)"
DEVICE="$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/Apple_HFS|Apple_APFS/ { print $1; exit }')"
VOLUME="$(printf '%s\n' "$ATTACH_OUTPUT" | sed -n 's|^/dev/[^[:space:]]*[[:space:]].*[[:space:]]\(/Volumes/.*\)$|\1|p' | tail -n 1)"
if [[ -z "$VOLUME" ]]; then
    VOLUME="/Volumes/Thermal Pilot"
fi
detach_dmg() {
    local target="$1"
    for _ in 1 2 3 4 5; do
        if hdiutil detach "$target"; then
            return 0
        fi
        sleep 1
    done
    hdiutil detach -force "$target"
}
cleanup_dmg_mount() {
    hdiutil detach "$VOLUME" >/dev/null 2>&1 || hdiutil detach "$DEVICE" >/dev/null 2>&1 || true
}
trap cleanup_dmg_mount EXIT
sleep 2
osascript - "$VOLUME" <<'APPLESCRIPT'
on run argv
    set volumePath to item 1 of argv
    set bgPic to POSIX file (volumePath & "/.background/dmg-background.png") as alias

    tell application "Finder"
        tell disk "Thermal Pilot"
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            try
                set pathbar visible of container window to false
            end try
            set the bounds of container window to {80, 80, 1080, 800}
            set theViewOptions to icon view options of container window
            set arrangement of theViewOptions to not arranged
            set icon size of theViewOptions to 192
            set text size of theViewOptions to 16
            set label position of theViewOptions to bottom
            set background picture of theViewOptions to bgPic
            set position of item "Thermal Pilot.app" to {320, 335}
            set position of item "Applications" to {720, 335}
            update without registering applications
            delay 1
            set the bounds of container window to {80, 80, 1080, 800}
            close
        end tell
    end tell
end run
APPLESCRIPT
sync
detach_dmg "$VOLUME"
trap - EXIT
sleep 2
for _ in 1 2 3 4 5; do
    rm -f "$DOWNLOAD_DMG"
    if hdiutil convert "$DMG_RW" -format UDZO -imagekey zlib-level=9 -o "$DOWNLOAD_DMG"; then
        break
    fi
    sleep 2
done
if [[ ! -f "$DOWNLOAD_DMG" ]]; then
    echo "Failed to create $DOWNLOAD_DMG" >&2
    exit 1
fi
rm -f "$DMG_RW"
echo "$APP_DIR"
echo "$DOWNLOAD_ZIP"
echo "$DOWNLOAD_DMG"
