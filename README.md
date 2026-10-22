# Sky wallpaper

A dynamic wallpaper for macOS and Windows. It renders one day of a mountain
landscape as 14 still frames and shows the right one for the time of day.

![The 14 frames, from midnight to night](docs/preview.jpg)

**Why it's cheap:** the desktop shows a still image and swaps it 14 times a
day. Nothing animates, nothing stays running. macOS swaps the frames itself
(a dynamic HEIC). On Windows, Task Scheduler starts a tiny helper at each
switch time; it sets the frame and exits.

No dependencies, no network. Same inputs, same frames.

## macOS

Needs macOS 14+ and Swift (`xcode-select --install`).

```bash
git clone https://github.com/corpaci/sky-wallpaper.git
cd sky-wallpaper
SUNRISE=07:20 SUNSET=17:55 ./make.sh 2560x1664
```

- Use your local sunrise and sunset, and your display's pixel size:
  `system_profiler SPDisplaysDataType | grep Resolution`. For several
  displays, list several sizes.
- Result: `out/sky-2560x1664-DATE.heic`, about 8 MB. The first run takes
  about a minute (compiling); later runs take seconds.
- Install: System Settings → Wallpaper → add a photo → pick the `.heic` →
  choose the dynamic option in the menu next to it. One file per display.
- The screen saver is separate and plays its own video (Aerial) when idle. To
  keep the sky instead, go to System Settings → Lock Screen → Start Screen
  Saver when inactive → Never, and set the display-off times there. This is
  also the cheapest option: a video screen saver costs far more than the
  wallpaper.

## Windows

Needs Windows 10 or 11, nothing else: the installer compiles its helper with
the C# compiler built into Windows. No admin rights.

Clone the repo (or download it as a ZIP and unpack it), then in PowerShell, in
the repo folder:

```powershell
powershell -ExecutionPolicy Bypass -File windows\install.ps1 -Sunrise 07:20 -Sunset 17:55
```

It renders frames for every connected monitor (a minute or so), schedules the
switches, and sets the current frame. Everything lives in
`%LOCALAPPDATA%\SkyWallpaper` plus one scheduled task, `SkyWallpaper`.

To remove it and get your old wallpaper back:

```powershell
powershell -ExecutionPolicy Bypass -File windows\uninstall.ps1
```

If the frame looks stale, check the task's last run and the log:

```powershell
Get-ScheduledTaskInfo SkyWallpaper | Format-List LastRunTime, LastTaskResult, NextRunTime
Get-Content "$env:LOCALAPPDATA\SkyWallpaper\sky.log" -Tail 20
```

`LastTaskResult` 0 means the last run worked.

## Options

| What | macOS (env var) | Windows (parameter) | Default |
|---|---|---|---|
| Sunrise, sunset | `SUNRISE`, `SUNSET` | `-Sunrise`, `-Sunset` | `07:20`, `17:55` |
| Landscape (another seed, other mountains) | `SEED` | `-Seed` | `7` |
| HEIC quality (below 0.9, night skies band) | `QUALITY` | — | `0.95` |

The schedule follows the clock, not the sun. Rerun with new times as the
seasons move. On macOS, pick the new file again.

## Your own images (macOS)

Any same-size stills work. Write a manifest of local switch times:

```
# HH:MM  path        [primary] [light] [dark]
06:30  dawn.jpg
12:00  noon.jpg      light
18:45  dusk.jpg      primary
22:00  night.jpg     dark
```

```bash
.build/release/heicpack manifest.txt -o mine.heic
.build/release/heicpack --inspect mine.heic   # print any wallpaper's schedule
```

Each image shows from its time until the next. `primary` is the thumbnail;
`light`/`dark` are the stills for macOS's light/dark modes (both or neither).

## Changing the look

The renderer exists twice, kept in step file by file: Swift
(`Sources/wallframes/`) and C# (`windows/src/`). After changing either, run on
a Mac with Mono (`brew install mono`):

```bash
windows/parity.sh
```

It renders the same day with both and compares every pixel and the schedule.

## Status

- **macOS:** built and checked on macOS 26.6 (M3, Swift 6.3). The files are
  valid. Not yet confirmed: that macOS switches on local time, not UTC.
- **Windows:** installs and sets the wallpaper on a real PC. Its frames match
  the macOS ones to within one color step. Frames missed during sleep now
  catch up on wake, unlock and logon; that fix is not yet confirmed on a PC.

Details, measurements and the file format: [docs/NOTES.md](docs/NOTES.md).
