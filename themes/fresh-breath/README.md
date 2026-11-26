# Fresh Breath

An original glo55 theme by J, in four palettes (Sedona, Painted Desert,
Chillwave and Office Print) that share one layout (`layout.toml`, pulled in
with `extends`). Each palette's `theme.toml` only sets four colours; its art
lives in its own `art/`.

Windows are floating plates that lean 19°: a stone, the title plate with its
register slip (a second plate in the cool accent, 3px above and 4px right),
four speed slashes stepping from warm to cool, and the onyx button plate,
all 4px above the frame. The frame is 5px wide with a 9px reveal wedge on the
left. An unfocused window keeps a plainer plate and two slashes. The toolbar
has the clock plate, the slashes, a rail across the screen carrying the
focused window's title, and the workspace plates leaning into each other.

## Where the art comes from

Everything is cut from J's mockup SVGs, whose layers are PNGs at twice the
mockup's size, by `make-art.py`:

    python3 make-art.py DIR   # DIR holds fresh-breath-<palette>.svg

It places each layer on the mockup's 1x grid, crops the part, halves it and
writes `<palette>/art/` and `<palette>/theme.toml`. Sizes in `layout.toml`
are the mockup's, pixel for pixel. Plates that carry text in the mockup
(title, clock, rail, workspace plates) have the text painted out from the
plate's own paint and grain, and glo55 draws the live text on top. Title
plates are 9-slice images, so their middle stretches with the window.

## Buttons

Left to right: collapse, fullscreen, close, as in the mockup. Close turns the
title paint on hover and the slip paint when pressed, as on the Window Parts
sheet. The sheet only shows close, so collapse and fullscreen just lift on
hover and sink when pressed. A rolled-up window shows a chevron in place of
the box and a thin bar of frame under its title row. The stone left of the
title is decoration.

## What differs from the mockups

- The title plate's length follows the window (20% of its width plus 120px),
  because glo55 cannot measure the title to make the plate hug it. A title
  that does not fit ends in an ellipsis.
- No soft drop shadows. glo55 draws to a non-composited X server and cuts the
  slanted plates with the 1-bit X SHAPE extension, so a half-transparent
  shadow would only blend into black. Plate edges are hard.
- The toolbar is an opaque window, so the space around its plates is a tile
  of the palette's sky and print grain.
- The menu design and the wallpaper are not used: the desktop is a flat
  `desktop_color`, the palette's sky.

## Fonts

Barlow Condensed SemiBold Italic, SIL Open Font License 1.1 (`fonts/OFL.txt`).
