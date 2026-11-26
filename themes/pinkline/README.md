# pinkline

A minimalist white and hot-pink theme from J's "pixel perfect" desktop
screenshot. It takes only two things from it: the window panels and the
toolbar along the bottom of the screen. Pink is `#f70087`, sampled from the
shot.

## Windows

Each window sits in a white panel: 4px on the sides, 8px on top with a small
13x5 pink tab in the top-right corner, and along the bottom 3px of white, a
2px pink line with a little white notch near the left, and a 5px black drop
edge. There is no title text and there are no buttons; the keyboard closes,
collapses and fullscreens. Unfocused windows have a grey tab and line, so the
focused one is the pink one. A rolled-up window is a 16px bar of the same.

## Toolbar

The bar lives at the bottom of the screen and hides itself
(`position = "bottom"`, `auto_hide = true`). Hidden, it is the 7px strip from
the shot: the pink line over black, and only that strip is kept clear of
windows. Put the pointer on it and it slides up to 26px over the windows: the
line on top, the workspaces on the left (an empty one grey, an occupied one
white, the current one a pink plate) and the date and time on the right, the
time in pink. It also comes up for 1.2 seconds after a workspace switch
(`reveal_ms`), and stays while the pointer is on it.

## Font

`fonts/pinkpixel.ttf` (PinkPixel) is a small 5-pixel capitals font drawn for
this theme, in the style of the shot's. `fonts/make-font.py` builds it from
the glyph grids in the script (needs FontForge's Python module). The theme
uses it at 8px, one grid pixel per screen pixel, with antialiasing off. Lower
case comes out as capitals.

## Art

`art/make-art.sh` draws both images with ImageMagick: `notch.png` (the white
tick on the pink lines) and `stone.png`, a seamless grey stone tile for the
desktop, standing in for the shot's moon photo.

## Running

```
./glo55 -c test/config-pinkline.toml
# after make install: put theme = "pinkline/theme.toml" in your config.toml
```
