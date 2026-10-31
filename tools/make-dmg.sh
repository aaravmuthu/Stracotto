#!/bin/zsh
# Builds Stracotto.dmg: the app, an Applications shortcut, and a laid-out Finder window with a drag-to-install
# background. Re-runnable. Usage: tools/make-dmg.sh [path/to/Stracotto.app] [output.dmg] [--notarized]
# The first run asks permission for the terminal to control Finder (it positions the icons); allow it once.
set -euo pipefail
cd "${0:A:h}/.."

APP=${1:-build/Build/Products/Release/Stracotto.app}
OUT=${2:-Stracotto.dmg}
NOTARIZED=""; [[ " $* " == *" --notarized "* ]] && NOTARIZED="--notarized"
VOL="Stracotto"
WORK=$(mktemp -d)
trap 'hdiutil detach "/Volumes/$VOL" -force >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

[[ -d $APP ]] || { echo "No app at $APP (build it first)"; exit 1 }

echo "→ Background"
swiftc -O tools/dmg-background.swift -o "$WORK/bg" 2>&1 | grep -v warning || true
"$WORK/bg" "$WORK/art" $NOTARIZED
tiffutil -cathidpicheck "$WORK/art/background.png" "$WORK/art/background@2x.png" -out "$WORK/background.tiff"

echo "→ Disk image"
hdiutil detach "/Volumes/$VOL" -force >/dev/null 2>&1 || true
hdiutil create -size 60m -fs HFS+ -volname "$VOL" -ov "$WORK/rw.dmg" >/dev/null
hdiutil attach "$WORK/rw.dmg" -mountpoint "/Volumes/$VOL" -nobrowse -noverify >/dev/null
ditto "$APP" "/Volumes/$VOL/Stracotto.app"
ln -s /Applications "/Volumes/$VOL/Applications"
mkdir "/Volumes/$VOL/.background"
cp "$WORK/background.tiff" "/Volumes/$VOL/.background/background.tiff"

echo "→ Laying out the window (Finder)"
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOL"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 550}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 128
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "Stracotto.app" of container window to {180, 190}
        set position of item "Applications" of container window to {480, 190}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT
sync; sleep 1
[[ -f "/Volumes/$VOL/.DS_Store" ]] || { echo "Finder didn't write the layout (.DS_Store missing)"; exit 1 }
chflags hidden "/Volumes/$VOL/.background" 2>/dev/null || true
hdiutil detach "/Volumes/$VOL" >/dev/null

echo "→ Compressing"
rm -f "$OUT"
hdiutil convert "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
echo "✓ $OUT ($(du -h "$OUT" | cut -f1))"
