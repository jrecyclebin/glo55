module x11

// xlib.v - raw Xlib / Xft / Xinerama bindings (the "custom X11 bindings").
//
// Only the functions and struct fields Glo55 actually uses are declared.
// V's C interop uses the real C headers for layout, so the fields listed on a
// `C.` struct only need to exist with the right *names* (types are used for V's
// own type checking). Everything outside this module should go through the
// wrappers in client.v / events.v / screen.v where practical.

#flag -lX11 -lXft -lXinerama -lXext -lXi -lfontconfig
#flag linux -I/usr/include/freetype2 -I/usr/include/libpng16
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xatom.h>
#include <X11/extensions/shape.h>
#include <X11/cursorfont.h>
#include <X11/Xft/Xft.h>
#include <X11/extensions/Xinerama.h>
#include <X11/extensions/XInput2.h>
#include <poll.h>
#include <locale.h>
#include <fontconfig/fontconfig.h>

// ---------------------------------------------------------------- basic types

pub type Client = u64 // client is the term for an X11 window
pub type Atom = u64
pub type X11Color = u64

// The predefined atoms Xlib documents as XA_STRING / XA_WM_NAME (XInternAtom
// would return these same ids; the numbers are fixed by the protocol).
pub const xa_string = Atom(31)
pub const xa_wm_name = Atom(39)

// ------------------------------------------------------------ opaque C types

@[typedef]
pub struct C.Display {}

@[typedef]
pub struct C.Visual {}

@[typedef]
pub struct C.XftDraw {}

@[typedef]
pub struct C.XRenderColor {
pub mut:
	red   u16
	green u16
	blue  u16
	alpha u16
}

@[typedef]
pub struct C.XftColor {
pub mut:
	pixel u64
	color C.XRenderColor
}

@[typedef]
pub struct C.XftFont {
pub:
	pattern           voidptr // FcPattern* the font was opened from
	ascent            int
	descent           int
	height            int
	max_advance_width int
}

@[typedef]
pub struct C.XTextProperty {
pub mut:
	value    &u8 = unsafe { nil }
	encoding u64
	format   int
	nitems   u64
}

@[typedef]
pub struct C.XVisualInfo {
pub mut:
	visual   &C.Visual = unsafe { nil }
	visualid u64
	screen   int
	depth    int
	// `class` is left out: some V versions mangle that field name to `__v_class`
	red_mask   u64
	green_mask u64
	blue_mask  u64
}

@[typedef]
pub struct C.XineramaScreenInfo {
pub:
	screen_number int
	x_org         i16
	y_org         i16
	width         i16
	height        i16
}

@[typedef]
pub struct C.XWindowAttributes {
pub mut:
	x                 int
	y                 int
	width             int
	height            int
	border_width      int
	map_state         int
	override_redirect int
}

@[typedef]
pub struct C.XSetWindowAttributes {
pub mut:
	background_pixel  u64
	border_pixel      u64
	event_mask        i64
	override_redirect int
	cursor            u64
}

@[typedef]
pub struct C.XWindowChanges {
pub mut:
	x            int
	y            int
	width        int
	height       int
	border_width int
	sibling      u64
	stack_mode   int
}

@[typedef]
pub struct C.XErrorEvent {
pub:
	error_code   u8
	request_code u8
	minor_code   u8
	resourceid   u64
}

// ------------------------------------------------------------------- events

@[typedef]
pub struct C.XAnyEvent {
pub:
	type   int
	window u64
}

@[typedef]
pub struct C.XKeyEvent {
pub:
	type      int
	window    u64
	subwindow u64
	x         int
	y         int
	x_root    int
	y_root    int
	state     u32
	keycode   u32
}

@[typedef]
pub struct C.XButtonEvent {
pub:
	type      int
	window    u64
	subwindow u64
	x         int
	y         int
	x_root    int
	y_root    int
	state     u32
	button    u32
}

@[typedef]
pub struct C.XMotionEvent {
pub:
	type   int
	window u64
	x      int
	y      int
	x_root int
	y_root int
	state  u32
}

@[typedef]
pub struct C.XCrossingEvent {
pub:
	type   int
	window u64
	x      int
	y      int
	x_root int
	y_root int
	mode   int
	detail int
}

// XGenericEvent carries extension events (XInput2 raw motion).
@[typedef]
pub struct C.XGenericEvent {
pub:
	type      int
	extension int
	evtype    int
}

@[typedef]
pub struct C.XIEventMask {
pub mut:
	deviceid int
	mask_len int
	mask     &u8 = unsafe { nil }
}

@[typedef]
pub struct C.XExposeEvent {
pub:
	type   int
	window u64
	count  int
}

@[typedef]
pub struct C.XMapRequestEvent {
pub:
	type   int
	parent u64
	window u64
}

@[typedef]
pub struct C.XConfigureRequestEvent {
pub:
	type         int
	parent       u64
	window       u64
	x            int
	y            int
	width        int
	height       int
	border_width int
	above        u64
	detail       int
	value_mask   u64
}

@[typedef]
pub struct C.XConfigureEvent {
pub mut:
	type              int
	serial            u64
	send_event        int
	display           &C.Display = unsafe { nil }
	event             u64
	window            u64
	x                 int
	y                 int
	width             int
	height            int
	border_width      int
	above             u64
	override_redirect int
}

@[typedef]
pub struct C.XDestroyWindowEvent {
pub:
	type   int
	event  u64
	window u64
}

@[typedef]
pub struct C.XUnmapEvent {
pub:
	type   int
	event  u64
	window u64
}

@[typedef]
pub struct C.XPropertyEvent {
pub:
	type   int
	window u64
	atom   u64
}

// XEvent is a C union. `pad` reproduces the C definition's `long pad[24]` so
// the union is as big as the real thing (XNextEvent writes up to that many bytes).
@[typedef]
pub union C.XEvent {
pub mut:
	type              int
	xany              C.XAnyEvent
	xkey              C.XKeyEvent
	xbutton           C.XButtonEvent
	xmotion           C.XMotionEvent
	xcrossing         C.XCrossingEvent
	xgeneric          C.XGenericEvent
	xexpose           C.XExposeEvent
	xmaprequest       C.XMapRequestEvent
	xconfigurerequest C.XConfigureRequestEvent
	xconfigure        C.XConfigureEvent
	xdestroywindow    C.XDestroyWindowEvent
	xunmap            C.XUnmapEvent
	xproperty         C.XPropertyEvent
	pad               [24]i64
}

pub struct C.pollfd {
pub mut:
	fd      int
	events  i16
	revents i16
}

// -------------------------------------------------------------------- Xlib fns

fn C.XOpenDisplay(name &char) &C.Display
fn C.XCloseDisplay(d &C.Display) int
fn C.XDefaultScreen(d &C.Display) int
fn C.XRootWindow(d &C.Display, screen int) u64
fn C.XDisplayWidth(d &C.Display, screen int) int
fn C.XDisplayHeight(d &C.Display, screen int) int
fn C.XDefaultVisual(d &C.Display, screen int) &C.Visual
fn C.XDefaultColormap(d &C.Display, screen int) u64
fn C.XDefaultDepth(d &C.Display, screen int) int
fn C.XMatchVisualInfo(d &C.Display, screen int, depth int, class int, vi &C.XVisualInfo) int
fn C.ConnectionNumber(d &C.Display) int
fn C.XSync(d &C.Display, discard int) int
fn C.XFlush(d &C.Display) int
fn C.XPending(d &C.Display) int
fn C.XNextEvent(d &C.Display, ev &C.XEvent) int
fn C.XSetErrorHandler(handler voidptr) voidptr
fn C.XGetErrorText(d &C.Display, code int, buf &char, n int) int
fn C.XInternAtom(d &C.Display, name &char, only_if_exists int) u64
fn C.XFree(p voidptr) int
fn C.XSelectInput(d &C.Display, w u64, mask i64) int
fn C.XCreateSimpleWindow(d &C.Display, parent u64, x int, y int, w u32, h u32, bw u32, border u64, bg u64) u64
fn C.XCreateWindow(d &C.Display, parent u64, x int, y int, w u32, h u32, bw u32, depth int, class u32, visual &C.Visual, valuemask u64, attrs &C.XSetWindowAttributes) u64
fn C.XDestroyWindow(d &C.Display, w u64) int
fn C.XMapWindow(d &C.Display, w u64) int
fn C.XMapRaised(d &C.Display, w u64) int
fn C.XUnmapWindow(d &C.Display, w u64) int
fn C.XMoveWindow(d &C.Display, w u64, x int, y int) int
fn C.XMoveResizeWindow(d &C.Display, w u64, x int, y int, width u32, height u32) int
fn C.XResizeWindow(d &C.Display, w u64, width u32, height u32) int
fn C.XReparentWindow(d &C.Display, w u64, parent u64, x int, y int) int
fn C.XConfigureWindow(d &C.Display, w u64, mask u32, ch &C.XWindowChanges) int
fn C.XRaiseWindow(d &C.Display, w u64) int
fn C.XCheckMaskEvent(d &C.Display, mask i64, ev &C.XEvent) int
fn C.XQueryExtension(d &C.Display, name &char, opcode &int, first_event &int, first_error &int) int
fn C.XIQueryVersion(d &C.Display, major &int, minor &int) int
fn C.XISelectEvents(d &C.Display, w u64, masks &C.XIEventMask, n int) int
fn C.FcConfigAppFontAddFile(cfg voidptr, file &char) int
fn C.XSetWindowBackgroundPixmap(d &C.Display, w u64, pm u64) int
fn C.XCreateBitmapFromData(d &C.Display, drawable u64, data &char, w u32, h u32) u64
fn C.XShapeCombineMask(d &C.Display, dest u64, kind int, x int, y int, src u64, op int)
fn C.XSetWindowBorderWidth(d &C.Display, w u64, bw u32) int
fn C.XSetWindowBackground(d &C.Display, w u64, pixel u64) int
fn C.XClearWindow(d &C.Display, w u64) int
fn C.XAddToSaveSet(d &C.Display, w u64) int
fn C.XChangeWindowAttributes(d &C.Display, w u64, mask u64, attrs &C.XSetWindowAttributes) int
fn C.XGetWindowAttributes(d &C.Display, w u64, wa &C.XWindowAttributes) int
fn C.XQueryTree(d &C.Display, w u64, root &u64, parent &u64, children &&u64, n &u32) int
fn C.XSetInputFocus(d &C.Display, w u64, revert int, time u64) int
fn C.XKillClient(d &C.Display, res u64) int
fn C.XSendEvent(d &C.Display, w u64, propagate int, mask i64, ev &C.XEvent) int
fn C.XGetWMProtocols(d &C.Display, w u64, protos &&u64, n &int) int
fn C.XGetTransientForHint(d &C.Display, w u64, prop_window &u64) int
fn C.XFetchName(d &C.Display, w u64, name &&char) int
fn C.XGetWindowProperty(d &C.Display, w u64, prop u64, off i64, len i64, del int, req_type u64, actual_type &u64, actual_format &int, nitems &u64, bytes_after &u64, prop_ret &&u8) int
fn C.XDeleteProperty(d &C.Display, w u64, prop u64) int
fn C.XChangeProperty(d &C.Display, w u64, prop u64, typ u64, format int, mode int, data &u8, n int) int
fn C.XStringToKeysym(s &char) u64
fn C.XKeysymToKeycode(d &C.Display, keysym u64) u8
fn C.XGrabKey(d &C.Display, keycode int, mods u32, w u64, owner_events int, pmode int, kmode int) int
fn C.XUngrabKey(d &C.Display, keycode int, mods u32, w u64) int
fn C.XGrabButton(d &C.Display, button u32, mods u32, w u64, owner_events int, mask u32, pmode int, kmode int, confine_to u64, cursor u64) int
fn C.XCreateFontCursor(d &C.Display, shape u32) u64
fn C.XDefineCursor(d &C.Display, w u64, cursor u64) int
fn C.XQueryPointer(d &C.Display, w u64, root &u64, child &u64, rx &int, ry &int, wx &int, wy &int, mask &u32) int
fn C.XWarpPointer(d &C.Display, src u64, dst u64, sx int, sy int, sw u32, sh u32, dx int, dy int) int
fn C.XCreatePixmap(d &C.Display, drawable u64, w u32, h u32, depth u32) u64
fn C.XFreePixmap(d &C.Display, p u64) int
fn C.XCreateGC(d &C.Display, drawable u64, mask u64, values voidptr) voidptr
fn C.XFreeGC(d &C.Display, gc voidptr) int
fn C.XSetForeground(d &C.Display, gc voidptr, pixel u64) int
fn C.XFillRectangle(d &C.Display, drawable u64, gc voidptr, x int, y int, w u32, h u32) int
fn C.XCopyArea(d &C.Display, src u64, dst u64, gc voidptr, sx int, sy int, w u32, h u32, dx int, dy int) int

// ------------------------------------------------------------------ Xft / Xinerama

fn C.XftFontOpenName(d &C.Display, screen int, name &char) &C.XftFont
fn C.XftFontClose(d &C.Display, font &C.XftFont)
fn C.XftDrawCreate(d &C.Display, drawable u64, visual &C.Visual, colormap u64) &C.XftDraw
fn C.XftDrawDestroy(draw &C.XftDraw)
fn C.XftDrawStringUtf8(draw &C.XftDraw, color &C.XftColor, font &C.XftFont, x int, y int, s &u8, len int)
fn C.XftTextExtentsUtf8(d &C.Display, font &C.XftFont, s &u8, len int, extents voidptr)
fn C.XftFontOpenPattern(d &C.Display, pattern voidptr) &C.XftFont
fn C.XftGetVersion() int
fn C.XftCharIndex(d &C.Display, font &C.XftFont, ucs4 u32) u32
fn C.XftDefaultSubstitute(d &C.Display, screen int, pattern voidptr)
fn C.XftColorAllocValue(d &C.Display, visual &C.Visual, colormap u64, color &C.XRenderColor, out &C.XftColor) int
fn C.XftColorFree(d &C.Display, visual &C.Visual, colormap u64, color &C.XftColor)

// fontconfig (pulled in by libXft) and locale
fn C.FcNameParse(name &u8) voidptr
fn C.FcPatternDestroy(p voidptr)
fn C.FcCharSetCreate() voidptr
fn C.FcCharSetAddChar(cs voidptr, ucs4 u32) int
fn C.FcCharSetDestroy(cs voidptr)
fn C.FcPatternAddCharSet(p voidptr, object &char, cs voidptr) int
fn C.FcPatternAddBool(p voidptr, object &char, b int) int
fn C.FcConfigSubstitute(cfg voidptr, p voidptr, kind int) int
fn C.FcFontMatch(cfg voidptr, p voidptr, result &int) voidptr
fn C.FcPatternGetString(p voidptr, object &char, n int, s &&u8) int
fn C.setlocale(category int, locale &char) &char
fn C.XSupportsLocale() int
fn C.XSetLocaleModifiers(mods &char) &char
fn C.XGetTextProperty(d &C.Display, w u64, prop &C.XTextProperty, atom u64) int
fn C.Xutf8TextPropertyToTextList(d &C.Display, prop &C.XTextProperty, list &&&char, count &int) int
fn C.XFreeStringList(list &&char)

fn C.XineramaIsActive(d &C.Display) int
fn C.XineramaQueryScreens(d &C.Display, n &int) &C.XineramaScreenInfo

fn C.poll(fds &C.pollfd, nfds u64, timeout int) int

// ------------------------------------------------------------------ constants

// event masks
pub const no_event_mask = i64(0)
pub const key_press_mask = i64(0x1)
pub const button_press_mask = i64(0x4)
pub const button_release_mask = i64(0x8)
pub const enter_window_mask = i64(0x10)
pub const leave_window_mask = i64(0x20)
pub const pointer_motion_mask = i64(0x40)
pub const exposure_mask = i64(0x8000)
pub const structure_notify_mask = i64(0x20000)
pub const substructure_notify_mask = i64(0x80000)
pub const substructure_redirect_mask = i64(0x100000)
pub const focus_change_mask = i64(0x200000)
pub const property_change_mask = i64(0x400000)

// modifier masks
pub const shift_mask = u32(0x1)
pub const lock_mask = u32(0x2)
pub const control_mask = u32(0x4)
pub const mod1_mask = u32(0x8)
pub const mod2_mask = u32(0x10)
pub const mod3_mask = u32(0x20)
pub const mod4_mask = u32(0x40)
pub const mod5_mask = u32(0x80)

// event types
const ev_key_press = 2
const ev_button_press = 4
const ev_button_release = 5
const ev_motion_notify = 6
const ev_enter_notify = 7
const ev_leave_notify = 8
const ev_expose = 12
const ev_destroy_notify = 17
const ev_unmap_notify = 18
const ev_map_request = 20
const ev_configure_request = 23
const ev_property_notify = 28
const ev_client_message = 33
const ev_generic = 35
const xi_raw_motion = 17 // XI_RawMotion
const xi_all_master_devices = 1
const stack_below_mode = 1 // XConfigureWindow stack_mode Below

// XConfigureWindow value mask bits
pub const cw_x = u32(0x1)
pub const cw_y = u32(0x2)
pub const cw_width = u32(0x4)
pub const cw_height = u32(0x8)
pub const cw_border_width = u32(0x10)
pub const cw_sibling = u32(0x20)
pub const cw_stack_mode = u32(0x40)

// XSetWindowAttributes value mask bits
const cw_override_redirect = u64(1) << 9
const cw_event_mask = u64(1) << 11

// ------------------------------------------------------- tiny shared helpers

// GlyphInfo mirrors XGlyphInfo (six 16 bit values); we declare it in V because
// the C field names (xOff, yOff) are not valid V identifiers.
pub struct GlyphInfo {
pub mut:
	width  u16
	height u16
	x      i16
	y      i16
	x_off  i16
	y_off  i16
}

// ------------------------------------------------------------------- XImage

@[typedef]
pub struct C.XImage {
pub mut:
	width          int
	height         int
	data           &char = unsafe { nil }
	bytes_per_line int
	bits_per_pixel int
}

fn C.XCreateImage(d &C.Display, visual &C.Visual, depth u32, format int, offset int, data &char, w u32, h u32, pad int, bpl int) &C.XImage
fn C.XGetImage(d &C.Display, drawable u64, x int, y int, w u32, h u32, plane_mask u64, format int) &C.XImage
fn C.XPutImage(d &C.Display, drawable u64, gc voidptr, img &C.XImage, sx int, sy int, dx int, dy int, w u32, h u32) int
fn C.XDestroyImage(img &C.XImage) int
