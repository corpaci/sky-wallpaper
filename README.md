# Wallpaper

A dynamic macOS wallpaper you own end to end: a renderer that paints one day of
a layered mountain landscape (14 frames, night through dawn, noon, sunset and
back), and a packer that turns any set of stills into a time-of-day (`h24`)
dynamic HEIC. Plain Swift, no dependencies, no network.

## Why it is cheap

macOS shows one still frame and swaps it at the listed times, 14 times a day.
Between swaps the desktop is a static picture: no app running, no animation,
no per-frame GPU work. The cost is one hardware HEVC decode per swap. Live and
video wallpapers redraw constantly and cost far more.

## Make it

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

## Install it

System Settings → Wallpaper → add a photo → pick `out/sky-2560x1664-….heic`,
and choose the dynamic option in the menu next to it. Repeat on the external
display with the `1920x1080` file. Each display has its own wallpaper.

The `light` and `dark` stills (noon and midnight) are what macOS shows if you
pick its light/dark modes instead of dynamic.

## Use your own images

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

## Layout

- `Sources/wallframes/`: the renderer. `Scene.swift` holds the sun model,
  palettes (one keyframe per sun altitude, morning and evening variants), and
  landscape. `Color.swift` holds OKLab blending and noise.
- `Sources/heicpack/`: manifest parsing, packing, and inspection.
- `build/`: rendered frames (PNG, about 3.8 MB each). Safe to delete.
- `out/`: the wallpapers.

Nothing is installed anywhere. Deleting this folder removes it all, except a
wallpaper you have set, which macOS keeps referencing at its path.

## Verified on this Mac (macOS 26.6.2, M3)

- **Metadata format.** The `apple_desktop` XMP namespace and the `l`/`d`
  light/dark keys match Apple's own `Sonoma.heic`. Apple's time-based
  wallpapers download on demand, so no `h24` file exists on disk to compare
  against. The `ti`/`t`/`i` keys and the local-clock `t` (fraction of the day)
  come from the open-source `wallpapper` encoder.
- **Read-back.** Both outputs decode through ImageIO with all 14 images and the
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
  night sky, use `QUALITY=1.0`.

## Not verified yet

- **Switch times.** It is unconfirmed that macOS switches frames at these
  local times (and not UTC). Install it, then check that the frame on screen
  matches `heicpack --inspect` for the current time.
- **Cache refresh.** It is unconfirmed whether macOS refreshes a wallpaper
  whose file was replaced at the same path. Output names carry the date for
  that reason. If a same-day rebuild doesn't show up, re-pick the file.
