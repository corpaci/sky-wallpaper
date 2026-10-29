# Notes

Evidence behind the README: how the pieces work, what was checked, what was
not.

## How it works

**Frames.** 14 frames at fixed sun altitudes (−14°, −7°, −3°, 0.5°, 5°, 14° on
each side of noon, plus noon and midnight), so they bunch around sunrise and
sunset, where the sky changes fastest. The sun follows a sine arc between
sunrise and sunset. Colors are blended in OKLab and dithered to 8 bits so slow
gradients don't band. Rendering is deterministic: two runs with the same
inputs produce byte-identical PNGs (checked for both renderers, and from a
fresh clone). The HEIC is not byte-identical between packs of the same
frames: about 0.5 KB near the start of the file differs.

**Landscape.** Far to near:
- a summit of domain-warped ridged multifractal noise, with a ragged snowcap
  that takes the sky's color and is brighter on the face toward the sun;
- a rocky middle range;
- rounded hills with spruce woods and clearings;
- a cabin with a porch (lean-to roof, posts, railing with balusters, steps),
  whose window lights up from dusk to dawn, with three tall spruces beside
  it.

The land is a silhouette line, sampled four times per pixel column. Trees and
the porch are 2-D antialiased coverage, so sky shows between branches. Each
spruce is built from tapered capsules:
- a trunk with 21 whorls up a cone (a Fibonacci number), alternately 5 and 3
  branches;
- each branch turned by the golden angle (137.5°), so its sideways reach,
  the cosine of the turn, varies the way phyllotaxis spaces real branches;
- branches rise near the top, droop near the foot, and bend down toward
  their tips;
- each branch carries copies of itself 0.382 (1/φ²) as long: two levels deep
  on big trees, one on small.

Trees are slightly darker than the meadow behind them, and snow whitens only
open ground.

**Sunrise and sunset** come from NOAA's general solar position equations, for
`--lat/--lon` and the date in the machine's time zone. The day is held
between 3 and 21 hours, centered on solar noon, so every frame keeps its own
minute. The manifest header says when that happens (polar night or day).

**Weather.** Each sky (clear, cloudy, overcast, rain, snow, fog) maps to knobs
in `Weather`: clouds, overcast, sea, valley, wet, snow and fog. Grey weather
isn't mirrored:
- **Overcast** draws a sea of clouds just below the far ranges, behind the
  cabin's hill. Its top is |noise| humps; its billows shrink toward the
  horizon and are lit where the noise thins upward.
- **Fog** sinks each hill's foot into bright fog lakes, least in front.
- **Rain** is the moment after:
  - a primary and secondary bow (reversed colors, Alexander's dark band, a
    brighter sky inside) centred opposite the sun's side of the view, sinking
    as the sun climbs and gone above about 42°;
  - glints on open ground (never on trees or the porch), each one color of
    the spectrum.

The forecast is
Open-Meteo's hourly `weather_code` and `cloud_cover`. WMO codes decide fog,
snow and rain; cloud cover decides the rest (under 30% clear, under 75%
cloudy, otherwise overcast). Each frame takes its hour's sky. Extra frames go
on every hour where the sky changes, and at 00:00 if the frame that wraps past
midnight would show the wrong sky.

**macOS format.** A multi-image HEIC. The first image carries XMP
`apple_desktop:h24` (namespace `http://ns.apple.com/namespace/1.0/`): a base64
binary plist `{ti: [{t: fraction of day, i: image index}], ap: {l, d}}`.

**macOS daily job.** A LaunchAgent (`local.sky-wallpaper`, process type
Background) runs `daily.sh` at 00:05, at login, and on wake after a missed run:
1. Render each screen's size, which `heicpack --screens` reports in backing
   pixels.
2. Pack the frames into a new file name, because macOS caches wallpapers by
   path.
3. `heicpack --set` gives each screen the file for its size.
4. Keep only what is on screen.

A run is skipped if today's sky already exists.

**Windows.** `install.ps1` compiles `windows/src/*.cs` twice with
`%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe`: once as `sky.exe`
(console), and once as `sky-apply.exe` (windowless, so nothing flashes). The
scheduled task runs `sky-apply.exe tick`:
1. Render today if it's missing, into a new folder, because Windows caches
   wallpapers by path.
2. When the frames changed, re-register the task from Task Scheduler XML via
   `schtasks /XML`:
   - one daily trigger per switch time, plus 00:05;
   - catch-up triggers 30 s after logon, on unlock, and on wake (Kernel-Power
     507 or Power-Troubleshooter event 1);
   - priority 7, never wakes the PC.
3. Set each monitor's frame through `IDesktopWallpaper`.

## Verified

On macOS 26.6.2, M3, Swift 6.3.3, Mono 6.12 (Roslyn csc 3.9):

- **HEIC metadata.** The namespace and the `l`/`d` keys match Apple's own
  `/System/Library/Desktop Pictures/Sonoma.heic`. Apple's time-based wallpapers
  download on demand, so there is no local `h24` file to compare against. The
  `ti`/`t`/`i` keys and local-clock `t` come from the open-source
  [wallpapper](https://github.com/mczachurski/wallpapper) encoder.
- **Local time, on screen (owner, 2026-10-28).** At 19:11 CET (18:11 UTC) the
  built-in screen showed the night frame scheduled for 18:19, not the blue-hour
  frame for 17:31. So macOS reads `t` as local wall-clock time.
- **Read-back.** `heicpack` reopens every file it writes and checks the image
  count and schedule.
- **Banding vs HEIC quality.** HEVC smooths the dither away at low quality.
  Measured as identical-pixel runs down a column of the dark night sky, where
  shorter runs mean less banding:

  | Encoding | Mean run | Longest run | 14 frames at 2560×1664 |
  |---|---|---|---|
  | PNG source | 2.2 px | 17 px | — |
  | q 0.8 | 23.7 px | 80 px | 0.9 MB |
  | q 0.9 | 8.0 px | 64 px | 2.0 MB |
  | q 0.95 | 3.6 px | 47 px | 8.1 MB |
  | q 1.0 | 2.2 px | 15 px | 27.6 MB |

  Apple ships its own wallpapers as 8-bit HEIC too. Windows uses PNG, which
  keeps the dither exactly.
- **C# port.** It compiles with `-langversion:5`, the level of Windows'
  built-in compiler, in console and windowless builds, with no warnings.
  `windows/parity.sh` compares it with the Swift renderer for every sky and for
  a real forecast day (`tests/forecast-berlin-2026-10-28.json`). At worst,
  0.015% of color values differ, each by one step out of 255. Schedules are
  identical.
- **Sunrise and sunset.** `tests/daylight.sh` compares both renderers with
  published times from Open-Meteo's archive:
  - Berlin winter and summer, Madrid, Sydney and Quito: all within 1 minute;
  - Tromsø: polar night and polar day are handled.
- **Forecast.** A live fetch for Berlin works in both renderers (Swift
  URLSession, and C# WebClient with TLS 1.2 under Mono), and gives identical
  schedules.
- **macOS daily job, without installing.** I ran `daily.sh --no-set` in a
  scratch folder:
  - two screens (3420×2224 and 1920×1080), 26 frames each with weather, in
    22 s wall clock and 54 s of CPU;
  - a second run is skipped;
  - zone.tab parsing gives the right coordinates for six time zones.
  - `heicpack --screens` and `--save` read this Mac correctly.
- **Windows task XML.** It is well-formed as UTF-16, the encoding schtasks
  reads: 27 daily triggers, plus logon, unlock and wake.
- **Frame choice.** I tested `sky frame` on two rendered sizes. It wraps past
  midnight, switches exactly on the minute, and uses the closest aspect ratio
  for other monitor sizes.
- **Windows PC (owner, 2026-10-22).** The earlier `install.ps1` runs on a real
  PC: the built-in compiler accepts the code, the task registers, and the
  wallpaper gets set.
- **macOS screen saver.** The screen saver is its own setting, separate from
  the wallpaper. On this Mac it was an Aerial video while the desktop showed
  the sky HEIC.

- **macOS daily job, installed (2026-10-28).**
  - The agent loads as a background-type job with the 00:05 calendar trigger.
    The first run rendered and set both screens (19 frames each, from the
    Vienna forecast). The run-at-load skipped correctly.
  - **First scheduled run (2026-10-29).** It started at 00:12 with the lid
    closed, so `--screens` listed only the external 1920×1080; the file was
    written at 02:08, the Mac apparently sleeping in between. In the morning
    the follower put that 16:9 file on the 3:2 built-in screen.
    - Fixed: daily.sh remembers every size seen (`screens`) and renders each
      size missing for today.
    - Fixed: the follower adds unknown sizes and starts the daily job.
    - Re-rendered: both screens show their own sizes.
  - **It stays dynamic.** `NSWorkspace.setDesktopImageURL` writes the same
    `{type: imageFile, url}` entry that System Settings wrote, with no separate
    "dynamic" flag, so the behavior comes from the file either way.
  - **Spaces.** `NSWorkspace` sets only the Space currently showing on each
    display, and full-screen apps are Spaces too. On the built-in screen
    (one desktop, eight full-screen app Spaces) all three sets that day
    landed on full-screen Spaces, so its desktop kept the old file; the owner
    saw it there. The external screen's showing desktop got today's sky
    directly. The Dock's own list (`com.apple.spaces`) labelled that Space a
    full-screen app; the list was stale, or its type codes are misread here.
    It isn't relied on.
    - Overwriting the wallpaper file in place doesn't help. Thirty seconds
      later, macOS's cached copy still held the old bytes.
    - `heicpack --in-use` reads the wallpaper store (fail-safe), so daily.sh
      deletes only files that no Space or display points at.
  - **The desktop follower.** `heicpack --follow`, a second LaunchAgent with
    KeepAlive, wakes on Space switches, wake, session return and screen
    changes. It sets the newest sky on the showing Space if that Space has an
    older one. When the owner switched Spaces, the built-in screen's desktop
    was set within a second; the owner then confirmed both screens show the
    new sky. Idle cost: about 30 MB resident and no CPU time growth across
    48 s of samples.
  - **macOS keeps its own byte-identical copy** of each wallpaper in
    `~/Library/Containers/com.apple.wallpaper.extension.image/Data/Library/Caches`.
    Re-setting the same file adds no copy.

## Not verified

- **macOS cache trimming.** A copy whose file no Space uses any more was still
  in that cache minutes later. If macOS never trims it, it grows by one
  render's HEICs per day: about 27 MB on this Mac (3420×2224 plus 1920×1080).
  To watch it:
  `ls ~/Library/Containers/com.apple.wallpaper.extension.image/Data/Library/Caches/*.heic | wc -l`.
- **macOS screen sizes over time.** The sizes-seen list only grows. A size
  that never comes back, for example after changing display scaling, keeps
  being rendered daily until it's removed from `screens`.
- **Windows `tick`.** It has never run on Windows:
  - `schtasks /XML` accepting this XML;
  - re-registering the task from inside its own run;
  - rendering through the windowless build;
  - a standard user registering the wake trigger (if refused, `tick` logs it
    and registers without it).
- **Windows after sleep.** The first PC run did not update overnight. The
  catch-up triggers are meant to fix that, but haven't been confirmed.
- **Windows scaled displays.** Whether monitor sizes come back in physical
  pixels is untested (`sky monitors` prints what it sees).
- **Windows installers.** None has run on Windows: `get.ps1` (download and
  install), `Install.cmd` / `Uninstall.cmd` (double-click), and the town
  question in install.ps1. Checked from here: Open-Meteo's place search
  returns name, region, country and coordinates; the GitHub ZIP unpacks to
  `sky-wallpaper-main\windows\install.ps1`; the scripts are ASCII; the
  `.cmd` files have CRLF line ends (kept by `.gitattributes`).
