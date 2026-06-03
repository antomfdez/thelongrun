#!/bin/bash
# Builds The Long Run (stable-signed) and packages it into a distributable .dmg
# with a drag-to-Applications layout.
set -e
cd "$(dirname "$0")"

VERSION="1.1"
VOL="The Long Run"
APP="TheLongRun.app"
DMG="TheLongRun-$VERSION.dmg"

# 1) Fresh, stable-signed build.
./build.sh

# 2) Stage the app + an Applications symlink (so users drag-install).
STAGE="$(mktemp -d)"
ditto "$APP" "$STAGE/$APP"
ln -s /Applications "$STAGE/Applications"
xattr -cr "$STAGE/$APP"

# 3) Build a compressed DMG.
rm -f "$DMG"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "✓ Built $DMG"
echo "  Share it. To use: open the .dmg, drag TheLongRun to Applications,"
echo "  then grant Input Monitoring + Accessibility once on first launch."
