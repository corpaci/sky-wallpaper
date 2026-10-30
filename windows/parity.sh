#!/bin/bash
# Render the same day with the Swift renderer and the C# port, then compare
# pixels and schedules. Run on a Mac with Mono after touching either renderer.
#
#   windows/parity.sh [WIDTHxHEIGHT] [SUNRISE] [SUNSET]
set -euo pipefail
cd "$(dirname "$0")/.."

size=${1:-640x416}
sunrise=${2:-07:20}
sunset=${3:-17:55}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

swift build -c release --quiet --product wallframes
# -langversion:5 matches the compiler that ships with Windows.
csc -nologo -langversion:5 -codepage:65001 -optimize+ -out:"$tmp/sky.exe" windows/src/*.cs

# Every kind of sky, so clouds, rain, snow and fog are covered too.
failed=0
for sky in clear cloudy overcast rain snow fog; do
    echo "== $sky"
    .build/release/wallframes --size "$size" --sunrise "$sunrise" --sunset "$sunset" --sky "$sky" --out "$tmp/swift-$sky" >/dev/null
    mono "$tmp/sky.exe" render --size "$size" --sunrise "$sunrise" --sunset "$sunset" --sky "$sky" --out "$tmp/cs-$sky" >/dev/null
    swift windows/compare.swift "$tmp/swift-$sky" "$tmp/cs-$sky/$size" || failed=1
done

# A real day's forecast: mixed skies plus the extra hourly frames.
echo "== forecast"
day=(--lat 52.5 --lon 13.4 --date 2026-10-28 --utc-offset 60 --forecast tests/forecast-berlin-2026-10-28.json)
.build/release/wallframes --size "$size" "${day[@]}" --out "$tmp/swift-day" >/dev/null
mono "$tmp/sky.exe" render --size "$size" "${day[@]}" --out "$tmp/cs-day" >/dev/null
swift windows/compare.swift "$tmp/swift-day" "$tmp/cs-day/$size" || failed=1

# Moonless nights, north and south: the Milky Way, and the view turned
# around to face north.
for place in "vienna 48.2 16.4 120" "sydney -33.9 151.2 600"; do
    read -r name lat lon offset <<<"$place"
    echo "== milky way, $name"
    night=(--size "$size" --lat "$lat" --lon "$lon" --date 2026-07-14 --utc-offset "$offset")
    .build/release/wallframes "${night[@]}" --out "$tmp/swift-$name" >/dev/null
    mono "$tmp/sky.exe" render "${night[@]}" --out "$tmp/cs-$name" >/dev/null
    swift windows/compare.swift "$tmp/swift-$name" "$tmp/cs-$name/$size" || failed=1
done
# Rare days, Berlin: an eclipse at sunset with the Perseids that night and
# the two out stargazing; a lunar eclipse on a winter night; spring in
# blossom with a bear and her cubs about.
for rare in "2026-08-12 120" "2028-12-31 60" "2026-05-27 120"; do
    read -r date offset <<<"$rare"
    echo "== rare day, $date"
    day=(--size "$size" --lat 52.5 --lon 13.4 --date "$date" --utc-offset "$offset")
    .build/release/wallframes "${day[@]}" --out "$tmp/swift-$date" >/dev/null
    mono "$tmp/sky.exe" render "${day[@]}" --out "$tmp/cs-$date" >/dev/null
    swift windows/compare.swift "$tmp/swift-$date" "$tmp/cs-$date/$size" || failed=1
done
exit $failed
