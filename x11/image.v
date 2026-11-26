module x11

// image.v - read/modify/write access to pixels of a drawable (used to alpha
// blend PNG theme images onto the back buffer).

fn C.calloc(n u64, size u64) voidptr

pub struct PixelRegion {
pub:
	img &C.XImage = unsafe { nil }
pub mut:
	width  int
	height int
	bpp    int
}

// get_region copies a rectangle of a drawable into client memory.
// Only 32 bits-per-pixel visuals (24-bit TrueColor on a normal desktop) are supported.
pub fn (c &X11Connection) get_region(drawable u64, x int, y int, w u32, h u32) ?PixelRegion {
	img := C.XGetImage(c.dpy, drawable, x, y, w, h, u64(0xffffffffffffffff), 2) // ZPixmap
	if isnil(img) {
		return none
	}
	if img.bits_per_pixel != 32 {
		C.XDestroyImage(img)
		return none
	}
	return PixelRegion{
		img:    img
		width:  img.width
		height: img.height
		bpp:    img.bits_per_pixel
	}
}

// new_region makes a blank (all-zero) w x h region without asking the server
// for the current contents: for painting that fully overwrites the area.
pub fn (c &X11Connection) new_region(w u32, h u32) ?PixelRegion {
	if C.XDefaultDepth(c.dpy, c.screen) < 24 {
		return none
	}
	data := unsafe { C.calloc(u64(w) * u64(h), 4) }
	if isnil(data) {
		return none
	}
	img := C.XCreateImage(c.dpy, C.XDefaultVisual(c.dpy, c.screen), u32(C.XDefaultDepth(c.dpy,
		c.screen)), 2, 0, unsafe { &char(data) }, w, h, 32, 0)
	if isnil(img) || img.bits_per_pixel != 32 {
		return none
	}
	return PixelRegion{
		img:    img
		width:  img.width
		height: img.height
		bpp:    32
	}
}

pub fn (r &PixelRegion) get_pixel(x int, y int) u32 {
	unsafe {
		row := &u8(r.img.data) + y * r.img.bytes_per_line
		return *(&u32(row + x * 4))
	}
}

pub fn (mut r PixelRegion) set_pixel(x int, y int, pixel u32) {
	unsafe {
		row := &u8(r.img.data) + y * r.img.bytes_per_line
		*(&u32(row + x * 4)) = pixel
	}
}

// put_region writes the region back at (x, y) and frees it.
pub fn (c &X11Connection) put_region(drawable u64, gc voidptr, r PixelRegion, x int, y int) {
	C.XPutImage(c.dpy, drawable, gc, r.img, 0, 0, x, y, u32(r.width), u32(r.height))
	C.XDestroyImage(r.img)
}

// destroy frees a region that was only read (put_region frees one it writes).
pub fn (r &PixelRegion) destroy() {
	C.XDestroyImage(r.img)
}
