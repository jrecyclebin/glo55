module glo55

// workspace.v - per-monitor workspaces and the Monitor container.
//
// Everything here is pure data manipulation (no X calls), so focus navigation,
// window movement and workspace visibility are all unit-tested without a
// display. The WindowManager performs the X side effects.
import x11

pub type MonitorId = int // the index of this monitor in the main array

// Workspace is a per-monitor, ordered list of windows plus a layout. The order
// of `windows` *is* the layout order: index 0 is the master.
pub struct Workspace {
pub:
	layout &Layout
pub mut:
	title   string
	windows []WindowSpec
	focused x11.Client   // focused window of this workspace (0 = none)
	history []x11.Client // windows in the order they had focus, most recent first
}

// index_of finds a window in this workspace by X id.
pub fn (ws &Workspace) index_of(c x11.Client) int {
	for i, spec in ws.windows {
		if spec.info.id == c {
			return i
		}
	}
	return -1
}

pub fn (ws &Workspace) has(c x11.Client) bool {
	return ws.index_of(c) >= 0
}

// add puts a window into the workspace. Tiled windows are forced into the
// layout's starting position (the master pane); floating windows keep the
// requested position and go to the end. New windows become the workspace's
// focused window. The caller then runs `compute_updates`.
//
// (The spec says add(c Client, ...) but a WindowSpec needs a reference to the
// shared Window record, which a bare Client id can't provide: see NOTES.md.)
pub fn (mut ws Workspace) add(win &Window, initial_rect ScreenRect) {
	if ws.has(win.id) {
		return
	}
	spec := WindowSpec{
		info: win
		rect: initial_rect
	}
	if win.is_floating() {
		ws.windows << spec
	} else {
		ws.windows.insert(0, spec)
	}
	ws.focus(win.id)
}

// focus makes `c` the workspace's focused window (0 = none) and moves it to
// the front of the focus history.
pub fn (mut ws Workspace) focus(c x11.Client) {
	ws.focused = c
	if c != 0 {
		ws.history = ws.history.filter(it != c)
		ws.history.insert(0, c)
	}
}

// add_at puts a window at a given slot of the order (clamped to the list) and
// leaves the focus alone: used when a restart gives every window its old slot back.
pub fn (mut ws Workspace) add_at(win &Window, initial_rect ScreenRect, idx int) {
	if ws.has(win.id) {
		return
	}
	spec := WindowSpec{
		info: win
		rect: initial_rect
	}
	ws.windows.insert(clamp_i(idx, 0, ws.windows.len), spec)
	if ws.focused == 0 {
		ws.focus(win.id)
	}
}

// remove takes a window out of the workspace. If it was focused, focus goes
// back to the window that had it before (a closed dialog returns to the window
// that opened it), skipping rolled-up windows; with no such window, to a
// neighbour (fallback_focus).
pub fn (mut ws Workspace) remove(c x11.Client) {
	idx := ws.index_of(c)
	if idx < 0 {
		return
	}
	ws.windows.delete(idx)
	ws.history = ws.history.filter(it != c)
	if ws.focused != c {
		return
	}
	for id in ws.history {
		if !ws.windows[ws.index_of(id)].info.is_collapsed() {
			ws.focus(id)
			return
		}
	}
	ws.focus(ws.fallback_focus(idx))
}

// fallback_focus picks who gets focus when the window at `idx` disappears
// or is rolled up: the one now occupying that slot, else the previous one,
// preferring normal windows over rolled-up ones; if only rolled-up windows are
// left, the one at `idx` (or the nearest) gets it. Returns 0 if the
// workspace is empty.
fn (ws &Workspace) fallback_focus(idx int) x11.Client {
	for i in idx .. ws.windows.len {
		if !ws.windows[i].info.is_collapsed() {
			return ws.windows[i].info.id
		}
	}
	for i := idx - 1; i >= 0; i-- {
		if !ws.windows[i].info.is_collapsed() {
			return ws.windows[i].info.id
		}
	}
	if ws.windows.len == 0 {
		return 0
	}
	return ws.windows[clamp_i(idx, 0, ws.windows.len - 1)].info.id
}

// visible_ids lists the windows shown when this workspace is active:
// all of them, rolled-up windows included (they are bars, not hidden).
pub fn (ws &Workspace) visible_ids() []x11.Client {
	mut out := []x11.Client{}
	for spec in ws.windows {
		out << spec.info.id
	}
	return out
}

// compute_updates asks the layout where windows should go. The WindowManager
// applies them in X, then calls apply_updates so the specs reflect reality.
pub fn (ws &Workspace) compute_updates(work_area ScreenRect) []WindowUpdate {
	return ws.layout.arrange(ws.windows, work_area)
}

pub fn (mut ws Workspace) apply_updates(updates []WindowUpdate) {
	for u in updates {
		ws.windows[u.window_index].rect = u.target_rect
	}
}

// ------------------------------------------------------------- navigation

// focus_direction returns the window that should receive focus when moving
// focus `dir` from the currently focused window, or none if there is nothing
// in that direction.
//
// Navigation is geometric (based on the rects the layout produced), so it
// works for any layout, not just master/stack: the neighbour must overlap the
// current window on the perpendicular axis (up/down need horizontal overlap,
// left/right need vertical overlap); the closest one along the axis wins and
// ties go to the one whose centre is nearest across the axis. In master/stack
// that means: up/down walk the column you're in, left/right jump between
// master and stack.
//
// Rolled-up windows take part: their bars are neighbours like any window.
pub fn (ws &Workspace) focus_direction(dir Direction) ?x11.Client {
	i := ws.neighbour_index(dir, false)?
	return ws.windows[i].info.id
}

// neighbour_index finds the geometric neighbour in `dir`. With `same_kind`
// only windows that are rolled up like the current one (or both not) count.
fn (ws &Workspace) neighbour_index(dir Direction, same_kind bool) ?int {
	cur_idx := ws.index_of(ws.focused)
	if cur_idx < 0 {
		return none
	}
	cur := ws.windows[cur_idx].rect
	cur_collapsed := ws.windows[cur_idx].info.is_collapsed()
	ccx, ccy := cur.center()
	mut best := -1
	mut best_axis := 0
	mut best_cross := 0
	for i, spec in ws.windows {
		if i == cur_idx || (same_kind && spec.info.is_collapsed() != cur_collapsed) {
			continue
		}
		r := spec.rect
		cx, cy := r.center()
		// axis: the distance from us to it along the direction of travel
		axis := match dir {
			.left { ccx - cx }
			.right { cx - ccx }
			.up { ccy - cy }
			.down { cy - ccy }
		}

		// the neighbour must overlap us across the axis; the closest along it
		// wins, ties go to the nearest centre across the axis
		cross := if dir in [.left, .right] { abs_i(ccy - cy) } else { abs_i(ccx - cx) }
		overlaps := if dir in [.left, .right] {
			r.y < cur.bottom() && cur.y < r.bottom()
		} else {
			r.x < cur.right() && cur.x < r.right()
		}
		if axis <= 0 || !overlaps {
			continue
		}
		if best < 0 || axis < best_axis || (axis == best_axis && cross < best_cross) {
			best = i
			best_axis = axis
			best_cross = cross
		}
	}
	if best < 0 {
		return none
	}
	return best
}

// move_direction moves the focused window by swapping its slot in the layout
// order with its neighbour in `dir` (moving "left" from the stack swaps it
// with the master; "down" swaps with the next window in the column, ...).
// A normal window only swaps with normal windows and a rolled-up one only
// with other rolled-up ones (that reorders the bars).
// Returns true if anything changed. Floating windows can't be moved this way.
// The caller then recomputes the layout.
pub fn (mut ws Workspace) move_direction(dir Direction) bool {
	cur_idx := ws.index_of(ws.focused)
	if cur_idx < 0 || ws.windows[cur_idx].info.is_floating() {
		return false
	}
	other := ws.neighbour_index(dir, true) or { return false }
	if ws.windows[other].info.is_floating() {
		return false
	}
	tmp := ws.windows[cur_idx]
	ws.windows[cur_idx] = ws.windows[other]
	ws.windows[other] = tmp
	return true
}

// last_collapsed returns the most recently collapsed window of this workspace.
pub fn (ws &Workspace) last_collapsed() ?x11.Client {
	mut best := x11.Client(0)
	mut best_seq := u64(0)
	for spec in ws.windows {
		if spec.info.is_collapsed() && spec.info.collapsed_at >= best_seq {
			best = spec.info.id
			best_seq = spec.info.collapsed_at
		}
	}
	if best == 0 {
		return none
	}
	return best
}

fn abs_i(a int) int {
	return if a < 0 { -a } else { a }
}

// ----------------------------------------------------------------- Monitor

// WorkspaceSwitch lists what must be hidden/shown when switching workspaces.
pub struct WorkspaceSwitch {
pub:
	hide []x11.Client
	show []x11.Client
}

// Monitor is a physical screen: geometry, the area left for tiling once its
// toolbars are docked, and its own list of workspaces.
pub struct Monitor {
pub:
	geometry ScreenRect
pub mut:
	work_area  ScreenRect
	workspaces []Workspace
	active     int // index of the shown workspace
	toolbars   []Toolbar
}

// new_monitor builds a monitor with one workspace per title. Toolbars flow
// into top rows in theme order and their row heights are removed from work_area.
pub fn new_monitor(geometry ScreenRect, sections []ThemeSection, widths []u32, titles []string, layout &Layout) Monitor {
	mut wss := []Workspace{}
	for t in titles {
		wss << Workspace{
			title:  t
			layout: unsafe { layout } // points into WindowManager.layouts, which outlives monitors
		}
	}
	rects, reserved := layout_toolbars(geometry, sections, widths)
	mut toolbars := []Toolbar{cap: sections.len}
	for i, rect in rects {
		toolbars << Toolbar{
			rect:        rect
			theme_index: i
		}
	}
	return Monitor{
		geometry:   geometry
		work_area:  work_area_below_toolbar(geometry, reserved)
		workspaces: wss
		toolbars:   toolbars
	}
}

// next_workspace is the index after the active one, wrapping around the list.
pub fn (m &Monitor) next_workspace() int {
	return (m.active + 1) % m.workspaces.len
}

// prev_workspace is the index before the active one, wrapping around the list.
pub fn (m &Monitor) prev_workspace() int {
	return (m.active + m.workspaces.len - 1) % m.workspaces.len
}

// set_titles gives the monitor a new workspace list (a config reload). Workspaces
// are matched by position: they are renamed, new ones are appended, and when the
// list shrinks the windows of the dropped workspaces move to the last kept one.
// The active workspace stays active (clamped to the new list). Returns true if
// the number of workspaces changed.
pub fn (mut m Monitor) set_titles(titles []string, layout &Layout) bool {
	if titles.len == 0 {
		return false
	}
	before := m.workspaces.len
	for i, t in titles {
		if i < m.workspaces.len {
			m.workspaces[i].title = t
		} else {
			m.workspaces << Workspace{
				title:  t
				layout: unsafe { layout }
			}
		}
	}
	if m.workspaces.len > titles.len {
		last := titles.len - 1
		for i in titles.len .. m.workspaces.len {
			for spec in m.workspaces[i].windows {
				if !m.workspaces[last].has(spec.info.id) {
					m.workspaces[last].windows << spec
				}
			}
			if m.workspaces[last].focused == 0 {
				m.workspaces[last].focused = m.workspaces[i].focused
			}
			for id in m.workspaces[i].history {
				if id !in m.workspaces[last].history {
					m.workspaces[last].history << id
				}
			}
		}
		m.workspaces = m.workspaces[..titles.len].clone()
		if m.active > last {
			m.active = last
		}
	}
	return m.workspaces.len != before
}

pub fn (m &Monitor) active_title() string {
	return m.workspaces[m.active].title
}

// workspace_list renders all workspace names with the active one in brackets,
// e.g. "main [web] code" (exposed to themes as the $workspaces variable).
pub fn (m &Monitor) workspace_list() string {
	mut parts := []string{}
	for i, ws in m.workspaces {
		parts << if i == m.active { '[${ws.title}]' } else { ws.title }
	}
	return parts.join('  ')
}

// window_ids is the complete (de-duplicated) window list across workspaces.
pub fn (m &Monitor) window_ids() []x11.Client {
	mut out := []x11.Client{}
	for ws in m.workspaces {
		for spec in ws.windows {
			if spec.info.id !in out {
				out << spec.info.id
			}
		}
	}
	return out
}

pub fn (m &Monitor) has_window(c x11.Client) bool {
	for ws in m.workspaces {
		if ws.has(c) {
			return true
		}
	}
	return false
}

// switch_to makes workspace `idx` (0-based) the shown one and reports which
// windows must be hidden and shown. Windows that exist on both the old and
// the new workspace stay put. Returns none for an invalid index.
pub fn (mut m Monitor) switch_to(idx int) ?WorkspaceSwitch {
	if idx < 0 || idx >= m.workspaces.len {
		return none
	}
	old := m.active
	if idx == old {
		return WorkspaceSwitch{}
	}
	old_ids := m.workspaces[old].visible_ids()
	new_ids := m.workspaces[idx].visible_ids()
	mut hide := []x11.Client{}
	mut show := []x11.Client{}
	for id in old_ids {
		if id !in new_ids {
			hide << id
		}
	}
	for id in new_ids {
		if id !in old_ids {
			show << id
		}
	}
	m.active = idx
	return WorkspaceSwitch{hide, show}
}

// warp moves a window from the active workspace to workspace `target`.
// Returns the switch description (the window hidden if `target` isn't the
// active workspace, which it never is for a real warp), or none if invalid.
pub fn (mut m Monitor) warp(c x11.Client, target int) ?WorkspaceSwitch {
	if target < 0 || target >= m.workspaces.len || target == m.active {
		return none
	}
	idx := m.workspaces[m.active].index_of(c)
	if idx < 0 {
		return none
	}
	win := m.workspaces[m.active].windows[idx].info
	rect := m.workspaces[m.active].windows[idx].rect
	m.workspaces[m.active].remove(c)
	m.workspaces[target].add(win, rect)
	// still visible if it is also attached to the active workspace (it isn't:
	// remove() above took it out), so it must be hidden.
	return WorkspaceSwitch{
		hide: [c]
	}
}

// remove_window forgets a window everywhere on this monitor.
pub fn (mut m Monitor) remove_window(c x11.Client) {
	for mut ws in m.workspaces {
		ws.remove(c)
	}
}
