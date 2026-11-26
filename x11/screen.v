module x11

// screen.v - physical screens (monitors), pointer and cursor, visual info.

// ScreenGeometry is one physical monitor's rectangle in root coordinates.
pub struct ScreenGeometry {
pub:
	x      int
	y      int
	width  u32
	height u32
}

// query_monitors uses Xinerama to find the physical monitors (Xephyr with
// `+xinerama`, or a real multi-head desktop). Without Xinerama the whole root
// is a single monitor.
pub fn (c &X11Connection) query_monitors() []ScreenGeometry {
	if C.XineramaIsActive(c.dpy) != 0 {
		mut n := 0
		infos := C.XineramaQueryScreens(c.dpy, &n)
		if !isnil(infos) && n > 0 {
			mut out := []ScreenGeometry{}
			for i in 0 .. n {
				s := unsafe { infos[i] }
				out << ScreenGeometry{
					x:      int(s.x_org)
					y:      int(s.y_org)
					width:  u32(s.width)
					height: u32(s.height)
				}
			}
			C.XFree(infos)
			return out
		}
	}
	return [ScreenGeometry{0, 0, c.width, c.height}]
}

// pointer_position returns the pointer's root coordinates.
pub fn (c &X11Connection) pointer_position() (int, int) {
	mut root := u64(0)
	mut child := u64(0)
	mut rx := 0
	mut ry := 0
	mut wx := 0
	mut wy := 0
	mut mask := u32(0)
	C.XQueryPointer(c.dpy, u64(c.root), &root, &child, &rx, &ry, &wx, &wy, &mask)
	return rx, ry
}

// pointer_window is the top-level window under the pointer (0 = the root) and
// whether a mouse button is held down.
pub fn (c &X11Connection) pointer_window() (Client, bool) {
	mut root := u64(0)
	mut child := u64(0)
	mut rx, mut ry, mut wx, mut wy := 0, 0, 0, 0
	mut mask := u32(0)
	C.XQueryPointer(c.dpy, u64(c.root), &root, &child, &rx, &ry, &wx, &wy, &mask)
	return Client(child), mask & 0x1f00 != 0 // Button1Mask .. Button5Mask
}

pub fn (c &X11Connection) warp_pointer(x int, y int) {
	C.XWarpPointer(c.dpy, 0, u64(c.root), 0, 0, 0, 0, x, y)
}

// init_cursor gives the root window a normal arrow instead of the X cross.
pub fn (c &X11Connection) init_cursor() {
	cur := C.XCreateFontCursor(c.dpy, 68) // XC_left_ptr
	C.XDefineCursor(c.dpy, u64(c.root), cur)
}

pub fn (c &X11Connection) set_root_background(pixel X11Color) {
	C.XSetWindowBackground(c.dpy, u64(c.root), u64(pixel))
	C.XClearWindow(c.dpy, u64(c.root))
}

// set_root_background_pixmap tiles a pixmap over the root window.
pub fn (c &X11Connection) set_root_background_pixmap(pm u64) {
	C.XSetWindowBackgroundPixmap(c.dpy, u64(c.root), pm)
	C.XClearWindow(c.dpy, u64(c.root))
}

// TrueColorInfo describes how to pack RGB into a pixel for the default visual.
pub struct TrueColorInfo {
pub:
	red_shift   int
	green_shift int
	blue_shift  int
	red_bits    int
	green_bits  int
	blue_bits   int
}

fn mask_shift_bits(mask u64) (int, int) {
	mut shift := 0
	mut m := mask
	if m == 0 {
		return 0, 8
	}
	for m & 1 == 0 {
		m >>= 1
		shift++
	}
	mut bits := 0
	for m & 1 == 1 {
		m >>= 1
		bits++
	}
	return shift, bits
}

// true_color_info looks up the default visual's RGB masks (24/32 bit TrueColor).
pub fn (c &X11Connection) true_color_info() ?TrueColorInfo {
	mut vi := C.XVisualInfo{}
	depth := C.XDefaultDepth(c.dpy, c.screen)
	if C.XMatchVisualInfo(c.dpy, c.screen, depth, 4, &vi) == 0 { // TrueColor
		return none
	}
	rs, rb := mask_shift_bits(vi.red_mask)
	gs, gb := mask_shift_bits(vi.green_mask)
	bs, bb := mask_shift_bits(vi.blue_mask)
	return TrueColorInfo{rs, gs, bs, rb, gb, bb}
}
