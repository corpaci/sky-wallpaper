#!/bin/bash
# Sunrise and sunset from --lat/--lon, checked against published times for
# both renderers (Swift, and C# under Mono), within 2 minutes. Needs Mono.
#
# Reference: Open-Meteo's archive API, fetched 2026-10-28. It reports past
# dates in today's UTC offset, so the Berlin summer times below are moved
# to that date's real offset (CEST, +120).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --quiet --product wallframes
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
csc -nologo -langversion:5 -codepage:65001 -optimize+ -out:"$tmp/sky.exe" windows/src/*.cs

minutes() { echo $((10#${1%%:*} * 60 + 10#${1##*:})); }
failed=0

check() {  # place lat lon date utc-offset expected (HH:MM-HH:MM, or a note)
    local place=$1 lat=$2 lon=$3 date=$4 offset=$5 want=$6 tool header got
    for tool in swift c#; do
        if [ "$tool" = swift ]; then
            header=$(.build/release/wallframes --dry-run --lat "$lat" --lon "$lon" --date "$date" --utc-offset "$offset")
        else
            header=$(mono "$tmp/sky.exe" render --dry-run --lat "$lat" --lon "$lon" --date "$date" --utc-offset "$offset")
        fi
        header=${header%%$'\n'*}
        if [[ "$want" == *:*-*:* ]]; then
            got=$(sed -E 's/.*sunrise ([0-9:]+), sunset ([0-9:]+).*/\1-\2/' <<<"$header")
            local dr=$(( $(minutes "${got%-*}") - $(minutes "${want%-*}") ))
            local ds=$(( $(minutes "${got#*-}") - $(minutes "${want#*-}") ))
            if (( dr < -2 || dr > 2 || ds < -2 || ds > 2 )); then
                echo "FAIL  $tool  $place $date: got $got, want $want"; failed=1
            else
                echo "ok    $tool  $place $date: $got (want $want)"
            fi
        elif [[ "$header" == *"$want"* ]]; then
            echo "ok    $tool  $place $date: $want"
        else
            echo "FAIL  $tool  $place $date: want \"$want\" in: $header"; failed=1
        fi
    done
}

check Berlin  52.52  13.40  2025-12-21   60 08:15-15:53
check Berlin  52.52  13.40  2026-06-21  120 04:42-21:33
check Madrid  40.42  -3.70  2025-12-21   60 08:34-17:51
check Sydney -33.87 151.21  2025-12-21  660 05:40-20:05
check Quito   -0.18 -78.47  2026-03-20 -300 06:18-18:24
check Tromsø  69.65  18.96  2025-12-21   60 "polar night"
check Tromsø  69.65  18.96  2026-06-21  120 "polar day"

[ $failed = 0 ] && echo "daylight: ok" || { echo "daylight: FAILED"; exit 1; }
