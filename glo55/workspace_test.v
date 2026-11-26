module glo55

// Unit tests for workspace logic: focus navigation, window movement,
// collapse/restore, workspace switching (visibility) and warping.

fn mk_layout() &Layout {
	l := TilingLayout{
		master_ratio:     0.5
		gap_width:        10
		border_width:     2
		collapsed_height: 20
	}
	return &Layout(l)
}

const mon_geo = ScreenRect{0, 0, 1000, 800}

// mk_monitor builds a 1000x800 monitor with a 24px toolbar and 3 workspaces.
fn mk_monitor() Monitor {
	return new_monitor(mon_geo, [ThemeSection{ height: 24 }], [u32(0)], ['a', 'b', 'c'],
		mk_layout())
}

// open adds a window the way the WindowManager does: add, arrange, apply.
fn open(mut m Monitor, id u64) &Window {
	w := &Window{
		id: id
	}
	m.workspaces[m.active].add(w, ScreenRect{})
	relayout(mut m)
	return w
}

fn relayout(mut m Monitor) {
	ups := m.workspaces[m.active].compute_updates(m.work_area)
	m.workspaces[m.active].apply_updates(ups)
}

fn order(m Monitor) []u64 {
	mut out := []u64{}
	for s in m.workspaces[m.active].windows {
		out << s.info.id
	}
	return out
}

fn test_toolbar_height_is_subtracted_from_work_area() {
	m := mk_monitor()
	assert m.work_area == ScreenRect{0, 24, 1000, 776}
	assert m.toolbars[0].rect == ScreenRect{0, 0, 1000, 24}
}

fn test_full_width_toolbars_wrap_and_reserve_row_heights() {
	sections := [ThemeSection{ height: 24 }, ThemeSection{ height: 18 }]
	m := new_monitor(mon_geo, sections, [u32(0), 0], ['a', 'b'], mk_layout())
	assert m.toolbars.len == 2
	assert m.toolbars[0].rect == ScreenRect{0, 0, 1000, 24}
	assert m.toolbars[1].rect == ScreenRect{0, 24, 1000, 18}
	assert m.work_area == ScreenRect{0, 42, 1000, 758}
	offset := new_monitor(ScreenRect{100, 50, 1000, 800}, sections, [u32(0), 0], ['a'], mk_layout())
	assert offset.toolbars[1].rect == ScreenRect{100, 74, 1000, 18}
	assert offset.work_area == ScreenRect{100, 92, 1000, 758}
	oversized := [ThemeSection{ height: 790 }, ThemeSection{ height: 20 }]
	rows, reserved := layout_toolbars(mon_geo, oversized, [u32(0), 0])
	assert rows[1] == ScreenRect{0, 790, 1000, 10}
	assert work_area_below_toolbar(mon_geo, reserved) == ScreenRect{0, 800, 1000, 0}
}

fn test_toolbars_share_a_row_until_the_next_one_does_not_fit() {
	sections := [
		ThemeSection{
			height: 24
			width:  200
			align:  'left'
		},
		ThemeSection{
			height: 18
			width:  200
			align:  'right'
		},
	]
	rects, reserved := layout_toolbars(ScreenRect{0, 0, 800, 600}, sections, [
		u32(200),
		200,
	])
	assert rects == [ScreenRect{0, 0, 200, 24}, ScreenRect{600, 0, 200, 18}]
	assert reserved == 24

	// Right alignment leaves a real gap in the middle. Later bars use that
	// space too; only the fifth 200px bar needs a new row.
	packed_sections := [
		ThemeSection{
			height: 24
			width:  200
			align:  'left'
		},
		ThemeSection{
			height: 24
			width:  200
			align:  'right'
		},
		ThemeSection{
			height: 24
			width:  200
			align:  'left'
		},
		ThemeSection{
			height: 24
			width:  200
			align:  'right'
		},
		ThemeSection{
			height: 20
			width:  200
			align:  'left'
		},
	]
	packed, packed_height := layout_toolbars(ScreenRect{0, 0, 800, 600}, packed_sections, [
		u32(200),
		200,
		200,
		200,
		200,
	])
	assert packed == [ScreenRect{0, 0, 200, 24}, ScreenRect{600, 0, 200, 24},
		ScreenRect{200, 0, 200, 24}, ScreenRect{400, 0, 200, 24},
		ScreenRect{0, 24, 200, 20}]
	assert packed_height == 44

	wrapping := [
		ThemeSection{
			height: 24
			width:  200
			align:  'left'
		},
		ThemeSection{
			height: 18
			width:  200
			align:  'left'
		},
		ThemeSection{
			height: 20
			width:  500
			align:  'left'
		},
	]
	rows, row_height := layout_toolbars(ScreenRect{0, 0, 800, 600}, wrapping, [
		u32(200),
		200,
		500,
	])
	assert rows == [ScreenRect{0, 0, 200, 24}, ScreenRect{200, 0, 200, 18},
		ScreenRect{0, 24, 500, 20}]
	assert row_height == 44
}

fn test_toolbar_resize_keeps_its_row_and_horizontal_anchor() {
	geo := ScreenRect{0, 0, 800, 600}
	left := ScreenRect{200, 42, 200, 18}
	assert toolbar_resize_rect(geo, left, 300, 'left') == ScreenRect{200, 42, 300, 18}
	right := ScreenRect{600, 42, 200, 18}
	assert toolbar_resize_rect(geo, right, 300, 'right') == ScreenRect{500, 42, 300, 18}
	center := ScreenRect{300, 42, 200, 18}
	assert toolbar_resize_rect(geo, center, 300, 'center') == ScreenRect{250, 42, 300, 18}
}

fn test_toolbar_bar_rect_centres_a_narrow_bar() {
	geo := ScreenRect{0, 0, 1000, 800}
	assert toolbar_bar_rect(geo, 28, 0, 'center') == ScreenRect{0, 0, 1000, 28}
	assert toolbar_bar_rect(geo, 28, 400, 'center') == ScreenRect{300, 0, 400, 28}
	assert toolbar_bar_rect(geo, 28, 400, 'left') == ScreenRect{0, 0, 400, 28}
	assert toolbar_bar_rect(geo, 28, 400, 'right') == ScreenRect{600, 0, 400, 28}
	// a width bigger than the monitor is clamped; work area still uses the height
	assert toolbar_bar_rect(geo, 28, 5000, 'center') == ScreenRect{0, 0, 1000, 28}
	assert work_area_below_toolbar(geo, 28) == ScreenRect{0, 28, 1000, 772}
}

fn test_new_windows_go_to_master_and_get_focus() {
	mut m := mk_monitor()
	open(mut m, 1)
	open(mut m, 2)
	open(mut m, 3)
	assert order(m) == [u64(3), 2, 1]
	assert m.workspaces[0].focused == 3
	// the master (index 0) is the left pane
	assert m.workspaces[0].windows[0].rect.x < m.workspaces[0].windows[1].rect.x
}

fn test_floating_windows_keep_requested_rect_and_go_last() {
	mut m := mk_monitor()
	open(mut m, 1)
	mut f := &Window{
		id: 7
	}
	f.set_floating(true)
	m.workspaces[0].add(f, ScreenRect{300, 300, 200, 100})
	relayout(mut m)
	assert order(m) == [u64(1), 7]
	assert m.workspaces[0].windows[1].rect == ScreenRect{300, 300, 200, 100}
}

fn test_focus_up_down_walks_the_stack_column() {
	mut m := mk_monitor()
	for id in [u64(1), 2, 3, 4] {
		open(mut m, id)
	}
	// order is [4 master | 3, 2, 1 stack top->bottom]
	mut ws := &m.workspaces[0]
	ws.focused = 3
	assert ws.focus_direction(.down)? == 2
	ws.focused = 2
	assert ws.focus_direction(.down)? == 1
	ws.focused = 1
	assert ws.focus_direction(.down) == none // bottom of the column: stay
	assert ws.focus_direction(.up)? == 2
	ws.focused = 3
	assert ws.focus_direction(.up) == none // top of the column
}

fn test_focus_left_right_jumps_between_master_and_stack() {
	mut m := mk_monitor()
	for id in [u64(1), 2, 3] {
		open(mut m, id)
	}
	// [3 master | 2, 1]
	mut ws := &m.workspaces[0]
	ws.focused = 3
	assert ws.focus_direction(.left) == none
	// master centre y is 412; window 2 spans upper half, 1 the lower half;
	// the nearest centre wins (2: centre ~217+..., 1: ...) - assert it's a stack window
	r := ws.focus_direction(.right)?
	assert r == 2 || r == 1
	ws.focused = 1
	assert ws.focus_direction(.left)? == 3
	ws.focused = 2
	assert ws.focus_direction(.left)? == 3
	assert ws.focus_direction(.right) == none
}

fn test_focus_right_from_master_picks_vertically_nearest_stack_window() {
	mut m := mk_monitor()
	for id in [u64(1), 2, 3, 4, 5] {
		open(mut m, id)
	}
	// [5 | 4, 3, 2, 1]; master centre is mid-height, so the middle stack
	// windows (3 or 2) are the nearest, not 4 or 1.
	mut ws := &m.workspaces[0]
	ws.focused = 5
	r := ws.focus_direction(.right)?
	assert r == 3 || r == 2
}

fn test_focus_navigation_includes_rolled_up_windows() {
	mut m := mk_monitor()
	mut w1 := open(mut m, 1)
	open(mut m, 2)
	open(mut m, 3)
	// [3 | 2, 1]; roll 1 up: [3 | 2, bar 1]
	w1.set_collapsed(true)
	relayout(mut m)
	mut ws := &m.workspaces[0]
	ws.focused = 2
	assert ws.focus_direction(.down)? == 1 // the bar is right below
	ws.focused = 1
	assert ws.focus_direction(.up)? == 2
	assert ws.focus_direction(.down) == none // nothing under the bottom bar
	assert ws.focus_direction(.left)? == 3 // across to the master
	ws.focused = 3
	assert ws.focus_direction(.right)? == 2 // nearest stack entry wins
}

fn test_move_keeps_bars_and_windows_apart() {
	mut m := mk_monitor()
	mut w1 := open(mut m, 1)
	mut w2 := open(mut m, 2)
	open(mut m, 3)
	open(mut m, 4)
	// [4 | 3, 2, 1]: roll up 1 and 2 -> [4 | 3, bar 2, bar 1]
	w2.set_collapsed(true)
	w1.set_collapsed(true)
	relayout(mut m)
	mut ws := &m.workspaces[0]
	// the normal window 3 can't swap with the bar below it
	ws.focused = 3
	assert !ws.move_direction(.down)
	assert order(m) == [u64(4), 3, 2, 1]
	// a bar swaps with another bar: the bars reorder
	ws.focused = 2
	assert ws.move_direction(.down)
	assert order(m) == [u64(4), 3, 1, 2]
}

fn test_restore_returns_to_the_original_slot() {
	mut m := mk_monitor()
	open(mut m, 1)
	mut w2 := open(mut m, 2)
	open(mut m, 3)
	// [3 | 2, 1]; roll up 2 -> it stays at index 1
	w2.set_collapsed(true)
	relayout(mut m)
	assert order(m) == [u64(3), 2, 1]
	before := m.workspaces[0].windows[1].rect
	assert before.height == 20 // a bar
	// a new window opens at the front; closing others shrinks the list
	open(mut m, 4)
	assert order(m) == [u64(4), 3, 2, 1]
	m.workspaces[0].remove(3)
	relayout(mut m)
	assert order(m) == [u64(4), 2, 1]
	// unroll: still at its slot between 4 and 1, laid out as the first stack window
	w2.set_collapsed(false)
	relayout(mut m)
	assert order(m) == [u64(4), 2, 1]
	r2 := m.workspaces[0].windows[1].rect
	r1 := m.workspaces[0].windows[2].rect
	assert r2.height > 20 && r2.y < r1.y
}

fn test_focus_falls_back_to_normal_windows_before_bars() {
	mut m := mk_monitor()
	mut w1 := open(mut m, 1)
	open(mut m, 2)
	mut w3 := open(mut m, 3)
	// [3 | 2, 1] with 1 rolled up: closing 2 would focus... the only other normal window, 3
	w1.set_collapsed(true)
	relayout(mut m)
	mut ws := &m.workspaces[0]
	ws.focused = 2
	ws.remove(2)
	assert ws.focused == 3
	// only bars left: a bar gets focus (collapsed windows are focusable)
	w3.set_collapsed(true)
	ws.focused = 3
	ws.remove(3)
	assert ws.focused == 1
	ws.remove(1)
	assert ws.focused == 0
}

fn test_move_down_and_up_swap_within_the_stack() {
	mut m := mk_monitor()
	for id in [u64(1), 2, 3, 4] {
		open(mut m, id)
	}
	assert order(m) == [u64(4), 3, 2, 1]
	m.workspaces[0].focused = 3
	assert m.workspaces[0].move_direction(.down)
	relayout(mut m)
	assert order(m) == [u64(4), 2, 3, 1]
	assert m.workspaces[0].move_direction(.down)
	assert order(m) == [u64(4), 2, 1, 3]
	relayout(mut m)
	assert !m.workspaces[0].move_direction(.down) // already at the bottom
	assert m.workspaces[0].move_direction(.up)
	assert order(m) == [u64(4), 2, 3, 1]
}

fn test_move_left_swaps_with_master_and_right_swaps_back() {
	mut m := mk_monitor()
	for id in [u64(1), 2, 3] {
		open(mut m, id)
	}
	assert order(m) == [u64(3), 2, 1]
	m.workspaces[0].focused = 1
	assert m.workspaces[0].move_direction(.left)
	relayout(mut m)
	assert order(m) == [u64(1), 2, 3] // 1 is the master now, 3 took its slot
	// geometry follows the new order
	assert m.workspaces[0].windows[0].rect.x < m.workspaces[0].windows[1].rect.x
	assert m.workspaces[0].move_direction(.right)
	assert order(m)[0] != 1
}

fn test_move_is_noop_without_neighbour() {
	mut m := mk_monitor()
	open(mut m, 1)
	assert !m.workspaces[0].move_direction(.left)
	assert !m.workspaces[0].move_direction(.up)
	assert order(m) == [u64(1)]
}

fn test_remove_moves_focus_to_a_neighbour() {
	mut m := mk_monitor()
	for id in [u64(1), 2, 3] {
		open(mut m, id)
	}
	// [3 | 2, 1], 3 focused; closing it focuses the window in its slot (2)
	m.workspaces[0].remove(3)
	assert m.workspaces[0].focused == 2
	m.workspaces[0].remove(1)
	assert m.workspaces[0].focused == 2
	m.workspaces[0].remove(2)
	assert m.workspaces[0].focused == 0
}

fn test_remove_gives_focus_back_to_the_previously_focused_window() {
	mut m := mk_monitor()
	for id in [u64(1), 2, 3] {
		open(mut m, id)
	}
	mut ws := &m.workspaces[0]
	ws.focus(1)
	dlg := &Window{
		id:    9
		flags: flag_floating
	}
	ws.add(dlg, ScreenRect{})
	assert ws.focused == 9
	// [3 | 2, 1, 9]: the dialog is last, but 1 had focus before it
	ws.remove(9)
	assert ws.focused == 1
	ws.focus(2)
	ws.focus(3)
	ws.remove(3)
	assert ws.focused == 2
	ws.remove(2)
	assert ws.focused == 1
	ws.remove(1)
	assert ws.focused == 0
	assert ws.history.len == 0
}

fn test_focus_history_skips_rolled_up_windows() {
	mut m := mk_monitor()
	open(mut m, 1)
	mut w2 := open(mut m, 2)
	open(mut m, 3)
	mut ws := &m.workspaces[0]
	ws.focus(1)
	ws.focus(2)
	w2.set_collapsed(true)
	ws.focus(3)
	ws.remove(3)
	assert ws.focused == 1
}

fn test_warp_gives_the_source_workspace_its_previous_focus() {
	mut m := mk_monitor()
	for id in [u64(1), 2, 3] {
		open(mut m, id)
	}
	m.workspaces[0].focus(1)
	m.workspaces[0].focus(3)
	m.warp(3, 1) or { panic('warp failed') }
	assert m.workspaces[0].focused == 1
	assert m.workspaces[1].history.map(u64(it)) == [u64(3)]
}

fn test_set_titles_keeps_the_focus_history_of_dropped_workspaces() {
	mut m := mk_monitor()
	open(mut m, 1)
	m.switch_to(2) or { panic('switch failed') }
	open(mut m, 2)
	m.switch_to(0) or { panic('switch failed') }
	m.set_titles(['a', 'b'], mk_layout())
	assert m.workspaces[1].history.map(u64(it)) == [u64(2)]
}

fn test_open_point_avoids_covering_rects() {
	r := ScreenRect{0, 0, 100, 100}
	x, y := r.open_point([]ScreenRect{})?
	assert x == 50 && y == 50
	// a dialog over the middle: the nearest uncovered point, still inside r
	cx, cy := r.open_point([ScreenRect{20, 20, 60, 60}])?
	assert r.contains(cx, cy)
	assert !ScreenRect{20, 20, 60, 60}.contains(cx, cy)
	assert cx > 15 && cx < 85 && cy > 15 && cy < 85
	// covered completely (by two dialogs together): nowhere to go
	if _, _ := r.open_point([ScreenRect{-5, -5, 60, 120}, ScreenRect{50, -5, 60, 120}]) {
		assert false, 'a fully covered rect has no open point'
	}
}

fn test_collapse_and_restore_last() {
	mut m := mk_monitor()
	mut w1 := open(mut m, 1)
	mut w2 := open(mut m, 2)
	w1.set_collapsed(true)
	w1.collapsed_at = 1
	w2.set_collapsed(true)
	w2.collapsed_at = 2
	assert m.workspaces[0].last_collapsed()? == 2
	w2.set_collapsed(false)
	assert m.workspaces[0].last_collapsed()? == 1
	w1.set_collapsed(false)
	assert m.workspaces[0].last_collapsed() == none
}

fn test_workspace_switch_hides_and_shows_the_right_windows() {
	mut m := mk_monitor()
	open(mut m, 1)
	open(mut m, 2)
	// put window 3 on workspace b (index 1)
	w3 := &Window{
		id: 3
	}
	m.workspaces[1].add(w3, ScreenRect{})
	sw := m.switch_to(1)?
	assert m.active == 1
	assert sw.hide.len == 2 && 1 in sw.hide && 2 in sw.hide
	assert sw.show.map(u64(it)) == [u64(3)]
	// switching to the same workspace changes nothing
	same := m.switch_to(1)?
	assert same.hide.len == 0 && same.show.len == 0
	// out of range
	assert m.switch_to(7) == none
	assert m.switch_to(-1) == none
	assert m.active == 1
}

fn test_window_on_multiple_workspaces_stays_visible_across_switch() {
	mut m := mk_monitor()
	both := open(mut m, 1)
	open(mut m, 2)
	m.workspaces[1].add(both, ScreenRect{}) // 1 lives on a and b
	sw := m.switch_to(1)?
	assert sw.hide.map(u64(it)) == [u64(2)]
	assert sw.show.len == 0 // 1 is already on screen
}

fn test_rolled_up_windows_are_shown_on_switch() {
	mut m := mk_monitor()
	mut w1 := open(mut m, 1)
	w1.set_collapsed(true)
	sw := m.switch_to(1)?
	assert sw.hide.map(u64(it)) == [u64(1)] // its bar is hidden with the workspace...
	sw2 := m.switch_to(0)?
	assert sw2.show.map(u64(it)) == [u64(1)] // ... and comes back with it
}

fn test_warp_moves_window_to_other_workspace() {
	mut m := mk_monitor()
	open(mut m, 1)
	open(mut m, 2)
	sw := m.warp(2, 2)?
	assert sw.hide.map(u64(it)) == [u64(2)]
	assert order(m) == [u64(1)]
	assert m.workspaces[2].has(2)
	assert !m.workspaces[0].has(2)
	// warp to current workspace / invalid is rejected
	assert m.warp(1, 0) == none
	assert m.warp(1, 9) == none
	assert m.warp(99, 1) == none
	assert m.window_ids().len == 2
}

fn test_remove_window_everywhere() {
	mut m := mk_monitor()
	both := open(mut m, 1)
	m.workspaces[2].add(both, ScreenRect{})
	assert m.has_window(1)
	m.remove_window(1)
	assert !m.has_window(1)
}

// ---- workspace next/prev, add_at, set_titles (patch 0007)

fn test_next_and_prev_workspace_wrap_around() {
	mut m := mk_monitor() // a b c
	assert m.next_workspace() == 1
	assert m.prev_workspace() == 2 // wraps backwards
	m.active = 2
	assert m.next_workspace() == 0 // wraps forwards
	assert m.prev_workspace() == 1
	mut one := new_monitor(mon_geo, [ThemeSection{ height: 24 }], [u32(0)], ['only'], mk_layout())
	assert one.next_workspace() == 0
	assert one.prev_workspace() == 0
	one.active = 0
}

fn test_add_at_puts_windows_in_their_old_slots() {
	mut m := mk_monitor()
	w1 := &Window{
		id: 1
	}
	w2 := &Window{
		id: 2
	}
	w3 := &Window{
		id: 3
	}
	// a restart adopts them in slot order
	m.workspaces[0].add_at(w1, ScreenRect{}, 0)
	m.workspaces[0].add_at(w2, ScreenRect{}, 1)
	m.workspaces[0].add_at(w3, ScreenRect{}, 2)
	assert order(m) == [u64(1), 2, 3]
	assert m.workspaces[0].focused == 1 // the first one keeps the focus until told otherwise
	// a missing slot (a window died meanwhile) clamps to the end
	w4 := &Window{
		id: 4
	}
	m.workspaces[0].add_at(w4, ScreenRect{}, 9)
	assert order(m) == [u64(1), 2, 3, 4]
}

fn test_set_titles_renames_grows_and_shrinks() {
	mut m := mk_monitor() // a b c
	l := mk_layout()
	m.active = 2
	w := open(mut m, 7) // on c
	m.active = 0
	// rename + grow
	assert m.set_titles(['x', 'y', 'z', 'w'], l)
	assert m.workspaces.len == 4
	assert m.workspaces[0].title == 'x' && m.workspaces[3].title == 'w'
	assert m.workspaces[2].has(w.id) // windows stay where they were
	// shrink: the dropped workspaces' windows join the last one kept
	assert m.set_titles(['p', 'q'], l)
	assert m.workspaces.len == 2
	assert m.workspaces[1].has(w.id)
	m.active = 1
	assert m.workspaces[1].focused == w.id
	// the active workspace is clamped
	mut m2 := mk_monitor()
	m2.active = 2
	m2.set_titles(['one'], l)
	assert m2.active == 0
	// renaming only: same count
	assert !m2.set_titles(['uno'], l)
	assert m2.active_title() == 'uno'
	// an empty list is refused
	assert !m2.set_titles([]string{}, l)
	assert m2.workspaces.len == 1
}

fn test_fullscreen_window_is_floating_like_for_the_layout() {
	mut m := mk_monitor()
	a := open(mut m, 1)
	b := open(mut m, 2)
	assert b.id == 2
	// fullscreen = floating + flag: the other window gets the whole work area
	mut win := m.workspaces[0].windows[0].info
	win.set_fullscreen(true)
	win.set_floating(true)
	assert win.is_fullscreen()
	relayout(mut m)
	rest := m.workspaces[0].windows.filter(it.info.id == a.id)[0]
	assert rest.rect.width > 900
}

fn test_bottom_toolbars_stack_up_from_the_bottom_edge() {
	sections := [
		ThemeSection{
			height: 24
		},
		ThemeSection{
			height:   20
			position: 'bottom'
		},
		ThemeSection{
			height:   10
			position: 'bottom'
		},
	]
	rects, work := place_toolbars(mon_geo, sections, [u32(0), 0, 0])
	assert rects[0] == ScreenRect{0, 0, 1000, 24}
	assert rects[1] == ScreenRect{0, 780, 1000, 20}
	assert rects[2] == ScreenRect{0, 770, 1000, 10}
	assert work == ScreenRect{0, 24, 1000, 746}
	m := new_monitor(ScreenRect{100, 50, 1000, 800}, sections, [u32(0), 0, 0], ['a'], mk_layout())
	assert m.toolbars[1].rect == ScreenRect{100, 830, 1000, 20}
	assert m.work_area == ScreenRect{100, 74, 1000, 746}
}

fn test_auto_hide_toolbars_only_reserve_their_hidden_strip() {
	bottom := ThemeSection{
		height:        26
		position:      'bottom'
		auto_hide:     true
		hidden_height: 7
	}
	top := ThemeSection{
		height:        30
		auto_hide:     true
		hidden_height: 4
	}
	rects, work := place_toolbars(mon_geo, [bottom, top], [u32(0), 0])
	// the rect is the whole bar; only the strip at the edge is kept clear
	assert rects[0] == ScreenRect{0, 774, 1000, 26}
	assert rects[1] == ScreenRect{0, 0, 1000, 30}
	assert work == ScreenRect{0, 4, 1000, 789}
	assert toolbar_window_rect(rects[0], bottom, true) == ScreenRect{0, 793, 1000, 7}
	assert toolbar_window_rect(rects[0], bottom, false) == rects[0]
	assert toolbar_window_rect(rects[1], top, true) == ScreenRect{0, 0, 1000, 4}
	m := new_monitor(mon_geo, [bottom], [u32(0)], ['a'], mk_layout())
	assert m.toolbars[0].hidden
}
