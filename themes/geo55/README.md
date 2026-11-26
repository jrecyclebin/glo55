# geo55

A Win95-inspired theme from J's floating desk-band screenshot (formerly Desk Band)
(`reference/j-win95-bands.jpg`). Every edge is a classic 2-pixel raised or
sunken bevel on silver (`#c0c0c0`) face, with white / `#dfdfdf` highlights
and `#808080` / black shadows. The art is 1:1 pixels; nothing is filtered.

## Toolbar

The top band in the shot: a compact silver bar that **floats centred at the
top**, rather than spanning the monitor. The engine shrinks the toolbar
window to its contents (`align = "center"`, `auto_width = true`) and grows
it with the workspace list; the work area is still the full strip under the
bar's 30px height, so windows never sit beside it and the desktop `#3b6ea5`
shows on both sides.

Left to right:

1. A dotted gripper (decorative).
2. A small computer icon (decorative).
3. A sunken LED **CPU meter** — this one is live. Once a second Glo55 reads
   `/proc/stat` and sets `$cpu` (0–100); the green LEDs fill that fraction
   of the well. Harmless if `/proc/stat` is missing (the well stays empty).
4. The clock and date in bold 8pt-ish W95FA, `HH:mm:ss  ddd, DD MMM, YYYY`
   (set in `test/config-geo55.toml`).
5. The workspaces as small Win95 toggle buttons: raised when idle, a dotted
   focus cue on hover, sunken when pressed, sunken with a dithered face when
   active, and a little occupied dot when the workspace has a window.

Sections are separated by etched vertical dividers.

## Windows

The title bar is the compact silver band from the bottom-right of the shot:
a dotted gripper on the left, black 8pt text (grey `#808080` when unfocused),
and classic 16×14 caption buttons. The button order is collapse, fullscreen,
close, with close rightmost (the same as Fresh Breath; the three action
elements in `theme.toml` can be reordered).

A 4px raised window edge goes **all the way around** the title bar and the
client as one unit: 2px of outer EDGE_RAISED plus 2px of inner EDGE_SUNKEN
around the client (the same on the bottom and both sides, not only at the
top). Insets are L4 T22 R4 B4; a rolled-up window is a 22px raised bar.

## Font

**W95FA** by Alina Sava (FontsArena) — a scalable recreation of Windows 95's
MS Sans Serif, bundled as `fonts/W95FA.otf` under the SIL Open Font License
1.1 (`fonts/OFL.txt`). It is not a Microsoft font. The theme opens it at
13px with antialiasing off (11px dropped thin strokes such as colons).

## Wallpaper

No image. The root is painted the desktop blue sampled from the shot,
`#3b6ea5` (59, 110, 165).

## Running

```
./glo55 -c test/config-geo55.toml
# after make install: put theme = "geo55/theme.toml" in your config.toml
```
