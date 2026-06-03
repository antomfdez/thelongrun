#!/bin/bash
# Builds The Long Run (stable-signed) and installs it to /Applications, leaving
# exactly ONE copy of the app. Because every build uses the same stable identity,
# you grant Input Monitoring + Accessibility once and it sticks — across rebuilds
# and regardless of where the app lives.
set -e
cd "$(dirname "$0")"

DEST="/Applications/TheLongRun.app"

# Build (build.sh creates/uses the stable self-signed identity automatically).
./build.sh

# Install to /Applications (stable path → no Gatekeeper translocation).
echo "Installing to $DEST…"
rm -rf "$DEST"
ditto TheLongRun.app "$DEST"
xattr -cr "$DEST"

# Remove the local build copy so there's only one app to grant / open.
rm -rf TheLongRun.app

echo
echo "✓ Installed $DEST"
echo
echo "Next:"
echo "  1. If macOS already shows a TheLongRun entry from an older build, run:"
echo "       ./reset-permissions.sh"
echo "  2. open \"$DEST\""
echo "  3. Grant TheLongRun in Privacy & Security ▸ Input Monitoring AND Accessibility."
echo "     You only do this once — future ./install.sh runs keep the grant."
