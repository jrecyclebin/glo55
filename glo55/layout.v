module glo55

// layout.v - the Layout interface and the master/stack TilingLayout.
//
// Layouts are pure functions from (window specs, work area) to a list of
// updates; they never talk to X. That keeps them unit-testable (see
// layout_test.v) and makes new layouts easy: implement `arrange` and you're done.

pub interface Layout {
	arrange(windows []WindowSpec, work_area ScreenRect) []WindowUpdate
}

// TilingLayout is a DWM-style master/stack layout: one master window on the
// left, everything else stacked in a column on the right.
//
// The rect handed out for each window is the X11 *client* rectangle, i.e.
// inside the border: the frame the WM draws around it is `rect` grown by
// `border_width` on every side, or by `insets` when the theme gives per-side
// frame insets (e.g. a title bar on top).
pub struct TilingLayout {
pub:
	master_ratio f32    // Master pane width ratio (e.g. 0.6 = 60% of screen)
	gap_width    u32    // Configurable gap between windows (and to the screen edge)
	border_width u32    // Window border width
	insets       Insets // per-side frame insets; if all zero, border_width is used
	// frame height of a rolled-up (collapsed) window, the "title bar"
	collapsed_height u32
}

// frame_insets is the frame thickness on each side of a client.
pub fn (l TilingLayout) frame_insets() Insets {
	return if l.insets.is_zero() { Insets.uniform(l.border_width) } else { l.insets }
}

// is_tiled: a normal (unrolled) window that takes part in the master/stack
// split. Collapsed ("rolled up") windows are laid out as bars instead.
fn is_tiled(ws WindowSpec) bool {
	return !ws.info.is_floating() && !ws.info.is_collapsed()
}

// is_bar: a rolled-up window.
fn is_bar(ws WindowSpec) bool {
	return !ws.info.is_floating() && ws.info.is_collapsed()
}

// cell_to_client turns an outer cell (frame included) into the client rect.
fn (l TilingLayout) cell_to_client(x int, y int, w int, h int) ScreenRect {
	ins := l.frame_insets()
	hx := int(ins.left + ins.right)
	hy := int(ins.top + ins.bottom)
	cw := if w - hx < 1 { 1 } else { w - hx }
	ch := if h - hy < 1 { 1 } else { h - hy }
	return ScreenRect{
		x:      x + int(ins.left)
		y:      y + int(ins.top)
		width:  u32(cw)
		height: u32(ch)
	}
}

// bar_height is the frame height of a rolled-up window (at least 1).
fn (l TilingLayout) bar_height() int {
	return if l.collapsed_height < 1 { 1 } else { int(l.collapsed_height) }
}

// outer_cells computes the outer (frame-sized) cells for n tiled windows
// followed by k rolled-up bars. Cells 0..n-1 are the tiled windows (index 0 is
// the master), cells n..n+k-1 are the bars, top to bottom. Recalculated from
// scratch every time.
//
//   n >= 2: master on the left; the stack column on the right holds the
//           stack windows with the bars at its bottom.
//   n == 1: the window fills the width; the bars go under it.
//   n == 0: the bars alone, stacked at the bottom of the work area.
pub fn (l TilingLayout) outer_cells(n int, k int, work_area ScreenRect) []ScreenRect {
	mut cells := []ScreenRect{}
	if n <= 0 && k <= 0 {
		return cells
	}
	g := int(l.gap_width)
	bh := l.bar_height()
	wa := work_area
	full_h := int(wa.height) - 2 * g
	// the column that holds the bars (and, if n < 2, the only window)
	mut col_x := wa.x + g
	mut col_w := max_i(1, int(wa.width) - 2 * g)
	mut stack_n := n // windows in that column
	if n >= 2 {
		avail_w := int(wa.width) - 3 * g // left edge, middle, right edge
		mut master_w := int(f32(avail_w) * l.master_ratio)
		master_w = clamp_i(master_w, 1, max_i(1, avail_w - 1))
		stack_w := max_i(1, avail_w - master_w)
		cells << ScreenRect{wa.x + g, wa.y + g, u32(master_w), u32(max_i(1, full_h))}
		col_x = wa.x + 2 * g + master_w
		col_w = stack_w
		stack_n = n - 1
	}
	// one column of stack_n windows above k bars, gaps between and around
	items := stack_n + k
	mut y := wa.y + g
	avail_h := int(wa.height) - (items + 1) * g - k * bh
	for i in 0 .. stack_n {
		// distribute the remainder so the windows fill the space exactly
		base_h := avail_h / stack_n
		extra := avail_h % stack_n
		mut h := base_h + if i < extra { 1 } else { 0 }
		h = max_i(1, h)
		cells << ScreenRect{col_x, y, u32(col_w), u32(h)}
		y += h + g
	}
	if k > 0 && stack_n == 0 {
		// bars only: sit at the bottom of the work area
		y = wa.y + int(wa.height) - g - k * bh - (k - 1) * g
	}
	for _ in 0 .. k {
		cells << ScreenRect{col_x, y, u32(col_w), u32(bh)}
		y += bh + g
	}
	return cells
}

// arrange: tiled windows get *client* rects (the cell minus the frame
// insets); rolled-up windows get their *frame* rect (the bar), because their
// client is hidden. Floating windows are left alone.
pub fn (l TilingLayout) arrange(windows []WindowSpec, work_area ScreenRect) []WindowUpdate {
	mut tiled := []int{} // indices into `windows`
	mut bars := []int{}
	for i, ws in windows {
		if is_tiled(ws) {
			tiled << i
		} else if is_bar(ws) {
			bars << i
		}
	}
	cells := l.outer_cells(tiled.len, bars.len, work_area)
	mut updates := []WindowUpdate{}
	for n, idx in tiled {
		c := cells[n]
		target := l.cell_to_client(c.x, c.y, int(c.width), int(c.height))
		if target != windows[idx].rect {
			updates << WindowUpdate{
				window_index: idx
				target_rect:  target
			}
		}
	}
	for n, idx in bars {
		target := cells[tiled.len + n]
		if target != windows[idx].rect {
			updates << WindowUpdate{
				window_index: idx
				target_rect:  target
			}
		}
	}
	return updates
}

fn max_i(a int, b int) int {
	return if a > b { a } else { b }
}

fn clamp_i(v int, lo int, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}
