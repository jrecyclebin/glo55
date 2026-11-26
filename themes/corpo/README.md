# CORPO for Glo55

A vaporwave / rusted alternate Win95 theme, by **J** (the idea, the mockup and every pixel of
`assets/`), pulled together into a Glo55 theme. The reference mockup is
`reference/j-corpo-mockup.png`.

    glo55 -c config.toml   # after `make install`, with `theme = "corpo/theme.toml"`
    CONFIG=test/config-corpo.toml test/run-nested.sh       # from the source tree (a safe nested X)

or put `theme = "corpo/theme.toml"` in your own config.

## What came from where

- `assets/` is J's art, unmodified: the window frame (`win-*.png`), the taskbar (`bar-*.png`) and
  three desktop backgrounds (`bg-*.gif`). `bg-ruins.gif` is the desktop in the mockup and the
  default; `bg-rain.gif` and `bg-truck.gif` are bundled as alternatives (set `background =
  "assets/bg-rain.gif"`). The GIFs are animated; Glo55 shows their first frame. The mockup's
  content art (`page-news.png`, the two icons) is not bundled.
- `fonts/`: `pixeltimes.ttf` (the serif pixel font of the mockup's title and page text; J's
  `pixeltimes.woff2` converted with fontTools, because Xft cannot load woff2) and
  `roundedsquare.ttf` (the clock's LCD digits; "RoundedSquare" by Donatien Kalvin, CC0).
  **Pixel Times is (c) 2020 Vasily Draigo aka Daymarius, "all rights reserved"**: it came with
  J's assets and is bundled here as such, so check you may redistribute it before you publish the
  repository (delete `fonts/pixeltimes.*` and the `font_files` entry, and the titles fall back to the
  system font).
- `glo55/` is the only part drawn for Glo55, by `tools/corpo_art.sh` (ImageMagick): the pieces
  the mockup did not have, below.
- `theme.toml`: the frame and toolbar assembled from those pieces.

## The window

The frame is exactly the assets: a 25px title bar (`win-barleft` 46px with the dotted ornament,
`win-bartile` tiled, `win-barright` 5px), 3px edges and corners, no scaling or smoothing anywhere
(images are drawn 1:1 or tiled). Insets 3 / 3 / 25 / 3. The title is Pixel Times at 12px (the size at which the
text is as wide as in the mockup), **upper-cased** with the new text key `transform = "upper"` (also
`"lower"`), starting 24px in as in the mockup. A rolled-up window is the bar alone.

Buttons, on J's purple 17x15 `win-button.png`, 2px apart at the right end of the bar, left to
right: **close** (X), **stick** (a ring with a dot; decorative, as in the other themes),
**collapse** (a bar low on the dark half of the face: rolls the window up), **fullscreen**
(a small window; `action = "fullscreen"`, the rightmost button, like mod+f). The mockup's one
button (a purple face with a slate rectangle) sits where fullscreen does. The glyph colour is a
light periwinkle from the palette's own blues.

### The inactive state

`glo55/inactive/` is every frame piece and button with the colours remapped to 80% brightness
and 30% saturation (a per-colour mapping, so dithers and checker rows stay crisp). The title
text turns from white to a slate grey (`#8d96ab`). The theme's `[windows.focused]` state points
`$win` / `$btn` back at the full-colour art.

## The toolbar (top of the screen, 30px)

Built from the `bar-*` pieces, which were drawn for a bottom bar. They read correctly at the top
as they are: the lit green line is on top and the dithered purple shadow below, next to the
windows, so nothing was flipped.

- **Left:** `bar-left` (56px, the ornament) as a cap, then the **workspaces** as recessed slots
  (`bar-down.png`, 9-sliced, 20px high, centred in the bar), in Pixel Times, upper-cased.
  Idle slots are dim periwinkle on dark green; hover is the same slot lifted; pressed is darker;
  the **current workspace** is the slot turned amber (the clock's colour) with an amber label.
- **Right:** the **clock** in J's recessed LCD slot (`bar-buttonl` + tiled `bar-buttonm` +
  `bar-buttonr`), amber RoundedSquare digits with antialiasing off, like the mockup. `bar-right` closes
  the bar.
- Not used: the mockup's taskbar clutter, `bar-sep` (the slot-start bracket), the CORPO logos
  (`bar-logo*.png`; they are in `assets/`). The workspaces being on the left and the clock on the
  right is plain theme config: the workspace region has `align = "left"` and the clock is a text element
  anchored to the right edge.

### Generated parts (`tools/corpo_art.sh`)

| file | what |
| --- | --- |
| `glo55/inactive/win-*.png` | the frame pieces, dimmed and desaturated |
| `glo55/active/btn-{close,stick,collapse,fullscreen}.png` | the buttons on `win-button.png`, glyphs 1px |
| `glo55/inactive/btn-*.png` | the same, dimmed |
| `glo55/slot-hover.png` / `slot-pressed.png` | `bar-down.png` lifted 60% / darkened to 65% |
| `glo55/slot-active.png` | `bar-down.png` with its green `#0A2307` turned amber `#2B1A04` |

## Desktop

`background = "assets/bg-ruins.gif"` with the new `background_scale = "cover"`: the image is
scaled, keeping its aspect ratio, until it covers the screen, and the overflow is cropped
equally on both sides. It is nearest-neighbour (as `stretch` always was), so the pixel art stays
sharp-edged: every screen pixel is a pixel of the source. At non-integer factors some of the
source pixels are 2px wide and some 3px, as in the mockup's own scaled-up background.

## Not done

- Hover and pressed art for the title-bar buttons (`win-buttondown.png` exists; Glo55 has no
  frame-button states yet).
- The animation of the GIF backgrounds (the first frame is shown).
- The mockup's page content, its taskbar entries and icons.
