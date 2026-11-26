# Fresh Breath

Four palettes — Sedona, Painted Desert, Chillwave and Office Print — sharing
one layout (`layout.toml`, via `extends`). A thin sheet of metal under glossy
paint, with the brushed grain showing through, lit from the top left, every
edge leaning 19°. The title bar floats a few pixels above the frame; a second
plate (the register slip) sits behind it in the cool accent; four speed slashes
step from warm to cool on a focused window (two grey slashes, no accent, when
it is not).

The art is cut from J's layered SVGs (the mockup 2× chrome, downscaled with
LANCZOS). Text-bearing plates (title, clock, workspace tabs, the rail) are
rebuilt from the plate's own gloss profile and the palette grain, because the
baked-in letters span almost the whole plate. Button hover and pressed faces
come from the parts-sheet "states" strip, recolored per palette; close turns
the title-bar colour on hover and the slip colour when pressed, as on the
sheet. `tools/fresh_breath_art.py` regenerates everything.

## Button order

The title-bar buttons are, left to right, **collapse, fullscreen, close** —
the mockup's visual order, so close is rightmost. (Earlier Glo55 themes put
fullscreen at the far right, as J asked then.) The three action elements in
`layout.toml` (`31_collapse`, `34_fullscreen`, `37_close` and their
hover/pressed overlays) can be reordered if you want fullscreen last again.

The square plate to the left of the title is decoration only.

## Fonts

[Barlow](https://github.com/jpt/barlow) and Barlow Condensed (SemiBold
Italic), SIL Open Font License 1.1; the licence is in `fonts/OFL.txt`. Titles,
the clock and the workspace labels use Barlow Condensed; Barlow itself is
bundled for anything that wants a wider cut.

## Wallpapers

Each palette has a 2880×1800 desktop in the mockup's spirit (moon, palm,
horizon and sea, in the palette's colours, with the textured grain). The
mockup wallpaper was a loose sketch with windows and a caption on top; these
are a cleaner, full-bleed version of the same scene, with a little moonlight
and grain, and no chrome.

## Soft shadows

The mockup plates stand a few pixels off the wallpaper and cast a soft drop
shadow. Glo55 draws to a non-composited X11 server and uses the 1-bit X SHAPE
extension for the slanted edges and the gaps between floating plates: a
semi-transparent shadow has nothing to blend against but the frame pixmap, so
it would read as a dark halo. The shipped art keeps a tight anti-aliased
fringe around each plate and relies on the painted thickness edges for depth.

## Palettes

| Palette        | Config                              | Title paint | Notes |
|----------------|-------------------------------------|-------------|-------|
| Sedona         | `test/config-fresh-breath-sedona.toml`   | amber       | |
| Painted Desert | `test/config-fresh-breath-painted-desert.toml` | peach | |
| Chillwave      | `test/config-fresh-breath-chillwave.toml` | `#ff5f8a`  | slip `#4ff0e6`, the paints from the parts sheet |
| Office Print   | `test/config-fresh-breath-office-print.toml` | dusty coral | |

    ./glo55 -c test/config-fresh-breath-chillwave.toml
    # or:  CONFIG=test/config-fresh-breath-sedona.toml test/run-nested.sh
