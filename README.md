# Sky wallpaper

A dynamic wallpaper for macOS and Windows that you own end to end. A renderer
paints one day of a layered mountain landscape: 14 frames, from night through
dawn, noon and sunset and back. Each platform then shows the right frame for
the time of day. No dependencies, no network, nothing left running.

## Why it is cheap

The desktop shows one still frame and swaps it at fixed times, 14 times a day.
Between swaps it is a static picture: no app running, no animation, no
per-frame GPU work. Live and video wallpapers redraw constantly and cost far
more.

- **macOS** has this built in: a dynamic HEIC holds all frames plus their
  schedule, and the system swaps them itself.
- **Windows** has no time-of-day wallpaper format. Task Scheduler starts a
  windowless helper at each switch time; it sets the frame and exits.

## macOS

### Make it

```bash
./make.sh
```

This builds both tools, renders frames into `build/frames-WxH/`, and writes
`out/sky-WxH-DATE.heic` for each display size (default `2560x1664` for the
built-in display and `1920x1080` for the external). It takes about 30 s.

Options, as environment variables:

| Variable | Default | Meaning |
|---|---|---|
| `SUNRISE`, `SUNSET` | `07:20`, `17:55` | Vienna in late October. h24 follows the clock, not the sun, so regenerate as the seasons move |
| `SEED` | `7` | Another seed gives another mountain range |
| `QUALITY` | `0.95` | HEIC quality; see Banding below |

Sizes are arguments: `./make.sh 2560x1664`.

### Install it

System Settings → Wallpaper → add a photo → pick `out/sky-2560x1664-….heic`,
and choose the dynamic option in the menu next to it. Repeat on the external
display with the `1920x1080` file. Each display has its own wallpaper.

The `light` and `dark` stills (noon and midnight) are what macOS shows if you
pick its light/dark modes instead of dynamic.

### Use your own images

`heicpack` works on any stills of the same size: photos, paintings, renders.
Write a manifest:

```
# HH:MM  path  [primary] [light] [dark]
06:30  dawn.jpg
12:00  noon.jpg      light
18:45  dusk.jpg      primary
22:00  night.jpg     dark
```

- Times are local wall-clock time. Each image shows from its time until the
  next one, wrapping past midnight.
- `primary` is the still shown in Finder and Settings thumbnails.
- `light`/`dark` are optional, but set both or neither.
- Paths are relative to the manifest, may contain spaces, and may repeat.

```bash
.build/release/heicpack my/manifest.txt -o my.heic
.build/release/heicpack --inspect my.heic     # print any wallpaper's schedule
```

The packer reads its own output back and refuses to call it done if the
schedule doesn't decode.

## Windows

Windows 10 or 11. Nothing to download: the installer compiles the helper with
the C# compiler that ships with Windows (.NET Framework 4.x), and no admin
rights are needed.

### Install it

Copy this folder to the PC. Then, in PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File windows\install.ps1 -Sunrise 07:20 -Sunset 17:55
```

The installer:

1. compiles `sky.exe` (console) and `sky-apply.exe` (windowless) into
   `%LOCALAPPDATA%\SkyWallpaper`;
2. saves your current wallpapers, so uninstall can put them back;
3. renders a frame set for each connected monitor size (about 2–3 s per frame);
4. registers a task named `SkyWallpaper` with one trigger per switch time,
   plus one at logon; a switch missed during sleep runs on wake;
5. sets the current frame.

Re-run it with new times as the seasons move. Each run renders into a fresh
folder, because Windows caches wallpapers by path. To remove everything and
restore your old wallpaper:

```powershell
powershell -ExecutionPolicy Bypass -File windows\uninstall.ps1
```

### The helper

```
sky monitors                    list monitors and their pixel sizes
sky frame DIR HH:MM [WxH]       which frame a monitor of that size shows then
sky schedule DIR                the switch times
sky apply DIR                   set the current frame on every monitor
sky render --size WxH --out DIR render frames yourself
```

`DIR` is a `frames-…` folder under `%LOCALAPPDATA%\SkyWallpaper`. A monitor
with no frame set of its own size gets the closest aspect ratio, filled.
Errors from the scheduled task go to `sky.log` in the same folder.

## Changing the look

The renderer exists twice: `Sources/wallframes/*.swift` for macOS and
`windows/src/*.cs` for Windows, kept in step file by file. After changing
either one, run this on the Mac:

```bash
windows/parity.sh
```

It renders the same day with both, compiled as C# 5 like on Windows, and
compares every pixel and the schedule. It needs Mono.

## Layout

- `Sources/wallframes/`: the Swift renderer. `Scene.swift` holds the sun
  model, palettes (one keyframe per sun altitude, morning and evening
  variants), and landscape. `Color.swift` holds OKLab blending and noise.
- `Sources/heicpack/`: manifest parsing, HEIC packing, and inspection.
- `windows/src/`: the C# port of the renderer (`Color.cs`, `Scene.cs`), a
  PNG writer, the wallpaper calls (`Desktop.cs`), and the CLI (`Program.cs`).
- `windows/install.ps1`, `windows/uninstall.ps1`: the Windows install and
  removal scripts.
- `windows/parity.sh`, `windows/compare.swift`: the cross-renderer check.
- `build/`, `out/`: macOS frames and wallpapers, not tracked. Safe to delete.

On macOS nothing is installed anywhere. On Windows everything lives in
`%LOCALAPPDATA%\SkyWallpaper` plus the one scheduled task.

## Verified

On a Mac (macOS 26.6.2, M3):

- **Metadata format.** The `apple_desktop` XMP namespace and the `l`/`d`
  light/dark keys match Apple's own `Sonoma.heic`. Apple's time-based
  wallpapers download on demand, so no `h24` file exists on disk to compare
  against. The `ti`/`t`/`i` keys and the local-clock `t` (fraction of the day)
  come from the open-source `wallpapper` encoder.
- **Read-back.** Both HEICs decode through ImageIO with all 14 images and the
  full schedule.
- **Banding.** Frames are dithered to 8-bit. HEVC smooths the dither away at
  low quality. Measured as identical-pixel runs down a column of the dark night
  sky, where shorter runs mean less banding:

  | Encoding | Mean run | Longest run | Size, 2560×1664 ×14 |
  |---|---|---|---|
  | PNG source | 2.2 px | 17 px | — |
  | q 0.8 | 23.7 px | 80 px | 0.9 MB |
  | q 0.9 | 8.0 px | 64 px | 2.0 MB |
  | q 0.95 | 3.6 px | 47 px | 8.1 MB |
  | q 1.0 | 2.2 px | 15 px | 27.6 MB |

  Apple's own wallpapers are 8-bit HEIC too. If you still see bands in the
  night sky, use `QUALITY=1.0`. Windows uses PNG, which keeps the dither
  exactly.
- **Windows renderer.** The C# compiles as C# 5 with no errors or warnings,
  in both console and windowless builds. Its frames match the Swift ones: at
  most 0.012% of color values differ, each by one step out of 255, for both
  an October and a summer day; the schedules are identical.
- **Windows frame choice.** `sky frame` was tested on two rendered sizes: it
  wraps past midnight, switches exactly at each time, and picks the closest
  aspect ratio for other monitor sizes.

## Not verified yet

macOS:

- **Switch times.** It is unconfirmed that macOS switches frames at these
  local times (and not UTC). Install it, then check that the frame on screen
  matches `heicpack --inspect` for the current time.
- **Cache refresh.** It is unconfirmed whether macOS refreshes a wallpaper
  whose file was replaced at the same path. Output names carry the date for
  that reason. If a same-day rebuild doesn't show up, re-pick the file.

Windows: nothing has run on Windows yet. Untested so far:

- the in-box `csc.exe` (the old C# 5 compiler, not the Roslyn one used here);
- the `IDesktopWallpaper` calls, and whether monitor sizes come back in
  physical pixels on scaled displays (`sky monitors` shows what it sees);
- registering the task without admin rights;
- triggers firing on time and after sleep.

If something fails, `sky.log` and the installer's error say where.
