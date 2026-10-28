#!/bin/bash
# Installs the daily sky for this Mac user. Each day, a background job
# computes sunrise and sunset for your location and, unless --no-weather,
# takes the hourly forecast from Open-Meteo: one request a day, carrying the
# date and your coordinates rounded to 0.1° (about 10 km). It renders the
# day's frames for each screen, packs them, and sets the wallpaper; macOS
# switches the frames from there.
#
#   mac/install.sh [--lat 48.2 --lon 16.4] [--no-weather] [--seed 7]
#
# Without --lat/--lon it uses your time zone's city (from zone.tab).
# mac/uninstall.sh removes it all and puts your previous wallpaper back.
set -euo pipefail
cd "$(dirname "$0")/.."

lat="" lon="" weather=yes seed=7
while [ $# -gt 0 ]; do
    case "$1" in
        --lat) lat=$2; shift 2 ;;
        --lon) lon=$2; shift 2 ;;
        --no-weather) weather=no; shift ;;
        --seed) seed=$2; shift 2 ;;
        *) echo "usage: mac/install.sh [--lat DEG --lon DEG] [--no-weather] [--seed N]" >&2; exit 2 ;;
    esac
done

if [ -z "$lat" ] || [ -z "$lon" ]; then
    tz=$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')
    coords=$(awk -v tz="$tz" '$3 == tz { print $2 }' /usr/share/zoneinfo/zone.tab)
    [ -n "$coords" ] || { echo "no coordinates for time zone $tz; pass --lat and --lon" >&2; exit 1; }
    # ISO 6709, e.g. +4813+01620: ±DDMM[SS] then ±DDDMM[SS]; kept to 0.1°.
    degrees() {
        awk -v s="$1" -v n="$2" 'BEGIN {
            d = substr(s, 2); v = substr(d, 1, n) + substr(d, n + 1, 2) / 60 + (length(d) > n + 2 ? substr(d, n + 3, 2) / 3600 : 0)
            printf "%.1f", (substr(s, 1, 1) == "-" ? -v : v) }'
    }
    lat=$(degrees "$(sed -E 's/^([+-][0-9]+)[+-].*/\1/' <<<"$coords")" 2)
    lon=$(degrees "$(sed -E 's/^[+-][0-9]+([+-][0-9]+)$/\1/' <<<"$coords")" 3)
    echo "location from time zone $tz: $lat, $lon"
fi

app="$HOME/Library/Application Support/SkyWallpaper"
agent="$HOME/Library/LaunchAgents/local.sky-wallpaper.plist"

swift build -c release --quiet
mkdir -p "$app/bin"
# Copies, so rebuilding the repo never changes what the job runs.
cp .build/release/wallframes .build/release/heicpack "$app/bin/"
cp mac/daily.sh "$app/daily.sh"
printf 'LAT=%s\nLON=%s\nWEATHER=%s\nSEED=%s\n' "$lat" "$lon" "$weather" "$seed" > "$app/config"
[ -f "$app/previous.txt" ] || "$app/bin/heicpack" --save "$app/previous.txt"

# Background process type: low priority, efficiency cores.
mkdir -p "$(dirname "$agent")"
cat > "$agent" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>local.sky-wallpaper</string>
    <key>ProgramArguments</key><array><string>/bin/bash</string><string>$app/daily.sh</string></array>
    <key>StartCalendarInterval</key><dict><key>Hour</key><integer>0</integer><key>Minute</key><integer>5</integer></dict>
    <key>RunAtLoad</key><true/>
    <key>ProcessType</key><string>Background</string>
    <key>StandardOutPath</key><string>$app/daily.log</string>
    <key>StandardErrorPath</key><string>$app/daily.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/local.sky-wallpaper" 2>/dev/null || true
/bin/bash "$app/daily.sh" --force   # now, in the foreground, so errors show here
launchctl bootstrap "gui/$(id -u)" "$agent"
echo "installed: daily at 00:05 (and at login, and on wake if missed); log: $app/daily.log"
