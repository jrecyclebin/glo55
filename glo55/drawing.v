module glo55

// drawing.v - drawing to an X11 graphics context.
//
// One DrawingContext is used globally for the whole window manager. It owns
// the graphics context, the pixel format of the default visual, and the cache
// of loaded Xft fonts. The pure colour/gradient maths (parse_color,
// gradient_t, ...) lives here too so it can be unit tested.
import log
import math
import os
import stbi
import x11

// Rgba is a theme colour.
pub struct Rgba {
pub:
	r u8
	g u8
	b u8
	a u8 = 255
}

// parse_color understands "#rgb", "#rrggbb" and "#rrggbbaa".
pub fn parse_color(s string) ?Rgba {
	t := s.trim_space()
	if t.len == 0 || t[0] != `#` {
		return none
	}
	h := t[1..]
	if h.len != 3 && h.len != 6 && h.len != 8 {
		return none
	}
	for ch in h {
		if !ch.is_hex_digit() {
			return none
		}
	}
	if h.len == 3 {
		r := u8(hex_val(h[0]) * 17)
		g := u8(hex_val(h[1]) * 17)
		b := u8(hex_val(h[2]) * 17)
		return Rgba{r, g, b, 255}
	}
	r := u8(hex_val(h[0]) * 16 + hex_val(h[1]))
	g := u8(hex_val(h[2]) * 16 + hex_val(h[3]))
	b := u8(hex_val(h[4]) * 16 + hex_val(h[5]))
	a := if h.len == 8 { u8(hex_val(h[6]) * 16 + hex_val(h[7])) } else { u8(255) }
	return Rgba{r, g, b, a}
}

fn hex_val(c u8) int {
	return match true {
		c >= `0` && c <= `9` { int(c - `0`) }
		c >= `a` && c <= `f` { int(c - `a`) + 10 }
		else { int(c - `A`) + 10 }
	}
}

// lerp_color blends fore→back; t=0 gives `fore`, t=1 gives `back`.
pub fn lerp_color(fore Rgba, back Rgba, t f32) Rgba {
	tt := if t < 0 {
		f32(0)
	} else if t > 1 {
		f32(1)
	} else {
		t
	}
	mix := fn [tt] (a u8, b u8) u8 {
		return u8(f32(a) + (f32(b) - f32(a)) * tt + 0.5)
	}
	return Rgba{mix(fore.r, back.r), mix(fore.g, back.g), mix(fore.b, back.b), mix(fore.a, back.a)}
}

// normalize_degrees maps any angle into [0, 360).
pub fn normalize_degrees(deg int) int {
	return ((deg % 360) + 360) % 360
}

// gradient_t returns where pixel (px, py) of a w x h rectangle sits along a
// gradient running in direction `deg` (0 = left→right, 90 = top→bottom):
// 0.0 at the start (the `fore` colour) to 1.0 at the end (`back`).
pub fn gradient_t(px int, py int, w int, h int, deg int) f32 {
	d := normalize_degrees(deg)
	// exact answers for the common axis-aligned cases (no float fuzz)
	if d == 0 || d == 180 {
		if w <= 1 {
			return 0
		}
		t := f32(px) / f32(w - 1)
		return if d == 0 { t } else { 1 - t }
	}
	if d == 90 || d == 270 {
		if h <= 1 {
			return 0
		}
		t := f32(py) / f32(h - 1)
		return if d == 90 { t } else { 1 - t }
	}
	rad := f64(d) * math.pi / 180.0
	dx := math.cos(rad)
	dy := math.sin(rad)
	length := math.abs(f64(w) * dx) + math.abs(f64(h) * dy)
	if length == 0 {
		return 0
	}
	t := ((f64(px) + 0.5 - f64(w) / 2.0) * dx + (f64(py) + 0.5 - f64(h) / 2.0) * dy) / length + 0.5
	if t < 0 {
		return 0
	}
	if t > 1 {
		return 1
	}
	return f32(t)
}

// Font is a loaded Xft font.
pub struct Font {
pub:
	spec   string // the fontconfig pattern it was opened with
	handle x11.XftFontHandle
}

// DrawingContext has everything needed to perform drawing operations.
pub struct DrawingContext {
pub:
	conn   &x11.X11Connection
	root   x11.Client
	width  u32
	height u32
	tc     x11.TrueColorInfo
pub mut:
	gc            voidptr
	fonts         map[string]Font        // by fontconfig pattern
	images        map[string]LoadedImage // by resolved path; width 0 = failed to load
	scaled_images map[string]ScaledImage // native pixels of opaque 9-slice images, by source and size
	image_dir     string                 // theme directory: relative image paths are resolved against it
}

// create sets up the global drawing context. width/height are the size of the
// whole X screen (an upper bound for any back buffer).
pub fn DrawingContext.create(conn &x11.X11Connection, root x11.Client, width u32, height u32) !DrawingContext {
	tc := conn.true_color_info() or {
		return error('the default X visual is not TrueColor; Glo55 needs a 24/32 bit TrueColor display')
	}
	return DrawingContext{
		conn:   conn
		root:   root
		width:  width
		height: height
		tc:     tc
		gc:     conn.create_gc()
	}
}

// load_fonts opens each fontconfig pattern with XftFontOpenName and returns
// the ones that loaded (failures are logged by the caller via the returned
// list being shorter). Loaded fonts are also cached in the context.
pub fn (mut d DrawingContext) load_fonts(font_specs []string) []Font {
	mut out := []Font{}
	for spec in font_specs {
		if f := d.fonts[spec] {
			out << f
			continue
		}
		h := d.conn.open_font(spec) or { continue }
		f := Font{spec, h}
		d.fonts[spec] = f
		out << f
	}
	return out
}

// font returns the cached font for a pattern, loading it on demand and
// falling back to plain "monospace" if the pattern can't be opened.
pub fn (mut d DrawingContext) font(spec string) ?Font {
	if f := d.fonts[spec] {
		return f
	}
	loaded := d.load_fonts([spec])
	if loaded.len > 0 {
		return loaded[0]
	}
	if spec != 'monospace' {
		return d.font('monospace')
	}
	return none
}

// to_pixel converts a theme colour into an X11 pixel value for the default visual.
pub fn (d &DrawingContext) to_pixel(c Rgba) x11.X11Color {
	pack := fn (v u8, bits int, shift int) u64 {
		scaled := if bits >= 8 { u64(v) << (bits - 8) } else { u64(v) >> (8 - bits) }
		return scaled << shift
	}
	return x11.X11Color(pack(c.r, d.tc.red_bits, d.tc.red_shift) | pack(c.g, d.tc.green_bits,
		d.tc.green_shift) | pack(c.b, d.tc.blue_bits, d.tc.blue_shift))
}

// new_buffer makes an off-screen pixmap to draw into before copying to a window.
pub fn (d &DrawingContext) new_buffer(w u32, h u32) u64 {
	return d.conn.create_pixmap(w, h)
}

pub fn (d &DrawingContext) free_buffer(b u64) {
	d.conn.free_pixmap(b)
}

// present copies a finished buffer onto a window.
pub fn (d &DrawingContext) present(buffer u64, win x11.Client, w u32, h u32) {
	d.conn.copy_area(buffer, u64(win), d.gc, w, h)
}

// fill_rect fills a rectangle with a solid colour (alpha 0 draws nothing).
pub fn (d &DrawingContext) fill_rect(target u64, r ScreenRect, c Rgba) {
	if c.a == 0 {
		return
	}
	d.conn.set_foreground(d.gc, d.to_pixel(c))
	d.conn.fill_rect(target, d.gc, r.x, r.y, r.width, r.height)
}

// fill_gradient paints a linear gradient from `fore` to `back` in direction
// `deg` (0 = left→right, 90 = top→bottom). Axis-aligned gradients are drawn
// as one stripe per pixel row/column; other angles are drawn per pixel.
pub fn (d &DrawingContext) fill_gradient(target u64, r ScreenRect, fore Rgba, back Rgba, deg int) {
	w := int(r.width)
	h := int(r.height)
	if w == 0 || h == 0 {
		return
	}
	nd := normalize_degrees(deg)
	if nd % 180 == 0 {
		for x in 0 .. w {
			c := lerp_color(fore, back, gradient_t(x, 0, w, h, nd))
			d.fill_rect(target, ScreenRect{r.x + x, r.y, 1, r.height}, c)
		}
	} else if nd % 180 == 90 {
		for y in 0 .. h {
			c := lerp_color(fore, back, gradient_t(0, y, w, h, nd))
			d.fill_rect(target, ScreenRect{r.x, r.y + y, r.width, 1}, c)
		}
	} else {
		for y in 0 .. h {
			for x in 0 .. w {
				c := lerp_color(fore, back, gradient_t(x, y, w, h, nd))
				d.fill_rect(target, ScreenRect{r.x + x, r.y + y, 1, 1}, c)
			}
		}
	}
}

// text_width measures UTF-8 text in the given font.
pub fn (d &DrawingContext) text_width(f Font, s string) int {
	return d.conn.text_width(f.handle, s)
}

// text_width_spaced is text_width plus `spacing` pixels between each rune.
pub fn (d &DrawingContext) text_width_spaced(f Font, s string, spacing int) int {
	if spacing <= 0 || s.len == 0 {
		return d.text_width(f, s)
	}
	n := s.runes().len
	if n <= 1 {
		return d.text_width(f, s)
	}
	return d.text_width(f, s) + spacing * (n - 1)
}

// stamp_text draws s with its baseline at (x, y). A positive spacing is added
// between runes (the letters of a nameplate).
fn (d &DrawingContext) stamp_text(target u64, f Font, s string, x int, y int, c Rgba, spacing int) {
	if spacing <= 0 {
		d.conn.draw_text(target, f.handle, s, x, y, c.r, c.g, c.b, c.a)
		return
	}
	mut px := x
	for r in s.runes() {
		ch := r.str()
		d.conn.draw_text(target, f.handle, ch, px, y, c.r, c.g, c.b, c.a)
		px += d.text_width(f, ch) + spacing
	}
}

// Measure gives the pixel width of a string in some font (an interface so the
// truncation logic can be unit tested without an X server).
pub interface Measure {
	width(s string) int
}

// FontMeasure measures strings in one loaded font.
struct FontMeasure {
	d       &DrawingContext
	f       Font
	spacing int
}

fn (m FontMeasure) width(s string) int {
	return m.d.text_width_spaced(m.f, s, m.spacing)
}

const ellipsis = '…'

// fit_with shortens s with an ellipsis so it is at most max_w wide. It cuts
// between characters (never inside a UTF-8 sequence, and not between a letter
// and the combining mark / joiner that follows it) and binary-searches the cut.
pub fn fit_with(m Measure, s string, max_w int) string {
	if m.width(s) <= max_w {
		return s
	}
	runes := s.runes()
	mut lo := 0 // known to fit (or 0)
	mut hi := runes.len - 1 // candidates are 0 .. runes.len-1 kept characters
	mut best := -1
	for lo <= hi {
		mid := (lo + hi) / 2
		if m.width(runes[..mid].string() + ellipsis) <= max_w {
			best = mid
			lo = mid + 1
		} else {
			hi = mid - 1
		}
	}
	if best < 0 {
		return ''
	}
	for best > 0 && x11.is_neutral(runes[best]) {
		best--
	}
	return runes[..best].string() + ellipsis
}

// fit_text shortens s with an ellipsis until it fits in max_w pixels.
pub fn (d &DrawingContext) fit_text(f Font, s string, max_w int) string {
	return d.fit_text_spaced(f, s, max_w, 0)
}

fn (d &DrawingContext) fit_text_spaced(f Font, s string, max_w int, spacing int) string {
	return fit_with(FontMeasure{
		d:       unsafe { d }
		f:       f
		spacing: spacing
	}, s, max_w)
}

// text_origin lays a string out in r: the (possibly ellipsised) text and the
// x / baseline-y it is drawn at. Text is vertically centred on the font's
// line box, which may be taller than r (it is not clipped to r).
fn (d &DrawingContext) text_origin(r ScreenRect, f Font, text string, align string, spacing int) (string, int, int) {
	s := d.fit_text_spaced(f, text, int(r.width), spacing)
	tw := d.text_width_spaced(f, s, spacing)
	x := match align {
		'center' { r.x + (int(r.width) - tw) / 2 }
		'right' { r.x + int(r.width) - tw }
		else { r.x }
	}

	y := r.y + (int(r.height) - f.handle.height) / 2 + f.handle.ascent
	return s, x, y
}

// draw_text draws UTF-8 text vertically centred in r. align: left|center|right.
// spacing is extra pixels between runes (0 = packed as the font designed).
pub fn (d &DrawingContext) draw_text(target u64, r ScreenRect, f Font, text string, c Rgba, align string, spacing int) {
	if c.a == 0 || text.len == 0 || r.width == 0 {
		return
	}
	s, x, y := d.text_origin(r, f, text, align, spacing)
	d.stamp_text(target, f, s, x, y, c, spacing)
}

// outline_offsets are the eight 1px neighbours a text outline is stamped at.
const outline_offsets = [[-1, -1], [0, -1], [1, -1], [-1, 0],
	[1, 0], [-1, 1], [0, 1], [1, 1]]

// draw_text_outline stamps the text at its eight 1px neighbours: a 1px
// outline, drawn under the text proper.
pub fn (d &DrawingContext) draw_text_outline(target u64, r ScreenRect, f Font, text string, c Rgba, align string, spacing int) {
	if c.a == 0 || text.len == 0 || r.width == 0 {
		return
	}
	s, x, y := d.text_origin(r, f, text, align, spacing)
	for o in outline_offsets {
		d.stamp_text(target, f, s, x + o[0], y + o[1], c, spacing)
	}
}

// text_coverage marks, in `mask`, the pixels a text element paints (glyphs,
// plus the outline when `outlined`), as seen at the same position
// draw_text uses. The text is rendered white-on-black into a scratch pixmap
// and thresholded, so it follows the glyph shapes (not their bounding box):
// a shaped frame can then show text that rises past the frame's art.
pub fn (d &DrawingContext) text_coverage(r ScreenRect, f Font, text string, align string, outlined bool, spacing int, mut mask ShapeMask) {
	if text.len == 0 || r.width == 0 {
		return
	}
	s, x, y := d.text_origin(r, f, text, align, spacing)
	// scratch area: the text's ink box, with a margin for outline and overhang
	margin := 3
	tw := d.text_width_spaced(f, s, spacing)
	sx := x - margin
	sy := y - f.handle.ascent - margin
	sw := tw + 2 * margin
	sh := f.handle.height + 2 * margin
	if sw <= 0 || sh <= 0 {
		return
	}
	pm := d.conn.create_pixmap(u32(sw), u32(sh))
	d.fill_rect(pm, ScreenRect{0, 0, u32(sw), u32(sh)}, Rgba{0, 0, 0, 255})
	white := Rgba{255, 255, 255, 255}
	d.stamp_text(pm, f, s, margin, f.handle.ascent + margin, white, spacing)
	if outlined {
		for o in outline_offsets {
			d.stamp_text(pm, f, s, margin + o[0], f.handle.ascent + margin + o[1], white, spacing)
		}
	}
	region := d.conn.get_region(pm, 0, 0, u32(sw), u32(sh)) or {
		d.conn.free_pixmap(pm)
		return
	}
	for yy in 0 .. sh {
		for xx in 0 .. sw {
			if d.from_pixel(region.get_pixel(xx, yy)).g >= shape_alpha_threshold {
				m_x := sx + xx
				m_y := sy + yy
				if m_x >= 0 && m_y >= 0 && m_x < mask.width && m_y < mask.height {
					mask.cover[m_y * mask.width + m_x] = 1
				}
			}
		}
	}
	region.destroy()
	d.conn.free_pixmap(pm)
}

// ------------------------------------------------------------------- images

// LoadedImage is a decoded PNG (RGBA, 4 bytes per pixel).
pub struct LoadedImage {
pub:
	width  int
	height int
	data   &u8 = unsafe { nil }
	opaque bool // every pixel has alpha 255
	source string
}

// ScaledImage is opaque artwork already mapped into the target geometry and
// converted to native X pixels. Frame repaints can then copy it instead of
// repeating the full-window 9-slice and colour conversion for every pixel.
struct ScaledImage {
	width  int
	height int
	pixels []u32
}

fn (mut d DrawingContext) scaled_opaque(img LoadedImage, rect ScreenRect, mode ScaleMode, slice [4]int) ScaledImage {
	key := '${img.source}|${rect.width}|${rect.height}|${mode}|${slice}'
	if cached := d.scaled_images[key] {
		return cached
	}
	w := int(rect.width)
	h := int(rect.height)
	mut pixels := []u32{len: w * h}
	local := ScreenRect{0, 0, rect.width, rect.height}
	for y in 0 .. h {
		for x in 0 .. w {
			sx, sy := scale_source(x, y, local, img.width, img.height, mode, slice) or { continue }
			off := (sy * img.width + sx) * 4
			src := unsafe {
				Rgba{img.data[off], img.data[off + 1], img.data[off + 2], img.data[off + 3]}
			}
			pixels[y * w + x] = u32(d.to_pixel(src))
		}
	}
	out := ScaledImage{w, h, pixels}
	d.scaled_images[key] = out
	return out
}

// load_image loads (and caches) a PNG via stbi. Relative paths are relative to
// the theme directory. Failures are logged once and cached as "missing".
pub fn (mut d DrawingContext) load_image(path string) ?LoadedImage {
	full := if os.is_abs_path(path) || d.image_dir == '' {
		path
	} else {
		os.join_path(d.image_dir, path)
	}
	if cached := d.images[full] {
		if cached.width == 0 {
			return none
		}
		return cached
	}
	img := stbi.load(full, desired_channels: 4) or {
		log.error('cannot load image ${full}: ${err}')
		d.images[full] = LoadedImage{}
		return none
	}
	mut opaque := true
	for i in 0 .. img.width * img.height {
		if unsafe { img.data[i * 4 + 3] } != 255 {
			opaque = false
			break
		}
	}
	li := LoadedImage{img.width, img.height, img.data, opaque, full}
	d.images[full] = li
	return li
}

// blend composites src over dst (src alpha is respected, result is opaque).
pub fn blend(dst Rgba, src Rgba) Rgba {
	if src.a == 255 {
		return Rgba{src.r, src.g, src.b, 255}
	}
	if src.a == 0 {
		return dst
	}
	a := int(src.a)
	mix := fn [a] (s u8, t u8) u8 {
		return u8((int(s) * a + int(t) * (255 - a) + 127) / 255)
	}
	return Rgba{mix(src.r, dst.r), mix(src.g, dst.g), mix(src.b, dst.b), 255}
}

// tile_source maps a target pixel (px, py) to a pixel of an iw x ih image
// drawn into `rect`: at rect's top-left, once (tiled=false, so pixels outside
// the image give none) or repeated over the whole rect (tiled=true).
pub fn tile_source(px int, py int, rect ScreenRect, iw int, ih int, tiled bool) ?(int, int) {
	if iw <= 0 || ih <= 0 || !rect.contains(px, py) {
		return none
	}
	dx := px - rect.x
	dy := py - rect.y
	if tiled {
		return dx % iw, dy % ih
	}
	if dx >= iw || dy >= ih {
		return none
	}
	return dx, dy
}

// slice_axis maps offset d (0..size-1) along one axis of a 9-slice: `lo` and
// `hi` source pixels at the two ends are copied 1:1, the middle of the
// `src`-pixel image is stretched over the middle of the `size`-pixel target.
fn slice_axis(d int, size int, src int, lo int, hi int) int {
	if size <= lo + hi || src <= lo + hi {
		return d * src / size // too small to keep the edges: plain stretch
	}
	if d < lo {
		return d
	}
	if d >= size - hi {
		return src - (size - d)
	}
	return lo + (d - lo) * (src - lo - hi) / (size - lo - hi)
}

// scale_source is tile_source generalised to every ScaleMode: it maps a
// target pixel (px, py) inside `rect` to a pixel of the iw x ih image.
// `slice` is [left, top, right, bottom] for ScaleMode.slice.
pub fn scale_source(px int, py int, rect ScreenRect, iw int, ih int, mode ScaleMode, slice [4]int) ?(int, int) {
	if iw <= 0 || ih <= 0 || !rect.contains(px, py) {
		return none
	}
	dx := px - rect.x
	dy := py - rect.y
	w := int(rect.width)
	h := int(rect.height)
	return match mode {
		.none {
			tile_source(px, py, rect, iw, ih, false)
		}
		.tile {
			tile_source(px, py, rect, iw, ih, true)
		}
		.stretch {
			dx * iw / w, dy * ih / h
		}
		.slice {
			slice_axis(dx, w, iw, slice[0], slice[2]), slice_axis(dy, h, ih, slice[1], slice[3])
		}
	}
}

// intersect returns the overlap of two rectangles (zero size if disjoint).
pub fn (r ScreenRect) intersect(o ScreenRect) ScreenRect {
	x0 := if r.x > o.x { r.x } else { o.x }
	y0 := if r.y > o.y { r.y } else { o.y }
	x1 := if r.right() < o.right() { r.right() } else { o.right() }
	y1 := if r.bottom() < o.bottom() { r.bottom() } else { o.bottom() }
	if x1 <= x0 || y1 <= y0 {
		return ScreenRect{x0, y0, 0, 0}
	}
	return ScreenRect{x0, y0, u32(x1 - x0), u32(y1 - y0)}
}

// from_pixel is the inverse of to_pixel.
pub fn (d &DrawingContext) from_pixel(p u32) Rgba {
	unpack := fn (p u32, bits int, shift int) u8 {
		v := (u64(p) >> shift) & ((u64(1) << bits) - 1)
		return u8(if bits >= 8 {
			v >> (bits - 8)
		} else {
			v << (8 - bits)
		})
	}
	return Rgba{unpack(p, d.tc.red_bits, d.tc.red_shift), unpack(p, d.tc.green_bits,
		d.tc.green_shift), unpack(p, d.tc.blue_bits, d.tc.blue_shift), 255}
}

// draw_image alpha-blends an image onto `target` inside `rect` (clipped to
// `bounds`, the size of the drawable): once for `image` elements, tiled for
// `pattern` elements.
pub fn (mut d DrawingContext) draw_image(target u64, bounds ScreenRect, rect ScreenRect, img LoadedImage, mode ScaleMode, slice [4]int) {
	mut clip := rect.intersect(bounds)
	if mode == .none {
		clip = clip.intersect(ScreenRect{rect.x, rect.y, u32(img.width), u32(img.height)})
	}
	if clip.width == 0 || clip.height == 0 {
		return
	}
	if img.opaque && img.source != '' && mode == .slice {
		scaled := d.scaled_opaque(img, rect, mode, slice)
		mut region := d.conn.new_region(clip.width, clip.height) or { return }
		for yy in 0 .. int(clip.height) {
			for xx in 0 .. int(clip.width) {
				x := clip.x + xx - rect.x
				y := clip.y + yy - rect.y
				region.set_pixel(xx, yy, scaled.pixels[y * scaled.width + x])
			}
		}
		d.conn.put_region(target, d.gc, region, clip.x, clip.y)
		return
	}
	// A fully opaque image overwrites everything it covers, so there is no
	// need to read the old pixels back (a slow server round trip); a blank
	// region needs a 24+ bit visual, and a non-opaque image needs the old
	// pixels to blend over. Both fall back to reading the pixels back.
	mut region := if img.opaque {
		d.conn.new_region(clip.width, clip.height) or {
			d.conn.get_region(target, clip.x, clip.y, clip.width, clip.height) or {
				x11.PixelRegion{}
			}
		}
	} else {
		d.conn.get_region(target, clip.x, clip.y, clip.width, clip.height) or { x11.PixelRegion{} }
	}
	if isnil(region.img) {
		log.error('cannot read back pixels for image drawing (needs a 32 bits-per-pixel visual)')
		return
	}
	for yy in 0 .. int(clip.height) {
		for xx in 0 .. int(clip.width) {
			sx, sy := scale_source(clip.x + xx, clip.y + yy, rect, img.width, img.height, mode,
				slice) or { continue }
			off := (sy * img.width + sx) * 4
			src := unsafe {
				Rgba{img.data[off], img.data[off + 1], img.data[off + 2], img.data[off + 3]}
			}
			if src.a == 0 {
				continue
			}
			dst := d.from_pixel(region.get_pixel(xx, yy))
			region.set_pixel(xx, yy, u32(d.to_pixel(blend(dst, src))))
		}
	}
	d.conn.put_region(target, d.gc, region, clip.x, clip.y)
}

// cover_rect is the rectangle an iw x ih image takes when scaled, keeping its
// aspect ratio, to cover a w x h screen: centred, so the overflow is cropped
// equally on both sides (a negative x or y).
pub fn cover_rect(w int, h int, iw int, ih int) ScreenRect {
	if iw <= 0 || ih <= 0 {
		return ScreenRect{0, 0, u32(w), u32(h)}
	}
	// compare w/iw with h/ih without fractions
	if w * ih >= h * iw {
		sh := ih * w / iw
		return ScreenRect{0, (h - sh) / 2, u32(w), u32(sh)}
	}
	sw := iw * h / ih
	return ScreenRect{(w - sw) / 2, 0, u32(sw), u32(h)}
}

// scale_bilinear resamples an image to w x h with bilinear filtering (for
// smooth artwork that must be scaled to the screen; nearest-neighbour is the
// default because it keeps pixel art crisp). Colour is interpolated
// premultiplied by alpha so transparent edges do not bleed.
pub fn scale_bilinear(img LoadedImage, w int, h int) []u8 {
	mut out := []u8{len: w * h * 4}
	if w <= 0 || h <= 0 || img.width <= 0 || img.height <= 0 {
		return out
	}
	for y in 0 .. h {
		fy := (f32(y) + 0.5) * f32(img.height) / f32(h) - 0.5
		y0 := int(if fy < 0 { f32(0) } else { fy })
		y1 := if y0 + 1 < img.height { y0 + 1 } else { y0 }
		ty := if fy < 0 { f32(0) } else { fy - f32(y0) }
		for x in 0 .. w {
			fx := (f32(x) + 0.5) * f32(img.width) / f32(w) - 0.5
			x0 := int(if fx < 0 { f32(0) } else { fx })
			x1 := if x0 + 1 < img.width { x0 + 1 } else { x0 }
			tx := if fx < 0 { f32(0) } else { fx - f32(x0) }
			mut acc := [f32(0), 0, 0, 0]!
			for k in 0 .. 4 {
				sxs := if k % 2 == 0 { x0 } else { x1 }
				sys := if k < 2 { y0 } else { y1 }
				wx := if k % 2 == 0 { 1 - tx } else { tx }
				wy := if k < 2 { 1 - ty } else { ty }
				wgt := wx * wy
				off := (sys * img.width + sxs) * 4
				a := f32(unsafe { img.data[off + 3] })
				acc[0] += wgt * f32(unsafe { img.data[off] }) * a
				acc[1] += wgt * f32(unsafe { img.data[off + 1] }) * a
				acc[2] += wgt * f32(unsafe { img.data[off + 2] }) * a
				acc[3] += wgt * a
			}
			o := (y * w + x) * 4
			if acc[3] > 0 {
				out[o] = u8(acc[0] / acc[3] + 0.5)
				out[o + 1] = u8(acc[1] / acc[3] + 0.5)
				out[o + 2] = u8(acc[2] / acc[3] + 0.5)
				out[o + 3] = u8(acc[3] + 0.5)
			}
		}
	}
	return out
}
