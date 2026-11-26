module glo55

// Unit tests for the master/stack layout math: positions, sizes, gaps and
// border widths. No X server needed.

fn mk_win(id u64) &Window {
	return &Window{
		id: id
	}
}

fn mk_specs(wins []&Window) []WindowSpec {
	mut out := []WindowSpec{}
	for w in wins {
		out << WindowSpec{
			info: w
		}
	}
	return out
}

const test_area = ScreenRect{0, 24, 1000, 776} // 1000x800 monitor with a 24px toolbar

fn apply(mut specs []WindowSpec, ups []WindowUpdate) {
	for u in ups {
		specs[u.window_index].rect = u.target_rect
	}
}

fn test_no_windows_no_updates() {
	l := TilingLayout{
		master_ratio: 0.6
		gap_width:    10
		border_width: 2
	}
	assert l.arrange([]WindowSpec{}, test_area).len == 0
}

fn test_single_window_fills_work_area_minus_gap_and_border() {
	l := TilingLayout{
		master_ratio: 0.6
		gap_width:    10
		border_width: 2
	}
	specs := mk_specs([mk_win(1)])
	ups := l.arrange(specs, test_area)
	assert ups.len == 1
	assert ups[0].window_index == 0
	// outer cell = work area inset by gap (10); client = outer inset by border (2)
	assert ups[0].target_rect == ScreenRect{12, 36, 976, 752}
}

fn test_master_and_stack_widths() {
	l := TilingLayout{
		master_ratio: 0.6
		gap_width:    10
		border_width: 2
	}
	mut specs := mk_specs([mk_win(1), mk_win(2)])
	ups := l.arrange(specs, test_area)
	assert ups.len == 2
	// available width = 1000 - 3*10 = 970 ; master = int(970*0.6)=582 ; stack = 388
	m := ups[0].target_rect
	s := ups[1].target_rect
	assert m == ScreenRect{12, 36, 578, 752} // outer 582x776-20=756 -> minus 2*2
	assert s.x == 10 + 10 + 582 + 2 // after left gap, master, middle gap
	assert s.width == 388 - 4
	assert s.height == 756 - 4
	// no overlap and exactly one gap between the outer cells
	assert (m.x + int(m.width) + 2) + 10 == s.x - 2
	_ = specs
}

fn test_stack_splits_height_evenly_and_fills_exactly() {
	l := TilingLayout{
		master_ratio: 0.5
		gap_width:    8
		border_width: 1
	}
	mut specs := mk_specs([mk_win(1), mk_win(2), mk_win(3), mk_win(4)])
	ups := l.arrange(specs, test_area)
	apply(mut specs, ups)
	// 3 stacked windows: avail_h = 776 - 4*8 = 744 -> 248 each (exact)
	for i in 1 .. 4 {
		assert specs[i].rect.height == 248 - 2
	}
	// column bottom touches the work-area bottom minus the gap
	last := specs[3].rect
	assert last.y + int(last.height) + 1 == test_area.y + int(test_area.height) - 8
	// stack windows are separated by exactly one gap between outer cells
	assert (specs[1].rect.y + int(specs[1].rect.height) + 1) + 8 == specs[2].rect.y - 1
}

fn test_remainder_pixels_are_distributed() {
	l := TilingLayout{
		master_ratio: 0.5
		gap_width:    0
		border_width: 0
	}
	area := ScreenRect{0, 0, 100, 100}
	mut specs := mk_specs([mk_win(1), mk_win(2), mk_win(3), mk_win(4)])
	ups := l.arrange(specs, area)
	apply(mut specs, ups)
	// 100 / 3 = 33 rem 1 -> heights 34,33,33 and the column fills all 100px
	assert specs[1].rect.height == 34
	assert specs[2].rect.height == 33
	assert specs[3].rect.height == 33
	assert specs[3].rect.y + int(specs[3].rect.height) == 100
}

fn test_only_changed_windows_are_updated() {
	l := TilingLayout{
		master_ratio: 0.6
		gap_width:    10
		border_width: 2
	}
	mut specs := mk_specs([mk_win(1), mk_win(2)])
	apply(mut specs, l.arrange(specs, test_area))
	// nothing moved: second arrange must produce no updates
	assert l.arrange(specs, test_area).len == 0
	// a third window changes the stack, but the master (index 0) is unchanged
	specs << WindowSpec{
		info: mk_win(3)
	}
	ups := l.arrange(specs, test_area)
	assert ups.len == 2 // window 2 resized, window 3 placed; master untouched
	for u in ups {
		assert u.window_index != 0
	}
}

fn test_floating_windows_are_ignored() {
	l := TilingLayout{
		master_ratio: 0.6
		gap_width:    10
		border_width: 2
	}
	mut f := mk_win(9)
	f.set_floating(true)
	specs := mk_specs([mk_win(1), f, mk_win(2)])
	ups := l.arrange(specs, test_area)
	assert ups.len == 2
	for u in ups {
		assert u.window_index != 1
	}
	// with the floater ignored, window 1 is master and 2 is the (only) stack window
	assert ups[0].window_index == 0
	assert ups[1].window_index == 2
}

fn collapsed_win(id u64) &Window {
	mut w := mk_win(id)
	w.set_collapsed(true)
	return w
}

// 10px gaps, 2px borders, 20px rolled bars, in test_area (0,24 1000x776)
fn bar_layout() TilingLayout {
	return TilingLayout{
		master_ratio:     0.5
		gap_width:        10
		border_width:     2
		collapsed_height: 20
	}
}

fn test_collapsed_window_becomes_a_bar_and_others_fill_in() {
	l := TilingLayout{
		master_ratio:     0.6
		gap_width:        10
		border_width:     2
		collapsed_height: 20
	}
	mut c := mk_win(2)
	mut specs := mk_specs([mk_win(1), c, mk_win(3)])
	apply(mut specs, l.arrange(specs, test_area))
	assert specs[2].rect.height < 400 // two stack windows share the column
	c.set_collapsed(true)
	apply(mut specs, l.arrange(specs, test_area))
	// the bar is a 20px tall *frame* rect at the bottom of the column
	assert specs[1].rect.height == 20
	assert specs[1].rect.bottom() == test_area.bottom() - 10
	// window 3 fills the rest of the column above it: its frame ends one gap above the bar
	assert specs[2].rect.bottom() + 2 + 10 == specs[1].rect.y
	assert specs[2].rect.y == specs[0].rect.y // top aligned with the master
	// ... and the bar spans the stack column, like the window above it
	assert specs[1].rect.x == specs[2].rect.x - 2
	assert specs[1].rect.width == specs[2].rect.width + 4
}

fn test_bars_sit_at_the_bottom_of_the_stack_in_list_order() {
	l := bar_layout()
	// order: master 1, then stack 2, 3(rolled), 4, 5(rolled)
	mut specs := mk_specs([mk_win(1), mk_win(2), collapsed_win(3),
		mk_win(4), collapsed_win(5)])
	apply(mut specs, l.arrange(specs, test_area))
	// normal stack windows (2, 4) are above both bars
	assert specs[1].rect.y < specs[3].rect.y
	assert specs[3].rect.bottom() + 2 < specs[2].rect.y
	// bar 3 (earlier in the list) is above bar 5; both 20px; one gap between
	assert specs[2].rect.height == 20 && specs[4].rect.height == 20
	assert specs[2].rect.bottom() + 10 == specs[4].rect.y
	assert specs[4].rect.bottom() == test_area.bottom() - 10
	// the master keeps the full height
	assert specs[0].rect.height == u32(776 - 20 - 4)
	// column is exactly filled: stack windows share what bars leave
	total := int(specs[1].rect.height) + 4 + int(specs[3].rect.height) + 4 + 20 + 20 + 4 * 10
	assert total == 776 - 10 // 4 gaps (top + 3 between the 4 items) fill everything but the bottom gap
}

fn test_one_remaining_window_fills_the_width_with_bars_underneath() {
	l := bar_layout()
	mut specs := mk_specs([collapsed_win(1), mk_win(2), collapsed_win(3)])
	apply(mut specs, l.arrange(specs, test_area))
	// window 2 is the only normal one: full width (gap 10, border 2)
	assert specs[1].rect.x == 10 + 2
	assert specs[1].rect.width == u32(1000 - 20 - 4)
	// both bars are full width too, under it, in list order
	assert specs[0].rect.x == 10 && specs[0].rect.width == u32(1000 - 20)
	assert specs[2].rect.x == 10 && specs[2].rect.width == u32(1000 - 20)
	assert specs[1].rect.bottom() + 2 + 10 == specs[0].rect.y
	assert specs[0].rect.bottom() + 10 == specs[2].rect.y
	assert specs[2].rect.bottom() == test_area.bottom() - 10
	// the window takes the rest of the height: 776 - 4 gaps(3 items + 1) - 2 bars - 4 border px
	assert specs[1].rect.height == u32(776 - 4 * 10 - 40 - 4)
}

fn test_all_collapsed_stacks_the_bars_at_the_bottom() {
	l := bar_layout()
	mut specs := mk_specs([collapsed_win(1), collapsed_win(2),
		collapsed_win(3)])
	ups := l.arrange(specs, test_area)
	assert ups.len == 3
	apply(mut specs, ups)
	for sp in specs {
		assert sp.rect.height == 20
		assert sp.rect.x == 10 && sp.rect.width == u32(1000 - 20)
	}
	assert specs[0].rect.bottom() + 10 == specs[1].rect.y
	assert specs[1].rect.bottom() + 10 == specs[2].rect.y
	assert specs[2].rect.bottom() == test_area.bottom() - 10
	// settled: asking again changes nothing
	assert l.arrange(specs, test_area).len == 0
}

fn test_collapsed_master_hands_over_to_the_next_window() {
	l := bar_layout()
	mut first := collapsed_win(1)
	mut specs := mk_specs([first, mk_win(2), mk_win(3)])
	apply(mut specs, l.arrange(specs, test_area))
	// 2 is now master (left, full height), 3 the stack window, the bar under 3
	assert specs[1].rect.x == 10 + 2
	assert specs[1].rect.height == u32(776 - 20 - 4)
	assert specs[2].rect.x > specs[1].rect.right()
	assert specs[0].rect.x == specs[2].rect.x - 2
	assert specs[0].rect.bottom() == test_area.bottom() - 10
	// un-collapse: 1 is master again, exactly as before collapsing
	mut base := mk_specs([mk_win(1), mk_win(2), mk_win(3)])
	apply(mut base, l.arrange(base, test_area))
	first.set_collapsed(false)
	apply(mut specs, l.arrange(specs, test_area))
	for i in 0 .. 3 {
		assert specs[i].rect == base[i].rect
	}
}

fn test_no_collapsed_windows_matches_the_old_layout_exactly() {
	l := bar_layout()
	cells := l.outer_cells(3, 0, test_area)
	assert cells.len == 3
	assert cells[0] == ScreenRect{10, 34, 485, 756}
}

fn test_floating_windows_are_ignored_even_when_collapsed() {
	l := bar_layout()
	mut f := collapsed_win(2)
	f.set_floating(true)
	specs := mk_specs([mk_win(1), f])
	for u in l.arrange(specs, test_area) {
		assert u.window_index != 1
	}
}

fn test_degenerate_sizes_never_underflow() {
	l := TilingLayout{
		master_ratio: 0.9
		gap_width:    50
		border_width: 20
	}
	tiny := ScreenRect{0, 0, 40, 40}
	specs := mk_specs([mk_win(1), mk_win(2), mk_win(3)])
	for u in l.arrange(specs, tiny) {
		assert u.target_rect.width >= 1
		assert u.target_rect.height >= 1
	}
}

fn test_ratio_is_clamped_so_stack_keeps_width() {
	l := TilingLayout{
		master_ratio: 1.5
		gap_width:    0
		border_width: 0
	}
	specs := mk_specs([mk_win(1), mk_win(2)])
	ups := l.arrange(specs, ScreenRect{0, 0, 100, 100})
	assert ups[1].target_rect.width >= 1
	assert ups[0].target_rect.width + ups[1].target_rect.width == 100
}

fn test_asymmetric_insets_make_room_for_a_title_bar() {
	// 10 left/right/bottom, 20 top (a title bar), gap 8, one window
	l := TilingLayout{
		master_ratio: 0.5
		gap_width:    8
		insets:       Insets{10, 20, 10, 10}
	}
	mut specs := mk_specs([mk_win(1)])
	ups := l.arrange(specs, ScreenRect{0, 0, 400, 300})
	// outer cell: 8,8 .. 392,292 -> client sits 10px in (left/right/bottom), 20px down
	assert ups[0].target_rect == ScreenRect{18, 28, 364, 254}
	apply(mut specs, ups)
	// the frame (client grown by the insets) is exactly the outer cell
	assert l.frame_insets() == Insets{10, 20, 10, 10}
}

fn test_zero_insets_fall_back_to_border_width() {
	l := TilingLayout{
		border_width: 3
	}
	assert l.frame_insets() == Insets.uniform(3)
}

fn test_insets_with_two_windows_keep_cells_filling_the_area() {
	l := TilingLayout{
		master_ratio: 0.5
		gap_width:    6
		insets:       Insets{4, 16, 4, 4}
	}
	specs := mk_specs([mk_win(1), mk_win(2), mk_win(3)])
	ups := l.arrange(specs, ScreenRect{0, 0, 600, 400})
	assert ups.len == 3
	// stack windows: frame bottoms line up with the work area minus gap
	last := ups[2].target_rect
	assert int(last.y) + int(last.height) + 4 == 400 - 6
}
