module glo55

// toolbar.v - per-monitor toolbars. Bars flow left-to-right into rows at the
// top of a monitor, wrapping only when the next bar does not fit. Row heights
// are removed from the work area.
import x11

pub const default_toolbar_height = u32(24)

pub struct Toolbar {
pub mut:
	win         x11.Client // the X window the bar is drawn into (0 in unit tests)
	rect        ScreenRect // where it sits (monitor top edge)
	theme_index int        // index into the theme's `toolbars` array
	last_drawn  string     // text signature of the last paint (skip redundant redraws)
	// workspace buttons (see workspace_buttons.v)
	buttons      []ScreenRect // where each workspace's button was last drawn (toolbar coordinates)
	buttons_desc string       // the same, as text (to log only layout changes)
	hover        int = -1 // index of the button under the pointer, -1 = none
	pressed      int = -1 // index of the button the left mouse button went down on, -1 = none
}

// toolbar_bar_rect places
// `width` 0 means the full area width; otherwise the bar is that wide
// (clamped to the area) and `align` is left, center or right.
pub fn toolbar_bar_rect(geometry ScreenRect, height u32, width u32, align string) ScreenRect {
	h := if height > geometry.height { geometry.height } else { height }
	mut w := width
	if w == 0 || w > geometry.width {
		w = geometry.width
	}
	mut x := geometry.x
	if w < geometry.width {
		match align {
			'center' { x += int(geometry.width - w) / 2 }
			'right' { x += int(geometry.width - w) }
			else {}
		}
	}
	return ScreenRect{
		x:      x
		y:      geometry.y
		width:  w
		height: h
	}
}

// layout_toolbars packs bars into rows. Each is aligned inside the first free
// interval wide enough to hold it; only the bar's occupied interval is removed
// from the row's free space. A new row starts when no interval fits. Returns
// rects and the total reserved height (the sum of each row's tallest bar).
pub fn layout_toolbars(geometry ScreenRect, sections []ThemeSection, widths []u32) ([]ScreenRect, u32) {
	mut rects := []ScreenRect{cap: sections.len}
	mut gaps := [ScreenRect{geometry.x, 0, geometry.width, 0}]
	mut row_y := u32(0)
	mut row_height := u32(0)
	mut reserved := u32(0)
	for i, sec in sections {
		mut width := widths[i]
		if width == 0 || width > geometry.width {
			width = geometry.width
		}
		mut gap_index := -1
		for j, gap in gaps {
			if gap.width >= width {
				gap_index = j
				break
			}
		}
		if gap_index < 0 {
			reserved += row_height
			row_y += row_height
			row_height = 0
			gaps = [ScreenRect{geometry.x, 0, geometry.width, 0}]
			gap_index = 0
		}
		gap := gaps[gap_index]
		slot := ScreenRect{gap.x, geometry.y + int(row_y), gap.width, geometry.height - row_y}
		rect := toolbar_bar_rect(slot, sec.height, width, sec.align)
		rects << rect
		left_width := u32(rect.x - gap.x)
		right_x := rect.x + int(rect.width)
		right_width := u32(gap.x + int(gap.width) - right_x)
		gaps.delete(gap_index)
		if right_width > 0 {
			gaps.insert(gap_index, ScreenRect{right_x, 0, right_width, 0})
		}
		if left_width > 0 {
			gaps.insert(gap_index, ScreenRect{gap.x, 0, left_width, 0})
		}
		if rect.height > row_height {
			row_height = rect.height
		}
	}
	reserved += row_height
	return rects, reserved
}

// toolbar_resize_rect changes width around the bar's existing horizontal
// anchor. Its y and height never change, so repaints cannot reflow the rows.
pub fn toolbar_resize_rect(geometry ScreenRect, current ScreenRect, width u32, align string) ScreenRect {
	mut w := width
	if w == 0 || w > geometry.width {
		w = geometry.width
	}
	mut x := current.x
	match align {
		'center' { x += (int(current.width) - int(w)) / 2 }
		'right' { x += int(current.width) - int(w) }
		else {}
	}

	if x < geometry.x {
		x = geometry.x
	}
	return ScreenRect{x, current.y, w, current.height}
}

// work_area_below_toolbar is the monitor area left for tiled windows.
pub fn work_area_below_toolbar(geometry ScreenRect, height u32) ScreenRect {
	h := if height > geometry.height { geometry.height } else { height }
	return ScreenRect{
		x:      geometry.x
		y:      geometry.y + int(h)
		width:  geometry.width
		height: geometry.height - h
	}
}
