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
.build/release/wallframes --size "$size" --sunrise "$sunrise" --sunset "$sunset" --out "$tmp/swift" >/dev/null

# -langversion:5 matches the compiler that ships with Windows.
csc -nologo -langversion:5 -codepage:65001 -optimize+ -out:"$tmp/sky.exe" windows/src/*.cs
mono "$tmp/sky.exe" render --size "$size" --sunrise "$sunrise" --sunset "$sunset" --out "$tmp/cs" >/dev/null

swift windows/compare.swift "$tmp/swift" "$tmp/cs/$size"
