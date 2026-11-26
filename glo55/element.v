module glo55

// element.v - theme elements: accessors and rendering.
//
// Elements come in five types: solid, gradient, image, pattern and text. Each
// has a ThemeArea (where it goes inside the frame/toolbar it decorates) and
// type-specific properties. Strings may contain `$variables`, resolved
// (per state) by ThemeSection.resolve_vars before rendering.
import log
import toml

// element_keys are the properties an element table may hold; anything else
// is reported, since a typo'd key would otherwise silently do nothing.
const element_keys = ['type', 'left', 'top', 'right', 'bottom', 'fore', 'back', 'direction', 'path',
	'content', 'font', 'size', 'align', 'action', 'scale', 'slice', 'shadow', 'transform', 'outline',
	'shaped', 'letter_spacing', 'fill', 'when', 'unless']

pub enum ElementType {
	solid
	gradient
	image
	pattern
	text
}

pub fn ElementType.parse(s string) ?ElementType {
	return match s {
		'solid' { ElementType.solid }
		'gradient' { ElementType.gradient }
		'image' { ElementType.image }
		'pattern' { ElementType.pattern }
		'text' { ElementType.text }
		else { none }
	}
}

// ScaleMode says how an image fills its element area.
pub enum ScaleMode {
	none    // drawn once at the top-left, unscaled, clipped
	tile    // repeated at its natural size
	stretch // scaled to fill the area
	slice   // 9-slice: the `slice` edge bands stay unscaled, the middle stretches
}

pub fn ScaleMode.parse(s string) ?ScaleMode {
	return match s {
		'none' { ScaleMode.none }
		'tile' { ScaleMode.tile }
		'stretch' { ScaleMode.stretch }
		'slice' { ScaleMode.slice }
		else { none }
	}
}

// Element is one drawable piece of a theme.
pub struct Element {
pub:
	name           string
	kind           ElementType
	area           ThemeArea
	fore           string // colour (maybe "$var"), solid/gradient/text
	back           string
	direction      int    // gradient angle in degrees (0 = left→right, 90 = top→bottom)
	path           string // image/pattern source (PNG), relative to the theme file
	content        string // text with $template variables
	font           string
	size           int
	align          string    // text alignment: left (default), center, right
	action         string    // optional clickable action: close | collapse (frame elements)
	scale          ScaleMode // how an image fills its area (none/tile/stretch/slice)
	slice          [4]int    // scale = slice: fixed left, top, right, bottom edge sizes (px)
	shadow         string    // text drop-shadow colour (1px down/right), "" = none
	transform      string    // text case: upper | lower | "" (as written)
	outline        string    // text outline colour (1px all round), "" = none
	shaped         bool      // text: its glyphs count toward a shaped frame's shape (so it can rise past the art)
	letter_spacing int       // extra pixels between glyphs (text); 0 = none
	fill           string    // optional 0-100 (or "$var"): shrink the element's width from the left, for meters
	when           []string  // draw only while every one of these states is active
	unless         []string  // skip while any one of these states is active
}

// is_state_name reports whether `s` is a state a theme may test with
// `when`/`unless` or use as an override table: a window state (focused,
// collapsed, ...) or a workspace button state (active, occupied, ...).
pub fn is_state_name(s string) bool {
	return s in state_names || s in button_state_names
}

// parse_states reads a `when`/`unless` value: one state name or a comma
// separated list, parsed (and checked) once at load time, not per repaint.
fn parse_states(prop string, s string, element string) ![]string {
	mut out := []string{}
	for part in s.split(',') {
		t := part.trim_space()
		if t == '' {
			continue
		}
		if !is_state_name(t) {
			return error('element "${element}" ${prop}: unknown state "${t}"')
		}
		out << t
	}
	return out
}

// active_in says whether the element is drawn given the active states
// (`focused`, `collapsed`, ...): every `when` state must be on, no `unless`
// state may be.
pub fn (e &Element) active_in(states []string) bool {
	for name in e.when {
		if name !in states {
			return false
		}
	}
	for name in e.unless {
		if name in states {
			return false
		}
	}
	return true
}

fn edge_from_toml(a toml.Any) !EdgeRef {
	m := a.as_map()
	e := m['edge'] or { return error('position needs an edge') }
	edge := match e.string() {
		'left' { Edge.left }
		'top' { Edge.top }
		'right' { Edge.right }
		'bottom' { Edge.bottom }
		else { return error('unknown edge "${e.string()}"') }
	}

	off := m['offset'] or { toml.Any(0) }
	ratio := m['ratio'] or { toml.Any(0.0) }
	return EdgeRef{edge, off.int(), ratio.f64()}
}

// area_from_toml reads the left/top/right/bottom position keys of a table
// (each an `{ edge, offset, ratio }` inline table; missing ones span the whole area).
pub fn area_from_toml(name string, t map[string]toml.Any) !ThemeArea {
	pos := fn [name, t] (key string, def EdgeRef) !EdgeRef {
		if v := t[key] {
			return edge_from_toml(v) or { return error('element "${name}" ${key}: ${err}') }
		}
		return def
	}
	return ThemeArea{
		left:   pos('left', EdgeRef{.left, 0, 0})!
		top:    pos('top', EdgeRef{.top, 0, 0})!
		right:  pos('right', EdgeRef{.right, 0, 0})!
		bottom: pos('bottom', EdgeRef{.bottom, 0, 0})!
	}
}

// from_toml builds an Element from its TOML table.
pub fn Element.from_toml(name string, t map[string]toml.Any) !Element {
	ty := t['type'] or { return error('element "${name}" has no type') }
	kind := ElementType.parse(ty.string()) or {
		return error('element "${name}": unknown type "${ty.string()}"')
	}
	area := area_from_toml(name, t)!
	str := fn [t] (key string) string {
		if v := t[key] {
			return v.string()
		}
		return ''
	}
	num := fn [t] (key string) int {
		if v := t[key] {
			return v.int()
		}
		return 0
	}
	mut scale := if kind == .pattern { ScaleMode.tile } else { ScaleMode.none }
	if sv := t['scale'] {
		scale = ScaleMode.parse(sv.string()) or {
			return error('element "${name}": unknown scale "${sv.string()}" (none, tile, stretch, slice)')
		}
	}
	mut slice := [4]int{}
	if sv := t['slice'] {
		arr := sv.array()
		if arr.len != 4 {
			return error('element "${name}": slice needs 4 numbers [left, top, right, bottom]')
		}
		for i in 0 .. 4 {
			slice[i] = arr[i].int()
		}
	} else if scale == .slice {
		return error('element "${name}": scale = "slice" needs slice = [left, top, right, bottom]')
	}
	for k in t.keys() {
		if k !in element_keys {
			log.warn('element "${name}": unknown property "${k}" ignored')
		}
	}
	action := str('action')
	if action != '' && action !in ['close', 'collapse', 'fullscreen'] {
		return error('element "${name}": unknown action "${action}" (close, collapse, fullscreen)')
	}
	align := str('align')
	if align != '' && align !in ['left', 'center', 'right'] {
		return error('element "${name}": align must be left, center or right (got "${align}")')
	}
	transform := str('transform')
	if transform != '' && transform !in ['upper', 'lower', 'track'] {
		return error('element "${name}": transform must be upper, lower or track (got "${transform}")')
	}
	when := parse_states('when', str('when'), name)!
	unless := parse_states('unless', str('unless'), name)!
	return Element{
		name:           name
		kind:           kind
		area:           area
		fore:           str('fore')
		back:           str('back')
		direction:      num('direction')
		path:           str('path')
		content:        str('content')
		font:           str('font')
		size:           num('size')
		align:          align
		action:         action
		scale:          scale
		slice:          slice
		shadow:         str('shadow')
		transform:      transform
		outline:        str('outline')
		shaped:         if sv := t['shaped'] { sv.bool() } else { false }
		letter_spacing: num('letter_spacing')
		fill:           str('fill')
		when:           when
		unless:         unless
	}
}

// render draws the element onto `target` (a window or pixmap whose size is
// `bounds`). `vars` is the effective variable set (see resolve_vars) which
// must already include any run-time variables such as $title.
pub fn (e &Element) render(mut ctx DrawingContext, target u64, bounds ScreenRect, vars map[string]string) {
	e.render_rect(mut ctx, target, bounds, e.area.resolve(bounds), vars)
}

// render_in draws the element into a sub-area of `target` (a workspace button
// inside the toolbar, say): the element's own position is resolved against
// `area` (so its edges are relative to the area, not the whole drawable) and
// the result is translated to where the area sits. `drawable` is the size of
// the target, used for clipping.
pub fn (e &Element) render_in(mut ctx DrawingContext, target u64, drawable ScreenRect, area ScreenRect, vars map[string]string) {
	local := e.area.resolve(ScreenRect{0, 0, area.width, area.height})
	e.render_rect(mut ctx, target, drawable, ScreenRect{area.x + local.x, area.y + local.y, local.width, local.height},
		vars)
}

// apply_fill shrinks `rect` from the left to `fill` percent (0-100) of its
// width. `fill` may be a literal or a `$variable`. An empty value leaves the
// rectangle alone.
fn apply_fill(fill string, rect ScreenRect, vars map[string]string) ScreenRect {
	if fill == '' {
		return rect
	}
	mut p := substitute(fill, vars).int()
	if p < 0 {
		p = 0
	} else if p > 100 {
		p = 100
	}
	return ScreenRect{rect.x, rect.y, u32(int(rect.width) * p / 100), rect.height}
}

fn (e &Element) render_rect(mut ctx DrawingContext, target u64, bounds ScreenRect, rect ScreenRect, vars map[string]string) {
	r := apply_fill(e.fill, rect, vars)
	if r.width == 0 || r.height == 0 {
		return
	}
	fore := color_or(substitute(e.fore, vars),
		if e.kind == .text { '#ffffff' } else { '#00000000' }, e.name)
	back := color_or(substitute(e.back, vars), '#00000000', e.name)
	match e.kind {
		.solid {
			ctx.fill_rect(target, r, fore)
		}
		.gradient {
			ctx.fill_gradient(target, r, fore, back, e.direction)
		}
		.text {
			ctx.fill_rect(target, r, back)
			font := ctx.font(font_pattern(substitute(e.font, vars), e.size)) or { return }
			text := apply_transform(substitute(e.content, vars), e.transform)
			if e.shadow != '' {
				sh := color_or(substitute(e.shadow, vars), '#000000', e.name)
				ctx.draw_text(target, ScreenRect{r.x + 1, r.y + 1, r.width, r.height}, font, text,
					sh, e.align, e.letter_spacing)
			}
			if e.outline != '' {
				ol := color_or(substitute(e.outline, vars), '#000000', e.name)
				ctx.draw_text_outline(target, r, font, text, ol, e.align, e.letter_spacing)
			}
			ctx.draw_text(target, r, font, text, fore, e.align, e.letter_spacing)
		}
		.image, .pattern {
			img := ctx.load_image(substitute(e.path, vars)) or { return }
			ctx.draw_image(target, bounds, r, img, e.scale, e.slice)
		}
	}
}

fn color_or(s string, fallback string, element string) Rgba {
	if s.trim_space() == '' {
		return parse_color(fallback) or { Rgba{} } // property not set
	}
	if c := parse_color(s) {
		return c
	}
	log.error('element "${element}": bad colour "${s}"')
	return parse_color(fallback) or { Rgba{} }
}

// mark_shape adds what the element paints to a frame's shape mask. Text does
// not count (it is drawn over other elements) unless it says `shaped = true`:
// then its glyphs (and outline) are cut into the shape, so a title can rise
// above the frame's art. Images count where they are not transparent.
pub fn (e &Element) mark_shape(mut ctx DrawingContext, bounds ScreenRect, vars map[string]string, mut mask ShapeMask) {
	rect := e.area.resolve(bounds)
	if rect.width == 0 || rect.height == 0 {
		return
	}
	match e.kind {
		.solid, .gradient {
			if color_or(substitute(e.fore, vars), '#00000000', e.name).a != 0 {
				mask.mark_rect(rect)
			}
		}
		.image, .pattern {
			if img := ctx.load_image(substitute(e.path, vars)) {
				mask.mark_image(rect, img, e.scale, e.slice)
			}
		}
		.text {
			if e.shaped {
				font := ctx.font(font_pattern(substitute(e.font, vars), e.size)) or { return }
				text := apply_transform(substitute(e.content, vars), e.transform)
				ctx.text_coverage(rect, font, text, e.align, e.outline != '', e.letter_spacing, mut
					mask)
			}
		}
	}
}

// apply_transform changes the case of a text element's string: `transform =
// "upper"` / `"lower"` in the theme (anything else leaves it as written).
pub fn apply_transform(text string, transform string) string {
	return match transform {
		'upper' { text.to_upper() }
		'lower' { text.to_lower() }
		'track' { track_text(text) }
		else { text }
	}
}

// track_text upper-cases s and puts a hair space between letters (a word
// space stays a word space): the small-caps, spaced-out look of a nameplate.
fn track_text(s string) string {
	mut out := []string{}
	mut first := true
	for r in s.to_upper().runes() {
		if r == ` ` {
			out << ' '
			first = true
			continue
		}
		if !first {
			out << ' '
		}
		out << r.str()
		first = false
	}
	return out.join('')
}
