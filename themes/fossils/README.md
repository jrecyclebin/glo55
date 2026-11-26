# Fossils of the Machines for Glo55

The Enlightenment **E16** theme *Fossils of the Machines* by **DarkAlloy**
(scarab@egyptian.net, <http://darkalloy.catarsys.net>), running as a Glo55 theme: rusted
steel pipes, a glowing orb in the corner of every window, beveled rusty buttons.

    glo55 -c config.toml    # after `make install`, with `theme = "fossils/theme.toml"`
    CONFIG=test/config-fossils.toml test/run-nested.sh         # from the source tree (a safe nested X)

or put `theme = "fossils/theme.toml"` in your own config.

## Credits and licence (please read)

All the art here was drawn by DarkAlloy. The upstream `ABOUT/README` (included, unmodified) says:

> All other graphics in this etheme file were created by DarkAlloy with The GIMP and are free to
> use for **non-commercial use**. Permission is granted to those who wish to "clone" this theme
> for a different theme, skin, OS, program, etc... provided that credit be given to the original
> author. If you plan to make money from this theme or its contained graphics you can forget it.

This port is a "clone" of the theme for another window manager, and this README is the credit:
the window frames, buttons, pager, desktop image and toolbar here are DarkAlloy's art. It is
for **non-commercial use only**; keep the credit if you redistribute it.

What was left out on purpose:

- `fotm-watcher.jpg` (the image behind its logo is by Travis Charest) and `fotm-crow.jpg` (by Dave
  McKean), which the upstream credits to other artists, and `fotm-conceptions.jpg`, which is
  third-party art too. They are the backgrounds of E16's desktops 1-4 and are not bundled, nor
  is `fotm-logo.jpg` (desktop 4 / the splash). Only `fotm-moon.jpg` (desktop 0) is.
- `Envision.ttf` (Margo Chase's Envision, "all rights reserved", used by the package's About
  page only). The theme's own UI font, `ttfonts/Satis.ttf` ("Dissatisfaction"), **is** bundled:
  `fonts.theme.cfg` uses it for every border, dialog and menu text, and the package carries no
  separate licence for it. If you want a repository with no doubt about it, delete
  `ttfonts/Satis.ttf` and the `font_files` line in `theme.toml`; the titles then fall back to
  the system's default font.
- E16 things a window manager like Glo55 has no use for: cursors, menus, tooltips, epplets, the
  XMMS controls, the dock, the init splash, the focus list, the dragbar. (The unused imageclass
  files that remain are only there because `tools/e16_border_to_toml.py` reads
  `imageclasses/*.cfg`.)

## Provenance

- Upstream: `Fossils_of_the_Machines.etheme` from the E16 theme archive,
  <https://themes.effx.us/packages/e16/Fossils_of_the_Machines.etheme> (1,038,268 bytes, sha256
  `1f406345a95d5264d16155b2f523119baa62df5145b6e59fb9e03d4b7008488c`; "Maintained at
  themes.effx.us", `$Id: default.cfg 64 2009-07-03`). An `.etheme` is a gzipped tar of E16 config
  files (`borders/*.cfg`, `imageclasses/*.cfg`, `textclasses.cfg`, `desktops.cfg`, ...) and an
  `artwork/` tree.
- Copied **unmodified**: `artwork/` (borders, atoms, dialogs, pager, iconbox, `default_*.png`,
  the moon background), the config files (`borders/`, `imageclasses/`, `borders.cfg`,
  `textclasses.cfg`, `fonts.theme.cfg`, `desktops.cfg`), `ttfonts/Satis.ttf`, `ABOUT/README` and
  `ABOUT/MAIN`.
- Added: `theme.toml`, this README, and `glo55/` with the two titlebar buttons the theme does
  not have (below), made by `tools/fossils_button_art.sh`.

## How E16 maps onto Glo55

`[windows.*]` in `theme.toml` was generated from `borders/default.cfg` by
`tools/e16_border_to_toml.py` (`python3 tools/e16_border_to_toml.py themes/fossils default`;
the script now also reads an unpacked `.etheme`). Added by hand: the stick and fullscreen buttons,
the text colours, the toolbar and the desktop.

| E16 | Glo55 |
| --- | --- |
| `__BORDER_SIZE_*` 18/1/16/4 | `[windows.insets]` |
| border parts, percentage + absolute coordinates (bottom-right inclusive; fixed-size parts have no bottom-right) | `left/top/right/bottom = { edge, ratio, offset }` |
| `B_FRAME` imageclass: `frame_normal.png` / `frame_active.png` | `path = "$img_b_frame"`, switched by `[windows.focused]` (grey orb / red orb); the sticky variants have no counterpart |
| `__EDGE_SCALING 32 2 0 0` (title pipe), `__FILLRULE __TILE` (resizers, the black edge line) | `scale = "slice"`, `slice = [32, 0, 2, 0]`; `scale = "tile"` |
| `__KEEP_WHEN_SHADED` | `unless = "collapsed"` on the parts that are not kept: a rolled-up bar is the 16px pipe with close, minimise, stick, fullscreen and the end cap |
| `ACTION_KILL` / `ACTION_ICONIFY` | `action = "close"` / `"collapse"` (the "minimise" button) |
| `TEXT1` textclass: black text with a light shadow (unfocused), white with a black shadow (focused), centred | `title_color` / `title_shadow` vars, `[windows.focused]` |
| `font-default` = "Satis/9" | `font_files` + `font = "Dissatisfaction"`, size 13 (E16's 9pt at 96 dpi is 12px; 13 matched the original's look better at this pipe height) |
| the shaped frame (orb, 71px left edge, 1px black line) | `shaped = true` |
| `desktops.cfg` desktop 0 `FOTM_MOON`, a 1024x1024 layer scaled to the desktop | `background` + `background_scale = "stretch"` (new), `desktop_color = "#000000"` |
| the other four desktops (a different image per desk) | not mapped: Glo55 has one background |
| `HILITED` / `CLICKED` images (`close2.png`, ...) | unused: frame buttons have no hover state yet |
| the move / resize action parts, `STICKY` | drawn but not wired: no mouse move/resize, no sticky windows |

### Buttons: minimise, stick, fullscreen

The theme has close (x=56) and iconify/minimise (x=80) on the left, as in E16. It has no stick
or fullscreen button, so two were drawn on the right of the pipe (`tools/fossils_button_art.sh`):
the theme's own `close.png` barrel with the X painted out (a stretched copy of an untouched
column) and a new 1px glyph in the ink of the theme's own glyphs: a ring with a dot (stick: a
decoration, as in Blue Steel) and a small window (**fullscreen**, `action = "fullscreen"`, the
rightmost button, left of the pipe's end cap).

### Toolbar

E16 has no top bar. This one is the theme's title pipe (`tbar.png`, 16px, the same as the
windows') with the clock on the left end (the title text style, white on the pipe's
focused monitor) and the pipe's end cap (`terminator.png`) on the right; the workspaces are
buttons embedded between, made of the dialog button art (`dialogs/button_*.png`, the beveled
rusty buttons of the settings dialog, 9-sliced):

- idle: `button_in.png`, the dark recessed face; label dim, brighter when the workspace has windows
- hover: `button_out.png`, the raised metal face
- pressed: `button_in.png`
- current workspace: `button_over.png`, the lit, rust-glowing face, outlined by the pager's own
  white selection frame (`pager/pager.png`)

(Sizes: the buttons are the full 16px of the bar, so they are flush with the pipe; the 60x60 art is
stretched vertically between 4px bevels.)

### Rolled-up windows

A rolled-up window is the 16px pipe: tbar, close, minimise, stick, fullscreen and the end cap.
E16's own shaded look has no orb either (`B_FRAME` is not kept when shaded), so the first 56px of
a rolled bar are empty (the frame is shaped).

## Not done

- Hover states of the frame buttons (`close2.png`, `iconify2.png` exist; milestone 2 in NOTES).
- The theme's other borders (E16 picks a border per window class; Glo55 has one frame).
- Pager, iconbox, dock, dialogs, menus, tooltips, cursors: no counterpart in Glo55 (the pager and
  dialog art is only used for the toolbar).
