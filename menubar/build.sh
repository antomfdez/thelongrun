#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="TheLongRun.app"
BIN="$APP/Contents/MacOS/TheLongRun"
RES="$APP/Contents/Resources"
# Default to a STABLE self-signed identity so permission grants persist across
# rebuilds and copies. Override with SIGN_ID=- for a throwaway ad-hoc build.
if [ -z "${SIGN_ID:-}" ]; then
    SIGN_ID="$("$(dirname "$0")/ensure-cert.sh")"
fi

echo "Compiling…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$RES"

swiftc -O TheLongRun.swift -o "$BIN" -framework Cocoa -framework CoreGraphics

# App icon (best-effort; the app still works without it).
HAS_ICON=""
if swiftc -O makeicon.swift -o /tmp/tlr-makeicon 2>/dev/null && /tmp/tlr-makeicon >/dev/null 2>&1; then
    if iconutil -c icns AppIcon.iconset -o "$RES/AppIcon.icns" 2>/dev/null; then
        HAS_ICON="    <key>CFBundleIconFile</key><string>AppIcon</string>"
    fi
    rm -rf AppIcon.iconset
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>TheLongRun</string>
    <key>CFBundleDisplayName</key><string>The Long Run</string>
    <key>CFBundleIdentifier</key><string>com.thelongrun.menubar</string>
    <key>CFBundleVersion</key><string>1.1</string>
    <key>CFBundleShortVersionString</key><string>1.1</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>TheLongRun</string>
${HAS_ICON}
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>LSUIElement</key><true/>
    <key>NSInputMonitoringUsageDescription</key>
    <string>Reads your chosen hotkeys to toggle auto-running.</string>
</dict>
</plist>
PLIST

xattr -cr "$APP"                       # strip extended attrs that break signing
if ! codesign --force --sign "$SIGN_ID" --identifier com.thelongrun.menubar "$APP" 2>/tmp/tlr-codesign.err; then
    echo "⚠️  signing with '$SIGN_ID' failed:" >&2; cat /tmp/tlr-codesign.err >&2
    echo "    falling back to ad-hoc (permissions won't persist across rebuilds)." >&2
    codesign --force --sign - "$APP" || true
    SIGN_ID="-"
fi

echo "Built $APP  (signed: $SIGN_ID)"
echo "Open with:  open $APP"
