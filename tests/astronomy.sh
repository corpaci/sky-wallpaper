#!/bin/bash
# The sky's geometry against known events: eclipses, conjunctions, an
# elongation, an opposition, planet magnitudes, the sun at published
# sunrise and sunset times, Polaris, the galactic center. Checks the Swift
# code against published values, then the C# port against the Swift code
# (to the printed digit). Needs Mono for the C# half.
set -euo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
swiftc -O Sources/wallframes/{Astronomy,Stars,NightSky,Color}.swift tests/astronomy/main.swift -o "$tmp/check"
"$tmp/check" > "$tmp/swift.txt"

failed=0
expect() {  # name low high: the published value, with the model's and the reference's rounding
    local got
    got=$(awk -v n="$1" '$1 == n { print $2 }' "$tmp/swift.txt")
    if [ -n "$got" ] && awk -v g="$got" -v lo="$2" -v hi="$3" 'BEGIN { exit !(g >= lo && g <= hi) }'; then
        echo "ok    $1 $got"
    else
        echo "FAIL  $1 ${got:-missing}, want $2 to $3"; failed=1
    fi
}
expect solar-eclipse-dallas-sep 0 0.1          # total at Dallas, 2024-04-08 18:42 UT
expect solar-eclipse-dallas-phase 179 180
expect lunar-eclipse-from-antisun 0 0.5        # total, 2025-09-07 18:11 UT (gamma -0.275)
expect lunar-eclipse-lit 0.999 1
expect jupiter-saturn-min-sep 0.05 0.15        # 0.10°, 2020-12-21 18:20 UT
expect jupiter-saturn-day 21.4 22.1
expect venus-jupiter-min-sep 0.4 0.6           # 0.5°, 2023-03-01/02
expect venus-jupiter-day 1.5 2.5
expect mercury-max-elongation 18.4 19.0        # 18.7°, 2024-03-24
expect mercury-max-elongation-day 23.5 25.5
expect mars-opposition-day 15.5 16.5           # 2025-01-16 02:38 UT
expect jupiter-opposition-mag -3.0 -2.6        # -2.9, 2023-11-03
expect venus-brilliancy-mag -4.9 -4.5          # -4.6 to -4.9, 2025-02-14
for s in sun-berlin-rise sun-berlin-set sun-madrid-set sun-sydney-rise sun-quito-rise; do
    expect $s -1.1 -0.55                       # -0.833° at the published minute, ±2 minutes
done
expect polaris-alt-berlin 51.7 53.3            # the latitude, 52.52°, ± Polaris's 0.74° from the pole
expect galactic-center-l -0.05 0.05
expect galactic-center-b -0.05 0.05
expect stars 2847 2847
expect eclipse-dallas-2024-ut 18.62 18.78     # total at Dallas, greatest 18:42 UT
expect eclipse-dallas-2024-solar 1 1
expect eclipse-berlin-2028-ut 16.78 16.95      # total lunar, greatest 16:52 UT, the moon up over Berlin
expect eclipse-berlin-2028-solar 0 0
expect eclipse-berlin-none-ut -1 -1

if command -v csc >/dev/null && command -v mono >/dev/null; then
    csc -nologo -langversion:5 -codepage:65001 -optimize+ -out:"$tmp/check.exe" \
        windows/src/{Astronomy,Stars,NightSky,Color}.cs tests/astronomy/Check.cs
    mono "$tmp/check.exe" > "$tmp/cs.txt"
    if diff "$tmp/swift.txt" "$tmp/cs.txt"; then echo "ok    C# matches Swift"; else echo "FAIL  C# differs from Swift"; failed=1; fi
else
    echo "skip  C# (no Mono)"
fi

[ $failed = 0 ] && echo "astronomy: ok" || { echo "astronomy: FAILED"; exit 1; }
