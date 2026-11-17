#!/bin/bash
# Installs the daily sky for this Mac user. Each day, a background job
# computes sunrise and sunset for your location and, unless --no-weather,
# takes the hourly forecast from Open-Meteo: one request a day, carrying the
# date and your coordinates rounded to 0.1° (about 10 km). It renders the
# day's frames for each screen, packs them, and sets the wallpaper; macOS
# switches the frames from there.
#
#   mac/install.sh [--lat 48.2 --lon 16.4] [--no-weather] [--seed 7]
#                  [--not-on-battery | --in-low-power] [--extra WORD]...
#
# Without --lat/--lon it uses your time zone's city (from zone.tab).
# Each new day renders on battery too, but not in Low Power Mode, unless
# --not-on-battery or --in-low-power say otherwise; when it doesn't, the
# last day's sky stays up until the Mac is plugged in (or Low Power Mode
# goes off). Run in a terminal, it asks about those, and last for any extra
# arguments: secret words that change how the sky behaves. Which words there
# are isn't written down; the code keeps only their hashes.
# mac/uninstall.sh removes it all and puts your previous wallpaper back.
set -euo pipefail
cd "$(dirname "$0")/.."

lat="" lon="" weather=yes seed=7 battery=yes saver=no power_asked=no extras=() asked=no
while [ $# -gt 0 ]; do
    case "$1" in
        --lat) lat=$2; shift 2 ;;
        --lon) lon=$2; shift 2 ;;
        --no-weather) weather=no; shift ;;
        --seed) seed=$2; shift 2 ;;
        --not-on-battery) battery=no saver=no power_asked=yes; shift ;;
        --in-low-power) battery=yes saver=yes power_asked=yes; shift ;;
        --extra) extras+=("$2"); asked=yes; shift 2 ;;
        *) echo "usage: mac/install.sh [--lat DEG --lon DEG] [--no-weather] [--seed N] [--not-on-battery | --in-low-power] [--extra WORD]..." >&2; exit 2 ;;
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

# Rendering a day keeps the CPU busy for a minute or so.
if [ "$power_asked" = no ] && [ -t 0 ]; then
    read -r -p "Render each new day on battery too? If not, the last one stays up until you plug in. [Y/n] " answer
    if [[ "$answer" =~ ^[nN] ]]; then
        battery=no
    else
        read -r -p "Even in Low Power Mode? [y/N] " answer
        if [[ "$answer" =~ ^[yY] ]]; then saver=yes; fi
    fi
fi

# Extra arguments: the renderer knows them only by their hashes, so it checks them.
known_extras() {
    local args=() w
    for w in "$@"; do args+=(--extra "$w"); done
    .build/release/wallframes --dry-run "${args[@]}" >/dev/null 2>&1
}
if [ ${#extras[@]} -gt 0 ] && ! known_extras "${extras[@]}"; then
    echo "unknown --extra argument" >&2; exit 2
fi
if [ "$asked" = no ] && [ -t 0 ]; then
    while true; do
        read -r -p "Any extra arguments? (Enter to skip) " answer
        read -r -a words <<<"$answer"
        [ ${#words[@]} -gt 0 ] || break
        if known_extras "${words[@]}"; then extras=("${words[@]}"); echo "Got it."; break; fi
        echo "Not something this knows. Try again, or press Enter to skip."
    done
fi
# Stop both jobs before their files are replaced.
for label in local.sky-wallpaper local.sky-wallpaper.follow; do
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
done
mkdir -p "$app/bin"
# A new renderer or new settings mean today's sky is rendered again.
config=$(printf 'LAT=%s\nLON=%s\nWEATHER=%s\nSEED=%s\nBATTERY=%s\nSAVER=%s\nEXTRAS="%s"' \
    "$lat" "$lon" "$weather" "$seed" "$battery" "$saver" "${extras[*]:-}")
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
