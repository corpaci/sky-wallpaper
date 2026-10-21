# Notes

Evidence behind the README: how the pieces work, what was checked, what was
not.

## How it works

**Frames.** 14 frames at fixed sun altitudes (−14°, −7°, −3°, 0.5°, 5°, 14° on
each side of noon, plus noon and midnight), so they bunch around sunrise and
sunset, where the sky changes fastest. The sun follows a sine arc between the
given sunrise and sunset. Colors are blended in OKLab and dithered to 8 bits
so slow gradients don't band. Rendering is deterministic: two runs with the
same size, times and seed produce byte-identical PNGs (checked for both
renderers, and from a fresh clone). The HEIC is not byte-identical between
packs of the same frames: about 0.5 KB near the start of the file differs.

**macOS format.** A multi-image HEIC. The first image carries XMP
`apple_desktop:h24` (namespace `http://ns.apple.com/namespace/1.0/`): a base64
binary plist `{ti: [{t: fraction of day, i: image index}], ap: {l, d}}`.

**Windows.** `install.ps1` compiles `windows/src/*.cs` twice with
`%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe`: once as `sky.exe`
(console) and once as `sky-apply.exe` (windowless, so nothing flashes). It
renders into a fresh `frames-<timestamp>` folder each time, because Windows
caches wallpapers by path. The task has one daily trigger per switch time and
one at logon, with "run as soon as possible after a missed start" on, which
covers sleep. `sky-apply.exe apply` sets each monitor's frame through
`IDesktopWallpaper`, and skips monitors that already show the right frame.

## Verified

On macOS 26.6.2, M3, Swift 6.3.3, Mono 6 (Roslyn csc 3.9):

- **HEIC metadata.** The namespace and the `l`/`d` keys match Apple's own
  `/System/Library/Desktop Pictures/Sonoma.heic`. Apple's time-based wallpapers
  download on demand, so there is no local `h24` file to compare against. The
  `ti`/`t`/`i` keys and local-clock `t` come from the open-source
  [wallpapper](https://github.com/mczachurski/wallpapper) encoder.
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
- **C# port.** Compiles with `-langversion:5` (the level of Windows' built-in
  compiler) in console and windowless builds, with no warnings. Against the
  Swift renderer, at most 0.012% of color values differ, each by one step out
  of 255, on an October day (07:20–17:55) and a summer day (05:05–20:55).
  Schedules are identical.
- **Frame choice.** Tested with `sky frame` on two rendered sizes: it wraps
  past midnight, switches exactly on the minute, and uses the closest aspect
  ratio for other monitor sizes.

## Not verified

- **macOS local time.** It is unconfirmed that macOS reads `t` as local time,
  not UTC. To check, install it and compare the frame on screen with
  `heicpack --inspect` for the current time.
- **macOS cache.** Replacing a file at the same path may not refresh the
  wallpaper. That is why output names carry the date.
- **Windows compiler.** The built-in `csc.exe` is the old pre-Roslyn C# 5
  compiler, not the one tested here.
- **Windows runtime.** The `IDesktopWallpaper` calls are untested, and so is
  whether monitor sizes come back in physical pixels on scaled displays
  (`sky monitors` prints what it sees).
- **Windows task.** Registering the task without admin rights, and triggers
  firing on time and after sleep, are untested.
