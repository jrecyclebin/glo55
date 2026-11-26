module x11

import log

// xft.v - Xft font and text wrappers. Fonts are opened with XftFontOpenName
// (fontconfig patterns like "monospace:pixelsize=12") and text is always drawn
// with XftDrawStringUtf8 so UTF-8 just works.

pub struct XftFontHandle {
pub:
	name    string
	font    &C.XftFont = unsafe { nil }
	ascent  int
	descent int
	height  int
}

// open_font opens a fontconfig font pattern. Returns none if it can't be found.
// fontconfig never fails on an unknown family: it substitutes its closest
// match. So the family that was actually picked is checked: a name copied
// from a font picker ("Noto Sans Regular") is retried as family + style, and a
// name that still matches nothing is logged with the font that replaced it.
pub fn (c &X11Connection) open_font(pattern string) ?XftFontHandle {
	mut f := C.XftFontOpenName(c.dpy, c.screen, &char(pattern.str))
	if isnil(f) {
		return none
	}
	mut name := pattern
	want := requested_family(pattern)
	if !is_generic_family(want) && !family_matches(want, matched_family(f)) {
		mut fixed := false
		if alt := split_trailing_style(pattern) {
			mut g := C.XftFontOpenName(c.dpy, c.screen, &char(alt.str))
			if !isnil(g) {
				if family_matches(requested_family(alt), matched_family(g)) {
					log.info('font "${pattern}": no such family, using "${alt}" instead')
					C.XftFontClose(c.dpy, f)
					f = g
					name = alt
					fixed = true
				} else {
					C.XftFontClose(c.dpy, g)
				}
			}
		}
		if !fixed {
			log.warn('font "${pattern}": no installed font family "${want}"; fontconfig substituted "${matched_family(f)}" (check with: fc-match "${want}")')
		}
	}
	log.debug('font "${name}" opened as family "${matched_family(f)}"')
	return XftFontHandle{
		name:    name
		font:    f
		ascent:  f.ascent
		descent: f.descent
		height:  f.height
	}
}

// matched_family returns the family fontconfig actually picked for an open font
// ("" if unknown). fontconfig never fails on an unknown name: it silently
// substitutes its closest match, so this is how a wrong font name shows up.
pub fn matched_family(f &C.XftFont) string {
	mut fam := &u8(unsafe { nil })
	if C.FcPatternGetString(f.pattern, c'family', 0, &fam) == 0 && !isnil(fam) {
		return unsafe { cstring_to_vstring(&char(fam)) }
	}
	return ''
}

// add_app_font registers a font file (TTF/OTF/...) with fontconfig for this
// process only, so patterns by family name (e.g. "Vixar ASCI") find it.
pub fn add_app_font(path string) bool {
	return C.FcConfigAppFontAddFile(unsafe { nil }, &char(path.str)) != 0
}

pub fn (c &X11Connection) close_font(f XftFontHandle) {
	C.XftFontClose(c.dpy, f.font)
}

// ------------------------------------------------------- glyph fallback
//
// Xft draws a string with ONE font, so any character the font lacks (CJK in a
// Latin-only theme font such as Vixar, emoji and symbols in a text font)
// would show as an empty box. Like dwm and st, we look for a fallback font
// with fontconfig for each missing character, keep it in a cache, and draw the
// text one run per font.

const max_fallback_fonts = 24

// FallbackSet is the cache for one primary font.
pub struct FallbackSet {
pub mut:
	fonts   []&C.XftFont // fallback fonts opened so far (run font n -> fonts[n-1])
	by_rune map[int]int  // rune -> run font (0 = primary: nothing found, the box is drawn)
}

// FontFallbacks maps a primary font's pattern to its FallbackSet.
@[heap]
pub struct FontFallbacks {
pub mut:
	sets map[string]&FallbackSet
}

fn (c &X11Connection) fallback_set(f XftFontHandle) &FallbackSet {
	mut all := c.fallbacks
	if f.name !in all.sets {
		all.sets[f.name] = &FallbackSet{}
	}
	return all.sets[f.name] or { &FallbackSet{} }
}

fn (c &X11Connection) font_by_index(f XftFontHandle, set &FallbackSet, n int) &C.XftFont {
	if n <= 0 || n > set.fonts.len {
		return f.font
	}
	return set.fonts[n - 1]
}

fn (c &X11Connection) has_glyph(font &C.XftFont, r rune) bool {
	return C.XftCharIndex(c.dpy, font, u32(r)) != 0
}

// match_fallback runs one fontconfig query for a font with a glyph for r.
// The pattern starts from the primary font's own (size, weight, family
// preference). With allow_color false, colour bitmap fonts are excluded.
fn (c &X11Connection) match_fallback(f XftFontHandle, r rune, allow_color bool) ?&C.XftFont {
	pat := C.FcNameParse(&u8(f.name.str))
	if isnil(pat) {
		return none
	}
	cs := C.FcCharSetCreate()
	C.FcCharSetAddChar(cs, u32(r))
	C.FcPatternAddCharSet(pat, c'charset', cs)
	C.FcCharSetDestroy(cs)
	C.FcPatternAddBool(pat, c'scalable', 1)
	if !allow_color {
		C.FcPatternAddBool(pat, c'color', 0)
	}
	C.FcConfigSubstitute(unsafe { nil }, pat, 0) // FcMatchPattern
	C.XftDefaultSubstitute(c.dpy, c.screen, pat)
	mut result := 0
	m := C.FcFontMatch(unsafe { nil }, pat, &result)
	C.FcPatternDestroy(pat)
	if isnil(m) {
		return none
	}
	font := C.XftFontOpenPattern(c.dpy, m)
	if isnil(font) {
		C.FcPatternDestroy(m)
		return none
	}
	if !c.has_glyph(font, r) {
		C.XftFontClose(c.dpy, font)
		return none
	}
	return font
}

// find_fallback looks for a font with a glyph for r, preferring monochrome
// outline fonts. Colour fonts (emoji) are the last resort, and only with an
// Xft that can draw colour glyphs (2.3.5+; older versions raise X errors).
fn (c &X11Connection) find_fallback(f XftFontHandle, r rune) ?&C.XftFont {
	if font := c.match_fallback(f, r, false) {
		return font
	}
	if C.XftGetVersion() >= 20305 {
		return c.match_fallback(f, r, true)
	}
	return none
}

// choose_font picks the run font for a rune: 0 for the primary font, else the
// index of a (cached or newly opened) fallback font.
fn (c &X11Connection) choose_font(f XftFontHandle, mut set FallbackSet, r rune) int {
	if c.has_glyph(f.font, r) {
		return 0
	}
	if idx := set.by_rune[int(r)] {
		return idx
	}
	// reuse an already opened fallback before asking fontconfig again
	for i, ff in set.fonts {
		if c.has_glyph(ff, r) {
			set.by_rune[int(r)] = i + 1
			// the same one-line story as a freshly opened fallback, so the log
			// records every rune that is not in the primary font
			log.debug('glyph fallback for U+${int(r):04X}: font family "${matched_family(ff)}" (reused)')
			return i + 1
		}
	}
	mut idx := 0
	if set.fonts.len < max_fallback_fonts {
		if font := c.find_fallback(f, r) {
			set.fonts << font
			idx = set.fonts.len
			log.debug('glyph fallback for U+${int(r):04X}: font family "${matched_family(font)}"')
		} else {
			log.debug('glyph fallback for U+${int(r):04X}: no installed font has it')
		}
	}
	set.by_rune[int(r)] = idx
	return idx
}

// TextPiece is a run bound to the font that draws it.
struct TextPiece {
	text string
	font &C.XftFont
}

// pieces splits s into per-font runs (most strings are a single run).
fn (c &X11Connection) pieces(f XftFontHandle, s string) []TextPiece {
	mut set := c.fallback_set(f)
	runes := s.runes()
	mut fonts := []int{len: runes.len}
	mut any_fallback := false
	for i, r in runes {
		fonts[i] = if int(r) < 0x80 && c.has_glyph(f.font, r) {
			0
		} else {
			c.choose_font(f, mut set, r)
		}
		if fonts[i] != 0 {
			any_fallback = true
		}
	}
	if !any_fallback {
		return [TextPiece{s, f.font}]
	}
	mut out := []TextPiece{}
	for run in group_runs(runes, fonts) {
		out << TextPiece{run.text, c.font_by_index(f, set, run.font)}
	}
	return out
}

fn (c &X11Connection) piece_width(p TextPiece) int {
	mut gi := GlyphInfo{}
	C.XftTextExtentsUtf8(c.dpy, p.font, p.text.str, p.text.len, voidptr(&gi)) // GlyphInfo has XGlyphInfo's layout
	return int(gi.x_off)
}

// text_width measures a UTF-8 string in pixels (fallback fonts included).
pub fn (c &X11Connection) text_width(f XftFontHandle, s string) int {
	if s.len == 0 {
		return 0
	}
	mut w := 0
	for p in c.pieces(f, s) {
		w += c.piece_width(p)
	}
	return w
}

// draw_text draws UTF-8 text with its baseline at (x, y) onto a drawable
// (window or pixmap) using color rgba (each 0..255). Characters missing from
// the font are drawn with fallback fonts.
pub fn (c &X11Connection) draw_text(drawable u64, f XftFontHandle, s string, x int, y int, r u8, g u8, b u8, a u8) {
	if s.len == 0 {
		return
	}
	visual := C.XDefaultVisual(c.dpy, c.screen)
	cmap := C.XDefaultColormap(c.dpy, c.screen)
	draw := C.XftDrawCreate(c.dpy, drawable, visual, cmap)
	if isnil(draw) {
		return
	}
	rc := C.XRenderColor{
		red:   u16(r) * 257
		green: u16(g) * 257
		blue:  u16(b) * 257
		alpha: u16(a) * 257
	}
	mut xc := C.XftColor{}
	if C.XftColorAllocValue(c.dpy, visual, cmap, &rc, &xc) != 0 {
		mut px := x
		for p in c.pieces(f, s) {
			C.XftDrawStringUtf8(draw, &xc, p.font, px, y, p.text.str, p.text.len)
			px += c.piece_width(p)
		}
		C.XftColorFree(c.dpy, visual, cmap, &xc)
	}
	C.XftDrawDestroy(draw)
}

// ------------------------------------------------------------ drawing prims

pub fn (c &X11Connection) create_pixmap(w u32, h u32) u64 {
	return C.XCreatePixmap(c.dpy, u64(c.root), w, h, u32(C.XDefaultDepth(c.dpy, c.screen)))
}

pub fn (c &X11Connection) free_pixmap(p u64) {
	C.XFreePixmap(c.dpy, p)
}

pub fn (c &X11Connection) create_gc() voidptr {
	return C.XCreateGC(c.dpy, u64(c.root), 0, unsafe { nil })
}

pub fn (c &X11Connection) set_foreground(gc voidptr, pixel X11Color) {
	C.XSetForeground(c.dpy, gc, u64(pixel))
}

pub fn (c &X11Connection) fill_rect(drawable u64, gc voidptr, x int, y int, w u32, h u32) {
	if w == 0 || h == 0 {
		return
	}
	C.XFillRectangle(c.dpy, drawable, gc, x, y, w, h)
}

pub fn (c &X11Connection) copy_area(src u64, dst u64, gc voidptr, w u32, h u32) {
	C.XCopyArea(c.dpy, src, dst, gc, 0, 0, w, h, 0, 0)
}
