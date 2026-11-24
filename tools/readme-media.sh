#!/usr/bin/env bash
# Renders the README's animations into docs/: day.webp, seasons.webp,
# weather.webp and moon.webp, each a looping crossfade of real frames.
#
#   tools/readme-media.sh            # macOS (Swift) or Windows Git Bash (C#)
#
# Needs ffmpeg built with libwebp. Takes a few minutes, mostly encoding.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The renderer: Swift on macOS, the C# one (compiled with Windows' own csc) elsewhere.
if [[ "$(uname)" == Darwin ]]; then
    swift build -c release --quiet
    render() { .build/release/wallframes "$@" >/dev/null; }
else
    csc="$WINDIR/Microsoft.NET/Framework64/v4.0.30319/csc.exe"
    srcs=(); for f in windows/src/*.cs; do srcs+=("$(cygpath -w "$f")"); done
    "$csc" -nologo -optimize+ -codepage:65001 -target:exe "-out:$(cygpath -w "$work/sky.exe")" "${srcs[@]}"
    render() { "$work/sky.exe" render "$@" >/dev/null; }
fi

# One place, one landscape, so every loop shows the same hill.
place=(--lat 47.3 --lon 11.4 --seed 7)

# frame DIR GLOB: the first rendered frame whose name matches GLOB.
# Numbering shifts with the day's length, so match by name, not number.
frame() {
    local f; f=$(find "$1" -name "$2" | sort | head -1)
    [[ -n "$f" ]] || { echo "no frame $2 in $1" >&2; exit 1; }
    echo "$f"
}

# fade OUT.webp FILTER HOLD FADE QUALITY IMG... : holds each image HOLD
# seconds, crossfades over FADE seconds, and fades the last back into the
# first so the loop is seamless.
fade() {
    local out=$1 vf=$2 hold=$3 fade=$4 quality=$5; shift 5
    local imgs=("$@" "$1") n=$(($# + 1)) inputs=() graph="" prev=v0 i
    local seg; seg=$(awk "BEGIN{print $hold + $fade}")
    for i in "${!imgs[@]}"; do
        inputs+=(-loop 1 -t "$seg" -framerate 15 -i "${imgs[$i]}")
        graph+="[$i:v]$vf,format=yuv420p,setsar=1,fps=15[v$i];"
    done
    for ((i = 1; i < n; i++)); do
        graph+="[$prev][v$i]xfade=transition=fade:duration=$fade:offset=$(awk "BEGIN{print $i * $hold}")[x$i];"
        prev=x$i
    done
    graph+="[$prev]trim=end=$(awk "BEGIN{print ($n - 1) * $hold + $fade}")[out]"
    ffmpeg -v error -y "${inputs[@]}" -filter_complex "$graph" -map "[out]" \
        -c:v libwebp_anim -lossless 0 -quality "$quality" -compression_level 6 -preset picture -loop 0 "$out"
    echo "$out: $(du -h "$out" | cut -f1)"
}

small="scale=960:-1:flags=lanczos"

# The day: one clear October day, midnight to night.
render "${place[@]}" --size 1280x640 --date 2026-10-14 --utc-offset 120 --sky clear --out "$work/day" &
# The year: the cabin's hill, close up, on a clear morning in each season.
seasons=(2026-04-22:120 2026-06-10:120 2026-08-25:120 2026-10-14:120 2026-10-28:60 2026-11-12:60 2027-01-15:60)
for s in "${seasons[@]}"; do
    render "${place[@]}" --size 2560x1280 --scale 1.5 --date "${s%:*}" --utc-offset "${s#*:}" --sky clear --out "$work/season-${s%:*}" &
done
# The weather: the same morning under each sky.
skies=(clear cloudy overcast fog rain snow)
for w in "${skies[@]}"; do
    render "${place[@]}" --size 1280x640 --date 2026-10-14 --utc-offset 120 --sky "$w" --out "$work/weather-$w" &
done
# The night: every other evening as the moon grows past full.
nights=(16 18 20 22 24 26 28 30)
for d in "${nights[@]}"; do
    render "${place[@]}" --size 1280x640 --date "2026-10-$d" --utc-offset 120 --sky clear --out "$work/moon-$d" &
done
wait

day=()
for p in midnight night-end blue-hour dawn sunrise golden morning noon \
         afternoon golden-eve sunset dusk blue-hour-eve night; do
    day+=("$(frame "$work/day" "[0-9][0-9]-$p.png")")
done
year=(); for s in "${seasons[@]}"; do year+=("$(frame "$work/season-${s%:*}" "*-morning*.png")"); done
sky=();  for w in "${skies[@]}";  do sky+=("$(frame "$work/weather-$w" "*-morning*.png")"); done
moon=(); for d in "${nights[@]}"; do moon+=("$(frame "$work/moon-$d" "*-night.png")"); done

# Night skies need the higher quality, or their gradients turn blocky.
fade docs/day.webp "$small" 0.9 0.9 85 "${day[@]}" &
fade docs/seasons.webp "crop=1600:640:700:560,$small" 1.4 1.0 72 "${year[@]}" &
fade docs/weather.webp "$small" 1.4 1.0 72 "${sky[@]}" &
fade docs/moon.webp "$small" 1.0 0.8 92 "${moon[@]}" &
wait
