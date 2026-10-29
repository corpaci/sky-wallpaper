# Sky wallpaper

A dynamic wallpaper for macOS and Windows. It renders a day of a snowcapped
mountain above spruce forests and a little cabin with a porch, as still frames, and shows
the right one for the time of day. Optionally, it follows your real sunrise,
sunset and hourly weather.

![The frames of one clear day, from midnight to night](docs/preview.jpg)
![Cloudy, overcast, rain, snow and fog](docs/weather.jpg)

**Why it's cheap:** the desktop shows a still image and swaps it at set
times; nothing animates. macOS swaps the frames itself (a dynamic HEIC). On
Windows, Task Scheduler starts a tiny helper at each switch time; it sets the
frame and exits. With location or weather on, the day is rendered once,
shortly after midnight: about a minute of low-priority CPU. On macOS, a small
helper also stays loaded, but asleep: it wakes only when you switch desktops.

No dependencies. Same inputs, same frames.

## macOS

Needs macOS 14+ and Swift (`xcode-select --install`).

```bash
git clone https://github.com/corpaci/sky-wallpaper.git
cd sky-wallpaper
```

**Daily (follows sun and weather):**

```bash
mac/install.sh --lat 48.2 --lon 16.4
```

- Without `--lat/--lon`, it uses your time zone's city.
- `--no-weather` keeps it offline; sunrise and sunset still follow the date.
- A background job (launchd) runs at 00:05, at login, and on wake if it
  missed 00:05. It renders the day for each screen, packs it and sets it.
  The log is at `~/Library/Application Support/SkyWallpaper/daily.log`.
- macOS only lets a program set the desktop (Space) that's showing, and
  full-screen apps count as desktops. So a small helper stays loaded with no
  timers: when you switch desktops, it puts today's sky on the one that comes
  into view. It uses about 30 MB of memory and no CPU while idle; its log is
  `follow.log` in the same folder.
- `mac/uninstall.sh` removes it all and puts your previous wallpaper back.

**Static (fixed times, nothing installed):**

```bash
SUNRISE=07:20 SUNSET=17:55 ./make.sh 2560x1664
```

Then go to System Settings → Wallpaper → add a photo → pick
`out/sky-2560x1664-DATE.heic` → choose the dynamic option. Use one file per
display. For your pixel size: `system_profiler SPDisplaysDataType | grep Resolution`.

**Screen saver:** it's a separate setting, and by default it plays a video.
To keep the sky when idle, go to System Settings → Lock Screen → Start
Screen Saver when inactive → Never. That's also the cheapest choice.

## Windows

Needs Windows 10 or 11, nothing else: the installer compiles its helper with
the C# compiler built into Windows. No admin rights.

**Easiest:** open PowerShell (Start → type "PowerShell") and paste:

```powershell
irm https://raw.githubusercontent.com/corpaci/sky-wallpaper/main/windows/get.ps1 | iex
```

It downloads this project, asks for your town, and sets everything up in
about a minute. Press Enter at the town question to use fixed times instead.
[`get.ps1`](windows/get.ps1) is a short script you can read first.

**Or with the ZIP:** on GitHub, Code → Download ZIP. Unpack it and
double-click `windows\Install.cmd`. If Windows says it protected your PC,
choose More info → Run anyway.

**To remove it** and get your old wallpaper back, double-click
`windows\Uninstall.cmd`, or paste:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\SkyWallpaper\uninstall.ps1"
```

Run the installer again to change town or settings. To skip the questions,
pass them yourself:

```powershell
powershell -ExecutionPolicy Bypass -File windows\install.ps1 -Latitude 48.2 -Longitude 16.4 -NoWeather
```

- Everything lives in `%LOCALAPPDATA%\SkyWallpaper`, plus one scheduled task,
  `SkyWallpaper`. The task switches frames, renders the new day at 00:05,
  and catches up at logon, unlock and wake.
- Without a location, it uses fixed `-Sunrise 07:20 -Sunset 17:55`.

If the frame looks stale:

```powershell
Get-ScheduledTaskInfo SkyWallpaper | Format-List LastRunTime, LastTaskResult, NextRunTime
Get-Content "$env:LOCALAPPDATA\SkyWallpaper\sky.log" -Tail 20
```

`LastTaskResult` 0 means the last run worked.

## Weather and privacy

Weather comes from [Open-Meteo](https://open-meteo.com): free, no account,
no key. Once a day, one request carries the date and your coordinates
rounded to 0.1° (about 10 km). On Windows, the town you type at install is
looked up once on Open-Meteo too. Nothing else leaves the machine. The response
is kept beside the frames as `forecast.json`. Each frame takes its hour's
sky, and an extra frame goes on every hour where the sky changes. If the
forecast can't be fetched, the day renders without weather.

## Options

| What | macOS daily | macOS static | Windows | Default |
|---|---|---|---|---|
| Location | `--lat`, `--lon` | — | `-Latitude`, `-Longitude` | macOS: time zone's city; Windows: asks for your town |
| Weather off | `--no-weather` | always off | `-NoWeather` | on, when located |
| Fixed sunrise, sunset | — | `SUNRISE`, `SUNSET` | `-Sunrise`, `-Sunset` | `07:20`, `17:55` |
| Landscape (another seed, other mountains) | `--seed` | `SEED` | `-Seed` | `7` |

The renderers also run by hand. For example, this prints a day's schedule
without rendering:

```bash
.build/release/wallframes --dry-run --lat 48.2 --lon 16.4 --date 2026-12-21 --weather
```

`--sky rain` forces one weather type for every frame. `--forecast FILE`
reads a saved forecast.

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

## Changing the look

The renderer exists twice, kept in step file by file: Swift
(`Sources/wallframes/`) and C# (`windows/src/`). After changing either one,
run these on a Mac with Mono (`brew install mono`):

```bash
windows/parity.sh     # every sky and a real forecast day, pixel by pixel
tests/daylight.sh     # sunrise and sunset against published times
```

## Status

- **macOS:** the daily job and the desktop helper are installed and work on
  the author's Mac, and the wallpaper stays dynamic. Still open: whether
  macOS ever trims its own copies of past days' wallpapers, and the first
  00:05 run.
- **Windows:** the earlier version runs on a real PC. These haven't run on
  Windows yet:
  - the daily `tick` (rendering, re-registering the task, weather), though
    it compiles and its task XML validates;
  - the one-line and double-click installers.

Details and measurements: [docs/NOTES.md](docs/NOTES.md).
