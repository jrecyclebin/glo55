module x11

// client.v - the X connection and everything done to individual windows
// ("clients" in X11 speak).
import log

// X11Connection owns the Display pointer and the handful of atoms the WM uses.
@[heap]
pub struct X11Connection {
pub:
	dpy    &C.Display = unsafe { nil }
	screen int
	root   Client
pub mut:
	width             u32
	height            u32
	atom_wm_protocols Atom
	atom_wm_delete    Atom
	atom_wm_state     Atom
	atom_net_wm_name  Atom
	atom_utf8_string  Atom
	// EWMH / private atoms
	atom_net_supported   Atom
	atom_net_wm_state    Atom
	atom_net_wm_state_fs Atom // _NET_WM_STATE_FULLSCREEN
	atom_net_wm_desktop  Atom
	atom_glo55_workspace Atom // per-client placement saved across a restart
	atom_glo55_session   Atom // root property: active workspaces saved across a restart
	fallbacks            &FontFallbacks = unsafe { nil } // per-font fallback cache (xft.v)
	xi_opcode            int // XInputExtension's major opcode (0 = no XInput 2: no pointer watch)
}

// open connects to the X server named by $DISPLAY.
pub fn X11Connection.open() !X11Connection {
	dpy := C.XOpenDisplay(unsafe { nil })
	if isnil(dpy) {
		return error('cannot open X display (is $DISPLAY set?)')
	}
	screen := C.XDefaultScreen(dpy)
	mut conn := X11Connection{
		dpy:       dpy
		screen:    screen
		root:      Client(C.XRootWindow(dpy, screen))
		width:     u32(C.XDisplayWidth(dpy, screen))
		height:    u32(C.XDisplayHeight(dpy, screen))
		fallbacks: &FontFallbacks{}
	}
	conn.atom_wm_protocols = conn.atom('WM_PROTOCOLS')
	conn.atom_wm_delete = conn.atom('WM_DELETE_WINDOW')
	conn.atom_wm_state = conn.atom('WM_STATE')
	conn.atom_net_wm_name = conn.atom('_NET_WM_NAME')
	conn.atom_utf8_string = conn.atom('UTF8_STRING')
	conn.atom_net_supported = conn.atom('_NET_SUPPORTED')
	conn.atom_net_wm_state = conn.atom('_NET_WM_STATE')
	conn.atom_net_wm_state_fs = conn.atom('_NET_WM_STATE_FULLSCREEN')
	conn.atom_net_wm_desktop = conn.atom('_NET_WM_DESKTOP')
	conn.atom_glo55_workspace = conn.atom('_GLO55_WORKSPACE')
	conn.atom_glo55_session = conn.atom('_GLO55_SESSION')
	conn.xi_opcode = query_xinput2(dpy)
	return conn
}

pub fn (c &X11Connection) close() {
	C.XCloseDisplay(c.dpy)
}

pub fn (c &X11Connection) atom(name string) Atom {
	return Atom(C.XInternAtom(c.dpy, &char(name.str), 0))
}

pub fn (c &X11Connection) sync() {
	C.XSync(c.dpy, 0)
}

pub fn (c &X11Connection) flush() {
	C.XFlush(c.dpy)
}

// ---------------------------------------------------------------- X errors

// During start-up the only error we care about is BadAccess from selecting
// SubstructureRedirect on the root: it means another WM owns the screen.
fn startup_error_handler(_ &C.Display, e &C.XErrorEvent) int {
	log.error('another window manager is already running (X error ${e.error_code} on request ${e.request_code})')
	exit(1)
}

// Windows vanish at any moment so BadWindow & co. are normal races. Log and
// carry on instead of crashing.
fn runtime_error_handler(d &C.Display, e &C.XErrorEvent) int {
	mut buf := [128]char{}
	C.XGetErrorText(d, e.error_code, &buf[0], 128)
	msg := unsafe { cstring_to_vstring(&buf[0]) }
	// 3 = BadWindow, 8 = BadMatch, 9 = BadDrawable: expected when clients die mid-request
	if e.error_code in [u8(3), 8, 9] {
		log.debug('ignored X error: ${msg} (request ${e.request_code}, resource 0x${e.resourceid:x})')
	} else {
		log.error('X error: ${msg} (request ${e.request_code}, resource 0x${e.resourceid:x})')
	}
	return 0
}

// become_window_manager claims SubstructureRedirect on the root window. If
// another WM is running the startup handler logs a log.error and exits.
pub fn (c &X11Connection) become_window_manager() {
	C.XSetErrorHandler(voidptr(startup_error_handler))
	C.XSelectInput(c.dpy, u64(c.root),
		substructure_redirect_mask | substructure_notify_mask | pointer_motion_mask | property_change_mask)
	C.XSync(c.dpy, 0) // forces the BadAccess (if any) to be delivered right now
	C.XSetErrorHandler(voidptr(runtime_error_handler))
}

// ---------------------------------------------------------- window geometry

pub struct WindowAttributes {
pub:
	x                 int
	y                 int
	width             u32
	height            u32
	viewable          bool
	override_redirect bool
}

pub fn (c &X11Connection) get_attributes(w Client) ?WindowAttributes {
	mut wa := C.XWindowAttributes{}
	if C.XGetWindowAttributes(c.dpy, u64(w), &wa) == 0 {
		return none
	}
	return WindowAttributes{
		x:                 wa.x
		y:                 wa.y
		width:             u32(wa.width)
		height:            u32(wa.height)
		viewable:          wa.map_state == 2 // IsViewable
		override_redirect: wa.override_redirect != 0
	}
}

// existing_windows lists the top level children of the root (used to adopt
// windows that already exist when the WM starts).
pub fn (c &X11Connection) existing_windows() []Client {
	mut r := u64(0)
	mut p := u64(0)
	mut kids := &u64(unsafe { nil })
	mut n := u32(0)
	mut out := []Client{}
	if C.XQueryTree(c.dpy, u64(c.root), &r, &p, &kids, &n) == 0 {
		return out
	}
	for i in 0 .. int(n) {
		out << Client(unsafe { kids[i] })
	}
	if !isnil(kids) {
		C.XFree(kids)
	}
	return out
}

pub fn (c &X11Connection) move_resize(w Client, x int, y int, width u32, height u32) {
	C.XMoveResizeWindow(c.dpy, u64(w), x, y, if width < 1 { 1 } else { width }, if height < 1 {
		1
	} else {
		height
	})
}

pub fn (c &X11Connection) map_window(w Client) {
	C.XMapWindow(c.dpy, u64(w))
}

// move_window moves a window without resizing it.
pub fn (c &X11Connection) move_window(w Client, x int, y int) {
	C.XMoveWindow(c.dpy, u64(w), x, y)
}

pub fn (c &X11Connection) unmap_window(w Client) {
	C.XUnmapWindow(c.dpy, u64(w))
}

pub fn (c &X11Connection) raise_window(w Client) {
	C.XRaiseWindow(c.dpy, u64(w))
}

pub fn (c &X11Connection) destroy_window(w Client) {
	C.XDestroyWindow(c.dpy, u64(w))
}

// stack_below restacks `w` directly under `sibling` (both children of the root).
pub fn (c &X11Connection) stack_below(w Client, sibling Client) {
	mut wc := C.XWindowChanges{
		sibling:    u64(sibling)
		stack_mode: stack_below_mode
	}
	C.XConfigureWindow(c.dpy, u64(w), cw_sibling | cw_stack_mode, &wc)
}

pub fn (c &X11Connection) set_input_focus(w Client) {
	C.XSetInputFocus(c.dpy, u64(w), 1, 0) // RevertToPointerRoot, CurrentTime
}

pub fn (c &X11Connection) set_border_width(w Client, bw u32) {
	C.XSetWindowBorderWidth(c.dpy, u64(w), bw)
}

pub fn (c &X11Connection) add_to_save_set(w Client) {
	C.XAddToSaveSet(c.dpy, u64(w))
}

pub fn (c &X11Connection) select_input(w Client, mask i64) {
	C.XSelectInput(c.dpy, u64(w), mask)
}

pub fn (c &X11Connection) reparent(w Client, parent Client, x int, y int) {
	C.XReparentWindow(c.dpy, u64(w), u64(parent), x, y)
}

// create_frame makes the window that wraps a client: it draws the theme's
// border/decorations around the client, which is reparented inside it.
pub fn (c &X11Connection) create_frame(x int, y int, width u32, height u32) Client {
	mut attrs := C.XSetWindowAttributes{
		override_redirect: 1 // frames are ours; nobody (including us) redirects them
		event_mask:        substructure_redirect_mask | substructure_notify_mask | exposure_mask | enter_window_mask | leave_window_mask | button_press_mask | button_release_mask | pointer_motion_mask
	}
	w := C.XCreateWindow(c.dpy, u64(c.root), x, y, width, height, 0, 0, 1, // CopyFromParent depth/visual, InputOutput
	 unsafe { nil }, cw_override_redirect | cw_event_mask, &attrs)
	return Client(w)
}

// clear_shape removes any XShape bounding clip: the window is a plain rectangle again.
pub fn (c &X11Connection) clear_shape(w Client) {
	C.XShapeCombineMask(c.dpy, u64(w), 0, 0, 0, 0, 0) // ShapeBounding, src None, ShapeSet
}

// set_shape clips a window to a bitmap (XShape bounding region): one bit per
// pixel, LSB first, each row padded to a whole byte; 1 = visible.
pub fn (c &X11Connection) set_shape(w Client, width u32, height u32, bits []u8) {
	bm := C.XCreateBitmapFromData(c.dpy, u64(c.root), &char(bits.data), width, height)
	C.XShapeCombineMask(c.dpy, u64(w), 0, 0, 0, bm, 0) // ShapeBounding, ShapeSet
	C.XFreePixmap(c.dpy, bm)
}

// create_bar makes a toolbar window (override redirect so nobody manages it).
pub fn (c &X11Connection) create_bar(x int, y int, width u32, height u32) Client {
	mut attrs := C.XSetWindowAttributes{
		override_redirect: 1
		event_mask:        exposure_mask | button_press_mask | button_release_mask | enter_window_mask | leave_window_mask | pointer_motion_mask
	}
	w := C.XCreateWindow(c.dpy, u64(c.root), x, y, width, height, 0, 0, 1, unsafe { nil },
		cw_override_redirect | cw_event_mask, &attrs)
	return Client(w)
}

// send_configure_notify tells a client its (unchanged) geometry, as ICCCM
// requires when we refuse or ignore a ConfigureRequest.
pub fn (c &X11Connection) send_configure_notify(w Client, x int, y int, width u32, height u32, border_width u32) {
	mut ev := C.XEvent{}
	unsafe {
		ev.xconfigure.type = 22 // ConfigureNotify
		ev.xconfigure.display = c.dpy
		ev.xconfigure.event = u64(w)
		ev.xconfigure.window = u64(w)
		ev.xconfigure.x = x
		ev.xconfigure.y = y
		ev.xconfigure.width = int(width)
		ev.xconfigure.height = int(height)
		ev.xconfigure.border_width = int(border_width)
		ev.xconfigure.above = 0
		ev.xconfigure.override_redirect = 0
	}
	C.XSendEvent(c.dpy, u64(w), 0, structure_notify_mask, &ev)
}

// configure_passthrough forwards an unmanaged window's ConfigureRequest as-is.
pub fn (c &X11Connection) configure_passthrough(e ConfigureRequestEvent) {
	mut wc := C.XWindowChanges{
		x:            e.x
		y:            e.y
		width:        int(e.width)
		height:       int(e.height)
		border_width: int(e.border_width)
		sibling:      u64(e.above)
		stack_mode:   e.detail
	}
	C.XConfigureWindow(c.dpy, u64(e.window), u32(e.value_mask), &wc)
}

// ------------------------------------------------------------- client props

// raw_property reads a window property of any type. Returns the type atom
// and the bytes (format 8 properties only), or none if it is unset / not bytes.
fn (c &X11Connection) raw_property(w Client, prop Atom) ?(Atom, []u8) {
	mut actual_type := u64(0)
	mut actual_format := 0
	mut nitems := u64(0)
	mut after := u64(0)
	mut data := &u8(unsafe { nil })
	if C.XGetWindowProperty(c.dpy, u64(w), u64(prop), 0, 1024, 0, 0, &actual_type, &actual_format, &nitems, &after, &data) != 0
		|| isnil(data) {
		return none
	}
	defer {
		C.XFree(data)
	}
	if actual_type == 0 || actual_format != 8 || nitems == 0 {
		return none
	}
	mut b := []u8{len: int(nitems)}
	for i in 0 .. int(nitems) {
		b[i] = unsafe { data[i] }
	}
	return Atom(actual_type), b
}

// compound_to_utf8 converts a COMPOUND_TEXT (or other non-UTF8, non-Latin-1
// type such as TEXT) WM_NAME to UTF-8 with Xlib's converters, which need the
// locale set up by init_locale(). Returns '' if Xlib can't convert it.
fn (c &X11Connection) compound_to_utf8(w Client, prop Atom) string {
	mut tp := C.XTextProperty{}
	if C.XGetTextProperty(c.dpy, u64(w), &tp, u64(prop)) == 0 || isnil(tp.value) {
		return ''
	}
	mut list := unsafe { &&char(nil) }
	mut count := 0
	mut out := ''
	if C.Xutf8TextPropertyToTextList(c.dpy, &tp, &list, &count) >= 0 && !isnil(list) && count > 0 {
		mut parts := []string{}
		for i in 0 .. count {
			p := unsafe { list[i] }
			if !isnil(p) {
				parts << sanitize_title(unsafe { cstring_to_vstring(p) }.bytes())
			}
		}
		out = parts.join(' ')
		C.XFreeStringList(list)
	}
	C.XFree(tp.value)
	return out
}

// get_title returns the window title as clean UTF-8. _NET_WM_NAME
// (UTF8_STRING) wins; otherwise WM_NAME is decoded according to its type:
// STRING is Latin-1, UTF8_STRING is UTF-8, anything else (COMPOUND_TEXT) goes
// through Xlib's converter. Invalid bytes never reach the drawing code.
pub fn (c &X11Connection) get_title(w Client) string {
	if typ, b := c.raw_property(w, c.atom_net_wm_name) {
		if typ == c.atom_utf8_string {
			return sanitize_title(b)
		}
		if typ == xa_string {
			return latin1_to_utf8(b)
		}
	}
	if typ, b := c.raw_property(w, xa_wm_name) {
		if typ == c.atom_utf8_string {
			return sanitize_title(b)
		}
		if typ == xa_string { // ISO 8859-1
			return latin1_to_utf8(b)
		}
		s := c.compound_to_utf8(w, xa_wm_name)
		if s != '' {
			return s
		}
		log.warn('window 0x${w:x}: cannot convert WM_NAME of type ${typ} (locale not set up for it?)')
	}
	return ''
}

// init_locale makes Xlib's text converters (COMPOUND_TEXT -> UTF-8) work.
// Only LC_CTYPE is set, so number formatting etc. stay in the C locale. If the
// environment's locale is missing or not supported by Xlib, C.UTF-8 is tried.
pub fn init_locale() {
	C.setlocale(C.LC_CTYPE, c'')
	if C.XSupportsLocale() == 0 {
		log.warn('the locale from the environment is not supported by Xlib; trying C.UTF-8')
		C.setlocale(C.LC_CTYPE, c'C.UTF-8')
		if C.XSupportsLocale() == 0 {
			log.warn('no usable locale: non-UTF-8 window titles (COMPOUND_TEXT) may show as blank')
		}
	}
	C.XSetLocaleModifiers(c'')
}

// is_transient reports whether the window has WM_TRANSIENT_FOR (dialogs):
// those are shown floating.
pub fn (c &X11Connection) is_transient(w Client) bool {
	mut parent := u64(0)
	return C.XGetTransientForHint(c.dpy, u64(w), &parent) != 0
}

// close_window asks politely (WM_DELETE_WINDOW) and falls back to XKillClient.
pub fn (c &X11Connection) close_window(w Client) {
	mut protos := &u64(unsafe { nil })
	mut n := 0
	mut supports := false
	if C.XGetWMProtocols(c.dpy, u64(w), &protos, &n) != 0 {
		for i in 0 .. n {
			if unsafe { protos[i] } == u64(c.atom_wm_delete) {
				supports = true
			}
		}
		C.XFree(protos)
	}
	if supports {
		// Build an XClientMessageEvent by hand: its `data` member is an
		// anonymous C union that V can't name, so write the LP64 layout
		// directly into the event's long[24] pad (type@0, window@32,
		// message_type@40, format@48, data.l[0]@56, data.l[1]@64).
		mut ev := C.XEvent{}
		unsafe {
			ev.pad[0] = ev_client_message
			ev.pad[4] = i64(w)
			ev.pad[5] = i64(c.atom_wm_protocols)
			ev.pad[6] = 32
			ev.pad[7] = i64(c.atom_wm_delete)
			ev.pad[8] = 0 // CurrentTime
		}
		C.XSendEvent(c.dpy, u64(w), 0, no_event_mask, &ev)
	} else {
		C.XKillClient(c.dpy, u64(w))
	}
}

// ------------------------------------------------- 32-bit properties (EWMH)

const xa_atom = u64(4)
const xa_cardinal = u64(6)

// set_cardinals writes a CARDINAL[] property (format 32).
pub fn (c &X11Connection) set_cardinals(w Client, prop Atom, vals []i64) {
	C.XChangeProperty(c.dpy, u64(w), u64(prop), xa_cardinal, 32, 0, &u8(vals.data), vals.len)
}

// set_atoms writes an ATOM[] property (format 32); an empty list is fine.
pub fn (c &X11Connection) set_atoms(w Client, prop Atom, vals []Atom) {
	mut longs := []i64{cap: vals.len}
	for v in vals {
		longs << i64(v)
	}
	C.XChangeProperty(c.dpy, u64(w), u64(prop), xa_atom, 32, 0, &u8(longs.data), longs.len)
}

// get_longs reads any format-32 property as a list of numbers (CARDINAL,
// ATOM, ...), or none if it is unset or not 32-bit.
pub fn (c &X11Connection) get_longs(w Client, prop Atom) ?[]i64 {
	mut actual_type := u64(0)
	mut actual_format := 0
	mut nitems := u64(0)
	mut after := u64(0)
	mut data := &u8(unsafe { nil })
	if C.XGetWindowProperty(c.dpy, u64(w), u64(prop), 0, 1024, 0, 0, &actual_type, &actual_format, &nitems, &after, &data) != 0
		|| isnil(data) {
		return none
	}
	defer {
		C.XFree(data)
	}
	if actual_type == 0 || actual_format != 32 {
		return none
	}
	longs := unsafe { &i64(data) } // Xlib hands format-32 data over as C longs
	mut out := []i64{len: int(nitems)}
	for i in 0 .. int(nitems) {
		out[i] = unsafe { longs[i] }
	}
	return out
}

pub fn (c &X11Connection) delete_property(w Client, prop Atom) {
	C.XDeleteProperty(c.dpy, u64(w), u64(prop))
}

// has_atom_in reports whether an ATOM[] property (e.g. _NET_WM_STATE) holds `a`.
pub fn (c &X11Connection) has_atom_in(w Client, prop Atom, a Atom) bool {
	vals := c.get_longs(w, prop) or { return false }
	return i64(a) in vals
}

// publish_supported advertises the EWMH hints this WM understands on the root.
pub fn (c &X11Connection) publish_supported() {
	c.set_atoms(c.root, c.atom_net_supported, [c.atom_net_supported, c.atom_net_wm_state,
		c.atom_net_wm_state_fs, c.atom_net_wm_desktop])
}

// release_root stops managing: drops the root event selection (so a new WM, or
// this very binary after exec, can claim SubstructureRedirect) and all key grabs.
pub fn (c &X11Connection) release_root() {
	C.XSelectInput(c.dpy, u64(c.root), 0)
	c.ungrab_all_keys()
	C.XSync(c.dpy, 0)
}
