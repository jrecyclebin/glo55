module glo55

// workspace_buttons.v - the toolbar's workspace buttons.
//
// A toolbar theme may define a `[toolbars.workspace_buttons]` table: a region
// of the toolbar plus a template for one button. Glo55 stamps the template out
// once per workspace of the monitor, laying the buttons side by side inside the
// region (so the number and names of workspaces never need a theme edit). Each
// button is drawn from the template's elements with a set of states:
//
//   normal    none of the below
//   occupied  the workspace holds at least one window
//   active    the monitor's current workspace
//   hover     the pointer is over the button (not while pressed)
//   pressed   the left button is held down on it (and the pointer is still over it)
//
// `active` and `occupied` combine with `hover` / `pressed`. Elements pick
// states with `when` / `unless` (comma separated lists: `when = "active,hover"`),
// and a state table (`[toolbars.workspace_buttons.hover]`) overrides variables
// while that state is on, just like `[toolbars.focused]` does for the bar.
import log
import toml

// The button state names, in the order their variable overrides are applied
// (later ones win). `urgent` is reserved (Glo55 does not track it yet).
pub const button_state_names = ['normal', 'occupied', 'urgent', 'active', 'hover', 'pressed']

// WorkspaceButtons is a toolbar's workspace region and button template.
pub struct WorkspaceButtons {
pub mut:
	area          ThemeArea // the region, in toolbar coordinates
	align         string = 'left' // where the row sits in the region: left | center | right
	spacing       int    = 2      // pixels between buttons (negative: neighbours overlap)
	padding       int    = 6      // pixels left and right of the label inside a button
	min_width     int                          // buttons are at least this wide
	max_width     int                          // 0 = no limit
	button_height int                          // 0 = the region's height
	elements      []Element                    // drawn in order, relative to the button
	states        map[string]map[string]string // state name -> variable overrides
}

// parse_workspace_buttons reads the `workspace_buttons` table of a toolbar.
fn parse_workspace_buttons(t map[string]toml.Any) !WorkspaceButtons {
	mut wb := WorkspaceButtons{
		area: area_from_toml('workspace_buttons', t)!
	}
	for k, v in t {
		match v {
			map[string]toml.Any {
				if k in ['left', 'top', 'right', 'bottom'] {
					continue // region position, read above
				}
				if k in button_state_names {
					mut vars := map[string]string{}
					for vk, vv in v {
						vars[vk] = vv.string()
					}
					wb.states[k] = vars.move()
				} else {
					wb.elements << Element.from_toml(k, v)!
				}
			}
			else {
				match k {
					'align' {
						a := v.string()
						if a !in ['left', 'center', 'right'] {
							return error('workspace_buttons: align must be left, center or right (got "${a}")')
						}
						wb.align = a
					}
					'spacing' {
						wb.spacing = v.int()
					}
					'padding' {
						wb.padding = v.int()
					}
					'min_width' {
						wb.min_width = v.int()
					}
					'max_width' {
						wb.max_width = v.int()
					}
					'button_height' {
						wb.button_height = v.int()
					}
					else {
						log.warn('workspace_buttons: unknown setting "${k}" ignored')
					}
				}
			}
		}
	}
	return wb
}

// button_states lists the active states of a button for `when` / `unless`.
// hover and pressed exclude each other (pressed wins).
pub fn button_states(active bool, occupied bool, hover bool, pressed bool) []string {
	mut st := []string{}
	if active {
		st << 'active'
	}
	if occupied {
		st << 'occupied'
	}
	if pressed {
		st << 'pressed'
	} else if hover {
		st << 'hover'
	}
	if st.len == 0 || st.all(it == 'occupied') {
		st << 'normal'
	}
	return st
}

// resolve_vars builds the variables for drawing one button: the toolbar's own
// (already resolved) variables, the overrides of every active button state, and
// the run-time variables for the button (`$workspace`, `$number`).
pub fn (wb &WorkspaceButtons) resolve_vars(base map[string]string, states []string, runtime map[string]string) map[string]string {
	mut out := base.clone()
	for st in button_state_names {
		if st in states {
			if ov := wb.states[st] {
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

// label_element is the first template text element drawn in `states`: it
// supplies the font and text used to measure the button's width.
pub fn (wb &WorkspaceButtons) label_element(states []string) ?Element {
	for e in wb.elements {
		if e.kind == .text && e.active_in(states) {
			return e
		}
	}
	return none
}

// button_width is the width of a button for a label `text_w` pixels wide.
pub fn (wb &WorkspaceButtons) button_width(text_w int) int {
	mut w := text_w + 2 * wb.padding
	if w < wb.min_width {
		w = wb.min_width
	}
	if wb.max_width > 0 && w > wb.max_width {
		w = wb.max_width
	}
	return if w < 1 { 1 } else { w }
}

// layout_buttons places buttons of the given widths in `region` (toolbar
// coordinates), `spacing` apart, aligned left, centre or right. A negative
// spacing overlaps neighbours (for slanted plates that lean into each other),
// by at most half the narrowest button. If they do not all fit they are shrunk
// in proportion. Each is `button_height` tall (0 = the whole region) and
// vertically centred.
pub fn layout_buttons(region ScreenRect, widths []int, spacing int, align string, button_height int) []ScreenRect {
	n := widths.len
	if n == 0 || region.width == 0 || region.height == 0 {
		return []ScreenRect{}
	}
	mut gap := spacing
	if gap < 0 {
		mut narrowest := widths[0]
		for w in widths {
			if w < narrowest {
				narrowest = w
			}
		}
		if gap < -narrowest / 2 {
			gap = -narrowest / 2
		}
	}
	mut ws := widths.clone()
	mut sum := 0
	for w in ws {
		sum += w
	}
	avail := int(region.width)
	if sum + gap * (n - 1) > avail {
		if gap * (n - 1) > avail - n {
			gap = 0 // no room even for the gaps
		}
		room := avail - gap * (n - 1)
		mut used := 0
		for i in 0 .. n {
			mut w := widths[i] * room / sum
			if w < 1 {
				w = 1
			}
			ws[i] = w
			used += w
		}
		sum = used
	}
	total := sum + gap * (n - 1)
	mut x := region.x
	if total < avail {
		match align {
			'right' { x += avail - total }
			'center' { x += (avail - total) / 2 }
			else {}
		}
	}
	h := if button_height > 0 && button_height < int(region.height) {
		button_height
	} else {
		int(region.height)
	}
	y := region.y + (int(region.height) - h) / 2
	mut out := []ScreenRect{cap: n}
	for w in ws {
		out << ScreenRect{x, y, u32(w), u32(h)}
		x += w + gap
	}
	return out
}

// button_at is the index of the button containing (x, y), or -1.
pub fn button_at(rects []ScreenRect, x int, y int) int {
	for i, r in rects {
		if r.contains(x, y) {
			return i
		}
	}
	return -1
}

// buttons_from_workspaces_text upgrades the old way of showing workspaces
// (a text element with `$workspaces`) to the same look, but clickable: that
// element becomes the region and each workspace is a plain text button, the
// active one in [brackets]. It returns the converted section.
fn buttons_from_workspaces_text(sec ThemeSection) ThemeSection {
	mut idx := -1
	for i, e in sec.elements {
		if e.kind == .text && e.content.contains('$workspaces') {
			idx = i
			break
		}
	}
	if idx < 0 {
		return sec
	}
	old := sec.elements[idx]
	mut out := sec
	out.elements = sec.elements.clone()
	out.elements.delete(idx)
	area := old.area
	plain := Element{
		...old
		name:    'label'
		area:    ThemeArea{
			left:   EdgeRef{.left, 0, 0}
			top:    EdgeRef{.top, 0, 0}
			right:  EdgeRef{.right, 0, 0}
			bottom: EdgeRef{.bottom, 0, 0}
		}
		content: '\$workspace'
		unless:  ['active']
		align:   ''
	}
	marked := Element{
		...plain
		name:    'label_active'
		content: '[\$workspace]'
		unless:  []
		when:    ['active']
	}
	out.workspace_buttons = WorkspaceButtons{
		area:     area
		align:    'left'
		spacing:  8
		padding:  0
		elements: [plain, marked]
	}
	out.has_workspace_buttons = true
	return out
}
