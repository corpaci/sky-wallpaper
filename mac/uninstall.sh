#!/bin/bash
# Removes the daily sky: the background job and everything it made, and puts
# back the wallpapers from before the first install.
set -euo pipefail

app="$HOME/Library/Application Support/SkyWallpaper"
agent="$HOME/Library/LaunchAgents/local.sky-wallpaper.plist"

launchctl bootout "gui/$(id -u)/local.sky-wallpaper" 2>/dev/null || true
rm -f "$agent"
if [ -x "$app/bin/heicpack" ] && [ -f "$app/previous.txt" ]; then
    "$app/bin/heicpack" --restore "$app/previous.txt"
fi
rm -rf "${app:?}"
echo "sky wallpaper removed"
