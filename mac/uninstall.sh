#!/bin/bash
# Removes the daily sky: both background jobs and everything they made, and
# puts back the wallpapers from before the first install on the desktops
# showing. macOS can't set the others from here, so any sky file a desktop
# still shows is kept (and listed) rather than pulled out from under it.
set -euo pipefail

app="$HOME/Library/Application Support/SkyWallpaper"

for label in local.sky-wallpaper local.sky-wallpaper.follow; do
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/$label.plist"
done
[ -d "$app" ] || { echo "sky wallpaper not installed"; exit 0; }

kept=()
if [ -x "$app/bin/heicpack" ]; then
    [ -f "$app/previous.txt" ] && "$app/bin/heicpack" --restore "$app/previous.txt"
    if in_use=$("$app/bin/heicpack" --in-use); then
        for f in "$app"/out/sky-*.heic; do
            grep -qxF -- "$f" <<<"$in_use" && kept+=("$f")
        done
    else
        kept=("$app"/out/sky-*.heic)  # can't tell: keep them all
    fi
fi

if [ ${#kept[@]} -eq 0 ]; then
    rm -rf "${app:?}"
    echo "sky wallpaper removed"
else
    find "$app" -mindepth 1 -maxdepth 1 ! -name out -exec rm -rf {} +
    for f in "$app"/out/*; do
        keep=no
        for k in "${kept[@]}"; do [ "$f" = "$k" ] && keep=yes; done
        [ "$keep" = yes ] || rm -f "$f"
    done
    echo "sky wallpaper removed, except files other desktops still show:"
    printf '  %s\n' "${kept[@]}"
    echo "Give those desktops another wallpaper, then delete: $app"
fi
