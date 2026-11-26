# BlueSteel for Glo55

The Enlightenment **E16** (DR16 era) *BlueSteel* theme, by Daniel Erat ("hunchback",
erat@cats.ucsc.edu), running as a Glo55 theme. Use it with

    CONFIG=test/config-bluesteel.toml test/run-nested.sh      # or: glo55 -c test/config-bluesteel.toml

## Provenance

- Upstream: `e16-theme-BlueSteel-0.16.8-0.03.tar.gz` (2009-01-03), part of the E16 themes
  on SourceForge:
  <https://sourceforge.net/projects/enlightenment/files/e16-themes/>
  (downloaded from `https://prdownloads.sourceforge.net/sourceforge/enlightenment/e16-theme-BlueSteel-0.16.8-0.03.tar.gz`,
  sha256 `97f12649385613ab29d13eb2c7a61400e19c199f24499416d78a0216f2c619f5`).
- The tarball contains `BlueSteel.etheme` (itself a tar of the theme). Everything under
  `borders/`, `dialogs/`, `iconbox/`, `pager/`, `backgrounds/`, `ttfonts/` here is copied
  **unmodified** from it, along with the original `borders/*/border.cfg` as
  `border.cfg.upstream`, the original `README` as `README.upstream`, `ABOUT` and `COPYING`.
  No art was redrawn. The one addition is `glo55/`: the toolbar's embedded workspace-button faces
  (`well_up.png`, `well_down.png`, `well_up_hover.png`, `well_dark_hover.png`), cut from the dialog buttons
  (shadow removed, bevel turned inset) and `darkbg.png` (brightened for hover) by
  `tools/bluesteel_button_art.sh`.
- Only the PNGs/fonts/background actually referenced by `theme.toml` matter; the rest of the
  copied directories is there so the theme stays recognisable and complete.

## Licence

`COPYING` (from the upstream tarball) is an MIT licence with an acknowledgment clause:
"Copyright (C) 2000-2005 Carsten Haitzler, Geoff Harrison and various contributors", free use,
copy, modify, merge, publish, distribute, sublicense, sell, *provided* the copyright notice and
permission notice are included, and "acknowledgment shall be given in the documentation,
materials and software packages that this Software was used". This README is that
acknowledgment: this theme uses the Enlightenment E16 BlueSteel theme art. (Fedora lists the
e16-themes package as "MIT with advertising"; T2 SDE metadata says BSD; the text in COPYING is
what applies.) The ABOUT file credits the theme to Daniel Erat. `ttfonts/vixar.ttf` ("Vixar
ASCI") ships inside the theme and has no separate licence file; it is distributed under the
same package terms upstream.

## How E16 maps onto Glo55

`theme.toml`'s `[windows.*]` elements were generated from `borders/DEFAULT/border.cfg` by
`tools/e16_border_to_toml.py` (run `python3 tools/e16_border_to_toml.py themes/bluesteel
DEFAULT`); the toolbar is E16's title-bar art (tab, trim, strip) with the workspaces as flush,
embedded buttons made from the theme's dialog buttons (current workspace: the dark inset panel `darkbg.png`
plus the pager's `selected.png` outline), and the
desktop is hand-assembled from the same theme's other art.

| E16 | Glo55 |
| --- | --- |
| `__BORDER_SIZE_*` 10/10/20/10 | `[windows.insets]` |
| border part (`TOPLEFT_*` / `BOTTOMRIGHT_*`, percentage + absolute) | element `left/top/right/bottom = { edge, ratio, offset }` |
| imageclass `NORMAL` / `NORMAL_ACTIVE` (`*_bg.png` / `*_fg.png`) | `path = "...$sfx.png"`, `sfx` = `bg`, `fg` in the `focused` state |
| part with min = max size | `scale = "none"`; flexible parts (title bar, top, left, right, bottom) `scale = "stretch"` |
| `ACTION_KILL` / `ACTION_ICONIFY` | `action = "close"` / `"collapse"` |
| `ACTION_MAX` | the rightmost button: toggles **fullscreen** (`action = "fullscreen"`, E16's maximize art, unmodified) |
| `ACTION_STICK`, move/resize parts | drawn but inert (no sticky; the stick art sits one slot left of the fullscreen button; mouse move and resize are milestone 2) |
| `TITLE_TEXT` tclass (centred, white/grey, shadow) | text element with `shadow`, `$title_color` |
| shaped border (transparent trims) | `shaped = true` |
| `CLICKED` images (`*_cl.png`), hovered states | not used yet (clicked/hover are milestone 2) |
| `backgrounds.cfg` tiled JPEG | top-level `background` |
| `font-border "vixar/12"` | `font_files` + `font = "Vixar ASCI"`, size 12 |
