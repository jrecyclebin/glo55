module glo55

// theme.v - theme.toml loading and variable replacement.
//
// A theme has `[vars]` (global variables), `[[windows]]` and `[[toolbars]]`
// entries. Each entry holds scalar settings (border_width, window_gap, height,
// monitor), state override tables (`focused`, `hover`, `clicked`,
// `collapsed`: reserved names, which override variables while that state is
// active) and any number of named element tables.
import log
import os
import toml

// The reserved state names. Everything else that is a table is an element.
// `hidden` is an auto-hide toolbar while it is tucked away.
pub const state_names = ['focused', 'hover', 'clicked', 'pressed', 'collapsed', 'hidden']

// theme_root_keys are the top-level keys a theme file may hold.
const theme_root_keys = ['extends', 'vars', 'font_files', 'background', 'background_scale',
	'background_filter', 'windows', 'toolbars']

// section_keys are the scalar settings a [[windows]] / [[toolbars]] entry may
// hold; anything else is reported.
const section_keys = ['border_width', 'window_gap', 'shaped', 'collapsed_height', 'height', 'width',
	'align', 'auto_width', 'monitor', 'position', 'auto_hide', 'hidden_height', 'reveal_ms']

// side reads one side of an [insets] table (missing sides are 0).
fn side(v map[string]toml.Any, k string) u32 {
	if x := v[k] {
		return u32(x.int())
	}
	return 0
}

pub enum Edge {
	left
	top
	right
	bottom
}

// EdgeRef positions one coordinate of an element: "offset pixels from
// <edge> of the area". Offsets are signed: right/bottom edges are the far
// side of the area, so a negative offset moves inwards from them.
//
// `ratio` adds a fraction of the area's extent along that edge's axis
// (width for left/right, height for top/bottom), so `{ edge = "left",
// ratio = 0.5, offset = 1 }` means "1px right of the centre line".
pub struct EdgeRef {
pub:
	edge   Edge
	offset int
	ratio  f64
}

// ThemeArea is an element's positioning: its left/top/right/bottom settings,
// each relative to an edge of the area it is drawn into (a window frame or a
// toolbar). Fixed pixel values only.
pub struct ThemeArea {
pub:
	left   EdgeRef
	top    EdgeRef
	right  EdgeRef
	bottom EdgeRef
}

fn edge_base(r EdgeRef, width int, height int) int {
	extent := if r.edge == .left || r.edge == .right { width } else { height }
	base := match r.edge {
		.left, .top { 0 }
		.right { width }
		.bottom { height }
	}

	return base + int(r.ratio * f64(extent)) + r.offset
}

// resolve turns the area into a rectangle in the coordinates of a drawable of
// size bounds.width x bounds.height (origin 0,0). Inverted or empty
// rectangles come out with zero size.
pub fn (a ThemeArea) resolve(bounds ScreenRect) ScreenRect {
	w := int(bounds.width)
	h := int(bounds.height)
	l := edge_base(a.left, w, h)
	t := edge_base(a.top, w, h)
	r := edge_base(a.right, w, h)
	b := edge_base(a.bottom, w, h)
	return ScreenRect{
		x:      l
		y:      t
		width:  u32(if r > l { r - l } else { 0 })
		height: u32(if b > t { b - t } else { 0 })
	}
}

// Insets is the space a window frame adds around the client on each side.
pub struct Insets {
pub:
	left   u32
	top    u32
	right  u32
	bottom u32
}

pub fn (i Insets) is_zero() bool {
	return i.left == 0 && i.top == 0 && i.right == 0 && i.bottom == 0
}

pub fn Insets.uniform(n u32) Insets {
	return Insets{n, n, n, n}
}

// ThemeSection is one `[[windows]]` or `[[toolbars]]` entry.
pub struct ThemeSection {
pub mut:
	border_width     u32 = 2
	insets           Insets // optional per-side frame insets (replace border_width)
	has_insets       bool
	collapsed_height u32  // frame height of a rolled-up window; 0 = automatic (see rolled_height)
	shaped           bool // windows only: cut the frame to what its elements paint
	window_gap       u32 = 4
	height           u32 = 24 // toolbars only
	width            u32 // toolbars only: 0 = the monitor's width; with auto_width, a minimum
	align            string = 'left' // toolbars only: left | center | right, used when the bar is narrower than the monitor
	auto_width       bool // toolbars only: shrink the bar to its contents (and grow with workspaces)
	monitor          int    = -1  // optional explicit monitor index
	position         string = 'top' // toolbars only: top | bottom edge of the monitor
	// toolbars only: auto-hide. The bar shrinks to a `hidden_height` strip at its
	// edge (drawn with the `hidden` state) and only that strip is kept clear of
	// windows. It slides out over the windows while the pointer is on it, and for
	// `reveal_ms` after a workspace switch (0 = not on a switch).
	auto_hide     bool
	hidden_height u32 = 4
	reveal_ms     int = 1500
	elements      []Element
	states        map[string]map[string]string // state name -> variable overrides
	// toolbars only: the workspace button region and template (see workspace_buttons.v)
	workspace_buttons     WorkspaceButtons
	has_workspace_buttons bool
}

// frame_insets is how much the frame grows the client rect: the `insets`
// table if the theme gave one, else `border_width` on every side.
pub fn (sec &ThemeSection) frame_insets() Insets {
	return if sec.has_insets { sec.insets } else { Insets.uniform(sec.border_width) }
}

// default_rolled_height is the bar height for themes with neither a title
// bar inset nor a collapsed_height.
pub const default_rolled_height = u32(20)

// rolled_height is the frame height of a rolled-up window: `collapsed_height`
// if the theme sets it, else the top inset (the theme's title bar) when it has
// one, else default_rolled_height.
pub fn (sec &ThemeSection) rolled_height() u32 {
	if sec.collapsed_height > 0 {
		return sec.collapsed_height
	}
	if sec.has_insets && sec.insets.top > 0 {
		return sec.insets.top
	}
	return default_rolled_height
}

// ThemeTarget receives a loaded theme. The WindowManager implements it.
pub interface ThemeTarget {
mut:
	theme_vars              map[string]string
	theme_dir               string
	window_themes           []ThemeSection
	toolbar_themes          []ThemeSection
	theme_font_files        []string // font files to register (relative to theme)
	theme_background        string   // optional desktop image, relative to theme
	theme_background_scale  string   // how it fills the desktop: tile (default) | stretch | cover | none
	theme_background_filter string   // how stretch / cover resample: nearest (default, pixel art) | linear (smooth art)
}

// load_theme_into reads theme.toml into tt. A theme may `extends = "path"`
// another theme file (relative to the extending file): the base is loaded
// first, then the extending file's top-level keys replace the base's, except
// that [vars] is merged key by key. That is how one layout serves several
// palettes. Image and font paths stay relative to the extending theme's own
// directory.
pub fn load_theme_into(mut tt ThemeTarget, path string) ! {
	root := load_theme_root(path, 0)!
	tt.theme_dir = os.dir(path)
	parse_theme_root(mut tt, root) or { return error('${path}: ${err}') }
}

const max_extends_depth = 4

// load_theme_root reads a theme file and resolves its `extends` chain.
fn load_theme_root(path string, depth int) !map[string]toml.Any {
	if depth > max_extends_depth {
		return error('${path}: "extends" nests too deeply (a loop?)')
	}
	text := os.read_file(path) or { return error('cannot read ${path}: ${err}') }
	doc := toml.parse_text(text) or { return error('${path}: invalid TOML: ${err}') }
	root := doc.to_any().as_map()
	ext := root['extends'] or { return root }
	base_path := os.join_path(os.dir(path), ext.string())
	base := load_theme_root(base_path, depth + 1)!
	return merge_theme_roots(base, root)
}

// merge_theme_roots lays `over` on `base`: top-level keys of `over` win,
// [vars] is merged key by key, `extends` is dropped.
pub fn merge_theme_roots(base map[string]toml.Any, over map[string]toml.Any) map[string]toml.Any {
	mut out := base.clone()
	for k, v in over {
		if k == 'extends' {
			continue
		}
		if k == 'vars' {
			if bv := base['vars'] {
				mut merged := bv.as_map().clone()
				for vk, vv in v.as_map() {
					merged[vk] = vv
				}
				out['vars'] = toml.Any(merged)
				continue
			}
		}
		out[k] = v
	}
	return out
}

// parse_theme_into is the file-less half of load_theme_into (used by tests).
pub fn parse_theme_into(mut tt ThemeTarget, text string) ! {
	doc := toml.parse_text(text) or { return error('invalid TOML: ${err}') }
	parse_theme_root(mut tt, doc.to_any().as_map())!
}

fn parse_theme_root(mut tt ThemeTarget, root map[string]toml.Any) ! {
	for k, _ in root {
		if k !in theme_root_keys {
			log.warn('theme: unknown top-level key "${k}" ignored')
		}
	}
	tt.theme_vars = map[string]string{}
	if v := root['vars'] {
		for k, val in v.as_map() {
			tt.theme_vars[k] = val.string()
		}
	}
	tt.theme_font_files = []string{}
	if ff := root['font_files'] {
		for f in ff.array() {
			tt.theme_font_files << f.string()
		}
	}
	tt.theme_background = if bg := root['background'] { bg.string() } else { '' }
	tt.theme_background_scale = if bs := root['background_scale'] { bs.string() } else { 'tile' }
	if tt.theme_background_scale !in ['tile', 'stretch', 'cover', 'none'] {
		return error('background_scale must be tile, stretch, cover or none (got "${tt.theme_background_scale}")')
	}
	tt.theme_background_filter = if bf := root['background_filter'] {
		bf.string()
	} else {
		'nearest'
	}
	if tt.theme_background_filter !in ['nearest', 'linear'] {
		return error('background_filter must be nearest or linear (got "${tt.theme_background_filter}")')
	}
	tt.window_themes = []ThemeSection{}
	if ws := root['windows'] {
		for w in ws.array() {
			tt.window_themes << parse_section(w)!
		}
	}
	tt.toolbar_themes = []ThemeSection{}
	if ts := root['toolbars'] {
		for t in ts.array() {
			sec := parse_section(t)!
			// old themes: a `$workspaces` text element becomes a clickable text-button row
			tt.toolbar_themes << if sec.has_workspace_buttons {
				sec
			} else {
				buttons_from_workspaces_text(sec)
			}
		}
	}
	if tt.window_themes.len == 0 {
		return error('theme needs at least one [[windows]] entry (the first is the default)')
	}
	if tt.toolbar_themes.len == 0 {
		tt.toolbar_themes << ThemeSection{}
	}
}

fn parse_section(a toml.Any) !ThemeSection {
	mut sec := ThemeSection{}
	for k, v in a.as_map() {
		match v {
			map[string]toml.Any {
				if k == 'workspace_buttons' {
					sec.workspace_buttons = parse_workspace_buttons(v)!
					sec.has_workspace_buttons = true
				} else if k == 'insets' {
					for sk in v.keys() {
						if sk !in ['left', 'top', 'right', 'bottom'] {
							log.warn('insets: unknown side "${sk}" ignored')
						}
					}
					sec.insets = Insets{
						left:   side(v, 'left')
						top:    side(v, 'top')
						right:  side(v, 'right')
						bottom: side(v, 'bottom')
					}
					sec.has_insets = true
				} else if k in state_names {
					mut vars := map[string]string{}
					for vk, vv in v {
						vars[vk] = vv.string()
					}
					sec.states[k] = vars.move()
				} else {
					sec.elements << Element.from_toml(k, v)!
				}
			}
			else {
				match k {
					'border_width' {
						sec.border_width = u32(v.int())
					}
					'window_gap' {
						sec.window_gap = u32(v.int())
					}
					'shaped' {
						sec.shaped = v.bool()
					}
					'collapsed_height' {
						sec.collapsed_height = u32(v.int())
					}
					'height' {
						sec.height = u32(v.int())
					}
					'width' {
						sec.width = u32(v.int())
					}
					'align' {
						al := v.string()
						if al !in ['left', 'center', 'right'] {
							return error('toolbar align must be left, center or right (got "${al}")')
						}
						sec.align = al
					}
					'auto_width' {
						sec.auto_width = v.bool()
					}
					'monitor' {
						sec.monitor = v.int()
					}
					'position' {
						pos := v.string()
						if pos !in ['top', 'bottom'] {
							return error('toolbar position must be top or bottom (got "${pos}")')
						}
						sec.position = pos
					}
					'auto_hide' {
						sec.auto_hide = v.bool()
					}
					'hidden_height' {
						sec.hidden_height = u32(v.int())
					}
					'reveal_ms' {
						sec.reveal_ms = v.int()
					}
					else {
						log.warn('unknown section setting "${k}" ignored')
					}
				}
			}
		}
	}
	return sec
}

// pick_section chooses the theme entry for a monitor. An entry with an
// explicit `monitor = N` wins; otherwise entry N (by position) is used if it
// exists and has no explicit monitor; otherwise the first entry is the default.
pub fn pick_section(sections []ThemeSection, monitor int) int {
	for i, s in sections {
		if s.monitor == monitor {
			return i
		}
	}
	if monitor >= 0 && monitor < sections.len && sections[monitor].monitor < 0 {
		return monitor
	}
	return 0
}

// pick_toolbar_sections returns the stack for one monitor. Explicit entries
// pinned to that monitor all participate, in file order. With no pinned entry,
// retain the original single positional/default toolbar selection.
pub fn pick_toolbar_sections(sections []ThemeSection, monitor int) []int {
	mut pinned := []int{}
	for i, s in sections {
		if s.monitor == monitor {
			pinned << i
		}
	}
	if pinned.len > 0 {
		return pinned
	}
	return [pick_section(sections, monitor)]
}

// ---------------------------------------------------------------- variables

fn is_ident_char(c u8) bool {
	return (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || (c >= `0` && c <= `9`) || c == `_`
}

// substitute replaces `$name` references with values from vars. Names are
// matched greedily over [A-Za-z0-9_], so `$primary_color` never picks up a
// variable called `$primary`. Unknown names are left untouched (so the
// run-time variables $title/$workspace/$time can be filled in by a later pass).
pub fn substitute(s string, vars map[string]string) string {
	if !s.contains('$') {
		return s
	}
	mut out := []u8{cap: s.len}
	mut i := 0
	for i < s.len {
		if s[i] == `$` {
			mut j := i + 1
			for j < s.len && is_ident_char(s[j]) {
				j++
			}
			name := s[i + 1..j]
			if name.len > 0 {
				if val := vars[name] {
					out << val.bytes()
					i = j
					continue
				}
			}
		}
		out << s[i]
		i++
	}
	return out.bytestr()
}

// resolve_vars builds the effective variable set for a section: global
// `[vars]`, then the overrides of each active state (in the fixed priority
// order focused < hover < clicked < pressed < collapsed < hidden), then run-time variables
// (`$title`, `$workspace`, `$time`) which always win.
pub fn (sec &ThemeSection) resolve_vars(globals map[string]string, active_states []string, runtime map[string]string) map[string]string {
	mut out := globals.clone()
	for st in state_names {
		if st in active_states {
			if ov := sec.states[st] {
				for k, v in ov {
					out[k] = v
				}
			}
		}
	}
	settle_vars(mut out)
	for k, v in runtime {
		out[k] = v
	}
	return out
}

// settle_vars lets variables refer to each other: it resolves a couple of
// levels deep.
fn settle_vars(mut out map[string]string) {
	for _ in 0 .. 3 {
		mut changed := false
		for k, v in out {
			nv := substitute(v, out)
			if nv != v {
				out[k] = nv
				changed = true
			}
		}
		if !changed {
			break
		}
	}
}

// font_pattern builds the fontconfig pattern for a text element.
pub fn font_pattern(name string, size int) string {
	n := if name == '' { 'monospace' } else { name }
	return if size > 0 { '${n}:pixelsize=${size}' } else { n }
}

// theme_get_fonts lists every font pattern the theme's text elements need
// (de-duplicated), in a form `DrawingContext.load_fonts` accepts.
pub fn theme_get_fonts(tt ThemeTarget) []string {
	mut out := []string{}
	mut sections := []ThemeSection{}
	sections << tt.window_themes
	sections << tt.toolbar_themes
	for sec in sections {
		for ele in sec.elements {
			if ele.kind == .text {
				vars := sec.resolve_vars(tt.theme_vars, []string{}, map[string]string{})
				p := font_pattern(substitute(ele.font, vars), ele.size)
				if p !in out {
					out << p
				}
			}
		}
		if sec.has_workspace_buttons {
			vars := sec.resolve_vars(tt.theme_vars, []string{}, map[string]string{})
			for ele in sec.workspace_buttons.elements {
				if ele.kind == .text {
					p := font_pattern(substitute(ele.font, vars), ele.size)
					if p !in out {
						out << p
					}
				}
			}
		}
	}
	return out
}
