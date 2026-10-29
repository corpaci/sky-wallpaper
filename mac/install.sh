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
follower="$HOME/Library/LaunchAgents/local.sky-wallpaper.follow.plist"

swift build -c release --quiet
# Stop both jobs before their files are replaced.
for label in local.sky-wallpaper local.sky-wallpaper.follow; do
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
done
mkdir -p "$app/bin"
# A new renderer or new settings mean today's sky is rendered again.
config=$(printf 'LAT=%s\nLON=%s\nWEATHER=%s\nSEED=%s' "$lat" "$lon" "$weather" "$seed")
changed=yes
cmp -s .build/release/wallframes "$app/bin/wallframes" && [ -f "$app/config" ] \
    && [ "$(cat "$app/config")" = "$config" ] && changed=no
# Copies, so rebuilding the repo never changes what the jobs run.
cp .build/release/wallframes .build/release/heicpack "$app/bin/"
cp mac/daily.sh "$app/daily.sh"
printf '%s\n' "$config" > "$app/config"
[ -f "$app/previous.txt" ] || "$app/bin/heicpack" --save "$app/previous.txt"

# The daily render. Background process type: low priority, efficiency cores.
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

# The follower: macOS only lets the showing Space be set, so this idle
# helper puts today's sky on each desktop as it comes into view. No timers;
# it sleeps until you switch Spaces, wake the Mac or change screens.
cat > "$follower" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>local.sky-wallpaper.follow</string>
    <key>ProgramArguments</key><array><string>$app/bin/heicpack</string><string>--follow</string><string>$app/out</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>$app/follow.log</string>
    <key>StandardErrorPath</key><string>$app/follow.log</string>
</dict>
</plist>
EOF

# Now, in the foreground, so errors show here. Re-render only if the settings changed.
if [ "$changed" = yes ]; then /bin/bash "$app/daily.sh" --force; else /bin/bash "$app/daily.sh"; fi
launchctl bootstrap "gui/$(id -u)" "$agent"
launchctl bootstrap "gui/$(id -u)" "$follower"
echo "installed: daily render at 00:05 (and at login, and on wake if missed), plus the desktop follower"
echo "logs: $app/daily.log, $app/follow.log"
