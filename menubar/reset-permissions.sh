#!/bin/bash
# Clears The Long Run's privacy decisions so macOS forgets any stale or duplicate
# entries from older/ad-hoc builds. Works by bundle ID — you do NOT need to know
# where the app is installed. After running, reopen the app and grant once.
echo "Clearing TheLongRun privacy entries (by bundle ID)…"
tccutil reset Accessibility com.thelongrun.menubar 2>/dev/null || true
tccutil reset ListenEvent  com.thelongrun.menubar 2>/dev/null || true
echo "Done."
echo "Now reopen The Long Run and grant Input Monitoring + Accessibility once when asked."
