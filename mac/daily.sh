#!/bin/bash
# Renders today's sky for every screen and sets it as the wallpaper. Run by
# the LaunchAgent at 00:05, at login, and on wake after a missed 00:05.
#
#   daily.sh [--force] [--no-set]
#
# Once a day is enough: macOS switches the frames inside the HEIC itself.
# If today's sky exists it is only set again, unless --force. --no-set
# renders and packs without touching the desktop. If the forecast can't be
# fetched, today renders without weather rather than not at all.
#
# macOS sets a wallpaper per Space (desktop), and only the ones showing can
# be set. Other Spaces keep an earlier day's sky until they are showing
# during a run; their files are kept until nothing points at them.
set -euo pipefail

app=${SKY_APP:-"$HOME/Library/Application Support/SkyWallpaper"}
bin="$app/bin"
# shellcheck source=/dev/null
source "$app/config"  # LAT, LON, WEATHER (yes|no), SEED

force=no set=yes
for arg in "$@"; do
    case "$arg" in
        --force) force=yes ;;
        --no-set) set=no ;;
        *) echo "usage: daily.sh [--force] [--no-set]" >&2; exit 2 ;;
    esac
done

day=$(date +%F)
mkdir -p "$app/out"
made=()
if [ "$force" = no ] && compgen -G "$app/out/sky-*-$day-*.heic" >/dev/null; then
    # Today's sky exists. It still goes on the desktops showing now: macOS
    # sets wallpapers per Space, and this may be one the render missed.
    last=$(for f in "$app"/out/sky-*-"$day"-*.heic; do echo "${f: -9:4}"; done | sort | tail -1)
    for f in "$app"/out/sky-*-"$day-$last".heic; do made+=("$f"); done
    echo "$(date '+%F %T') today's sky exists"
else
    echo "$(date '+%F %T') rendering $day"
    stamp=$(date +%F-%H%M)  # a new path each run: macOS caches wallpapers by path
    work="$app/work"
    rm -rf "${work:?}"
    for size in $("$bin/heicpack" --screens | sort -u); do
        frames="$work/$size"
        args=(--size "$size" --lat "$LAT" --lon "$LON" --seed "$SEED" --out "$frames")
        if [ "$WEATHER" = yes ] && "$bin/wallframes" "${args[@]}" --weather >/dev/null; then
            :
        else
            [ "$WEATHER" = yes ] && echo "no forecast; rendering without weather" >&2
            "$bin/wallframes" "${args[@]}" >/dev/null
        fi
        "$bin/heicpack" "$frames/manifest.txt" -o "$app/out/sky-$size-$stamp.heic"
        made+=("$app/out/sky-$size-$stamp.heic")
    done
    rm -rf "${work:?}"
fi

if [ "$set" = yes ]; then
    "$bin/heicpack" --set "${made[@]}"
    # Delete only what no Space or display points at any more. If the
    # wallpaper store can't be read, delete nothing.
    if in_use=$("$bin/heicpack" --in-use); then
        for f in "$app"/out/sky-*.heic; do
            keep=no
            for m in "${made[@]}"; do [ "$f" = "$m" ] && keep=yes; done
            grep -qxF -- "$f" <<<"$in_use" && keep=yes
            [ "$keep" = yes ] || rm -f "$f"
        done
    fi
fi
