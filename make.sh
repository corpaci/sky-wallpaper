#!/bin/bash
# Build the tools, render a day of frames per display size, and pack each set
# into a dynamic HEIC under out/.
#
#   ./make.sh [WIDTHxHEIGHT ...]        default: both displays on this Mac
#   SUNRISE=06:45 SUNSET=19:30 ./make.sh  move the day with the seasons
set -euo pipefail
cd "$(dirname "$0")"

SUNRISE=${SUNRISE:-07:20}  # central Europe, late October; set your own
SUNSET=${SUNSET:-17:55}
SEED=${SEED:-7}            # another seed, another mountain range
QUALITY=${QUALITY:-0.95}   # below ~0.9 HEVC smooths away the anti-banding dither (README)

sizes=("$@")
[ $# -gt 0 ] || sizes=(2560x1664 1920x1080)

swift build -c release --quiet
bin=.build/release
stamp=$(date +%Y-%m-%d)
mkdir -p out
for size in "${sizes[@]}"; do
    frames=build/frames-$size
    "$bin/wallframes" --size "$size" --sunrise "$SUNRISE" --sunset "$SUNSET" --seed "$SEED" --out "$frames"
    "$bin/heicpack" "$frames/manifest.txt" -o "out/sky-$size-$stamp.heic" --quality "$QUALITY"
done
