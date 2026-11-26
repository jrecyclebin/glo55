module glo55

// window.v - the WM's internal representation of managed windows.
//
// `Window` is the WM-side record of an X window (the X id is the `Client`
// stored in `id`). `WindowSpec` is one window's placement inside one specific
// workspace; a window that lives on several workspaces has several specs that
// all point at the same `Window`.
import x11

// ScreenRect is an X11 coordinate container in absolute physical pixels.
pub struct ScreenRect {
pub:
	x      int // Absolute X11 physical pixels
	y      int // Absolute X11 physical pixels
	width  u32
	height u32
}

pub fn (r ScreenRect) right() int {
	return r.x + int(r.width)
}

pub fn (r ScreenRect) bottom() int {
	return r.y + int(r.height)
}

pub fn (r ScreenRect) center() (int, int) {
	return r.x + int(r.width) / 2, r.y + int(r.height) / 2
}

pub fn (r ScreenRect) contains(px int, py int) bool {
	return px >= r.x && px < r.right() && py >= r.y && py < r.bottom()
}

// open_point is the point of r nearest its centre that none of `covers` hides
// (the centre itself when nothing is in the way), or none if r is hidden
// everywhere. Besides the centre, candidates lie on a 16x16 grid inside r.
pub fn (r ScreenRect) open_point(covers []ScreenRect) ?(int, int) {
	cx, cy := r.center()
	if !covers.any(it.contains(cx, cy)) {
		return cx, cy
	}
	mut found := false
	mut bx, mut by, mut bd := 0, 0, 0
	for i in 0 .. 16 {
		for j in 0 .. 16 {
			x := r.x + int(r.width) * (2 * i + 1) / 32
			y := r.y + int(r.height) * (2 * j + 1) / 32
			if covers.any(it.contains(x, y)) {
				continue
			}
			d := (x - cx) * (x - cx) + (y - cy) * (y - cy)
			if !found || d < bd {
				found, bx, by, bd = true, x, y, d
			}
		}
	}
	if !found {
		return none
	}
	return bx, by
}

// bit flags for Window.flags
pub const flag_visible = u32(1) << 0
pub const flag_floating = u32(1) << 1
pub const flag_collapsed = u32(1) << 2 // "rolled up": only a title bar stays, at the bottom of the stack
pub const flag_fullscreen = u32(1) << 3 // covers its whole monitor: no frame, no toolbar over it

// Window is the internal representation of a managed window.
@[heap]
pub struct Window {
pub:
	id x11.Client
pub mut:
	title         string
	flags         u32        // bit fields for is_visible, is_floating, is_collapsed, is_fullscreen
	frame         x11.Client // the decorated frame window wrapping `id` (0 until managed)
	collapsed_at  u64        // sequence number of the last collapse (for "restore last")
	ignore_unmaps int        // UnmapNotify events caused by our own reparenting
	was_floating  bool       // floating before it went fullscreen (to restore that)
	saved_rect    ScreenRect // client rect before it went fullscreen (floating windows)
}

pub fn (w &Window) is_visible() bool {
	return w.flags & flag_visible != 0
}

pub fn (w &Window) is_floating() bool {
	return w.flags & flag_floating != 0
}

pub fn (w &Window) is_collapsed() bool {
	return w.flags & flag_collapsed != 0
}

pub fn (w &Window) is_fullscreen() bool {
	return w.flags & flag_fullscreen != 0
}

pub fn (mut w Window) set_visible(on bool) {
	w.set_flag(flag_visible, on)
}

pub fn (mut w Window) set_floating(on bool) {
	w.set_flag(flag_floating, on)
}

pub fn (mut w Window) set_collapsed(on bool) {
	w.set_flag(flag_collapsed, on)
}

pub fn (mut w Window) set_fullscreen(on bool) {
	w.set_flag(flag_fullscreen, on)
}

fn (mut w Window) set_flag(flag u32, on bool) {
	if on {
		w.flags |= flag
	} else {
		w.flags &= ~flag
	}
}

// WindowSpec is an instance of a window within a specific workspace.
pub struct WindowSpec {
pub:
	info &Window
pub mut:
	rect ScreenRect
}

// Direction is used by focus/move navigation.
pub enum Direction {
	up
	down
	left
	right
}

pub fn Direction.parse(s string) ?Direction {
	return match s {
		'up' { Direction.up }
		'down' { Direction.down }
		'left' { Direction.left }
		'right' { Direction.right }
		else { none }
	}
}
