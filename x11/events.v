module x11

// events.v - turns raw XEvents into plain V structs (a sum type) and handles
// keyboard/mouse grabs and the blocking event wait.

pub struct KeyPressEvent {
pub:
	window  Client
	keycode u32
	state   u32
	x_root  int
	y_root  int
}

pub struct ButtonPressEvent {
pub:
	window    Client
	subwindow Client
	button    u32
	state     u32
	x         int
	y         int
	x_root    int
	y_root    int
}

pub struct ButtonReleaseEvent {
pub:
	window Client
	button u32
	x      int // relative to `window`
	y      int
	x_root int
	y_root int
}

pub struct MotionNotifyEvent {
pub:
	window Client
	x      int // relative to `window`
	y      int
	x_root int
	y_root int
}

pub struct EnterNotifyEvent {
pub:
	window Client
	x      int // relative to `window`
	y      int
	x_root int
	y_root int
	mode   int
	detail int
}

pub struct LeaveNotifyEvent {
pub:
	window Client
	x      int
	y      int
	mode   int
	detail int
}

pub struct ExposeEvent {
pub:
	window Client
	count  int
}

pub struct MapRequestEvent {
pub:
	window Client
	parent Client
}

pub struct ConfigureRequestEvent {
pub:
	window       Client
	x            int
	y            int
	width        u32
	height       u32
	border_width u32
	above        Client
	detail       int
	value_mask   u64
}

pub struct DestroyNotifyEvent {
pub:
	window Client
}

pub struct UnmapNotifyEvent {
pub:
	window Client
}

pub struct PropertyNotifyEvent {
pub:
	window Client
	atom   Atom
}

// ClientMessageEvent is a message sent to the root window by a client
// (EWMH requests such as _NET_WM_STATE). `data` holds data.l[0..2].
pub struct ClientMessageEvent {
pub:
	window       Client
	message_type Atom
	format       int
	data         [3]i64
}

// PointerMovedEvent: the user moved the mouse (XInput 2 raw motion, asked for
// with watch_pointer). Warps don't cause one.
pub struct PointerMovedEvent {}

pub struct UnknownEvent {
pub:
	typ int
}

pub type Event = ButtonPressEvent
	| ButtonReleaseEvent
	| ClientMessageEvent
	| ConfigureRequestEvent
	| DestroyNotifyEvent
	| EnterNotifyEvent
	| ExposeEvent
	| KeyPressEvent
	| LeaveNotifyEvent
	| MapRequestEvent
	| MotionNotifyEvent
	| PointerMovedEvent
	| PropertyNotifyEvent
	| UnknownEvent
	| UnmapNotifyEvent

// pending returns how many events are queued.
pub fn (c &X11Connection) pending() int {
	return C.XPending(c.dpy)
}

// wait_for_events blocks up to timeout_ms for the X socket to become readable.
// It returns early if events are already queued. Used so the loop can wake up
// periodically to redraw the toolbar clock.
pub fn (c &X11Connection) wait_for_events(timeout_ms int) {
	if C.XPending(c.dpy) > 0 {
		return
	}
	mut pfd := C.pollfd{
		fd:     C.ConnectionNumber(c.dpy)
		events: 1 // POLLIN
	}
	C.poll(&pfd, 1, timeout_ms)
}

// next_event reads (and blocks for) one event and converts it.
pub fn (c &X11Connection) next_event() Event {
	mut ev := C.XEvent{}
	C.XNextEvent(c.dpy, &ev)
	return convert_event(&ev, c.xi_opcode)
}

// xi_opcode is the connection's XInputExtension opcode (0 = none).
fn convert_event(ev &C.XEvent, xi_opcode int) Event {
	unsafe {
		match ev.type {
			ev_key_press {
				k := ev.xkey
				return KeyPressEvent{
					window:  Client(k.window)
					keycode: k.keycode
					state:   k.state
					x_root:  k.x_root
					y_root:  k.y_root
				}
			}
			ev_button_press {
				b := ev.xbutton
				return ButtonPressEvent{
					window:    Client(b.window)
					subwindow: Client(b.subwindow)
					button:    b.button
					state:     b.state
					x:         b.x
					y:         b.y
					x_root:    b.x_root
					y_root:    b.y_root
				}
			}
			ev_button_release {
				b := ev.xbutton
				return ButtonReleaseEvent{
					window: Client(b.window)
					button: b.button
					x:      b.x
					y:      b.y
					x_root: b.x_root
					y_root: b.y_root
				}
			}
			ev_motion_notify {
				m := ev.xmotion
				return MotionNotifyEvent{
					window: Client(m.window)
					x:      m.x
					y:      m.y
					x_root: m.x_root
					y_root: m.y_root
				}
			}
			ev_enter_notify {
				e := ev.xcrossing
				return EnterNotifyEvent{
					window: Client(e.window)
					x:      e.x
					y:      e.y
					x_root: e.x_root
					y_root: e.y_root
					mode:   e.mode
					detail: e.detail
				}
			}
			ev_leave_notify {
				e := ev.xcrossing
				return LeaveNotifyEvent{
					window: Client(e.window)
					x:      e.x
					y:      e.y
					mode:   e.mode
					detail: e.detail
				}
			}
			ev_expose {
				return ExposeEvent{
					window: Client(ev.xexpose.window)
					count:  ev.xexpose.count
				}
			}
			ev_map_request {
				return MapRequestEvent{
					window: Client(ev.xmaprequest.window)
					parent: Client(ev.xmaprequest.parent)
				}
			}
			ev_configure_request {
				r := ev.xconfigurerequest
				return ConfigureRequestEvent{
					window:       Client(r.window)
					x:            r.x
					y:            r.y
					width:        u32(r.width)
					height:       u32(r.height)
					border_width: u32(r.border_width)
					above:        Client(r.above)
					detail:       r.detail
					value_mask:   r.value_mask
				}
			}
			ev_destroy_notify {
				return DestroyNotifyEvent{
					window: Client(ev.xdestroywindow.window)
				}
			}
			ev_unmap_notify {
				return UnmapNotifyEvent{
					window: Client(ev.xunmap.window)
				}
			}
			ev_property_notify {
				return PropertyNotifyEvent{
					window: Client(ev.xproperty.window)
					atom:   Atom(ev.xproperty.atom)
				}
			}
			ev_client_message {
				// XClientMessageEvent on LP64: window@pad[4], message_type@pad[5],
				// format@pad[6], data.l[0..]@pad[7..] (see close_window)
				return ClientMessageEvent{
					window:       Client(u64(ev.pad[4]))
					message_type: Atom(u64(ev.pad[5]))
					format:       int(i64(ev.pad[6]) & 0xffffffff) // an int + padding: ignore the upper half
					data:         [ev.pad[7], ev.pad[8], ev.pad[9]]!
				}
			}
			ev_generic {
				g := ev.xgeneric
				if xi_opcode != 0 && g.extension == xi_opcode && g.evtype == xi_raw_motion {
					return PointerMovedEvent{}
				}
				return UnknownEvent{
					typ: ev.type
				}
			}
			else {
				return UnknownEvent{
					typ: ev.type
				}
			}
		}
	}
}

// drop_enter_events throws away the EnterNotify events queued so far. Call it
// after moving, mapping or destroying windows: the pointer did not move, so
// windows sliding under it must not take the focus (dwm's restack does this).
pub fn (c &X11Connection) drop_enter_events() {
	C.XSync(c.dpy, 0)
	mut ev := C.XEvent{}
	for C.XCheckMaskEvent(c.dpy, enter_window_mask, &ev) != 0 {
	}
}

// ---------------------------------------------------------- pointer watch

// query_xinput2 returns XInputExtension's opcode once version 2.0 is agreed, or
// 0. We ask for 2.0 on purpose: a 2.0 client gets no raw events while another
// client holds a pointer grab (a drag, an open menu).
fn query_xinput2(dpy &C.Display) int {
	mut opcode, mut ev, mut er := 0, 0, 0
	if C.XQueryExtension(dpy, c'XInputExtension', &opcode, &ev, &er) == 0 {
		return 0
	}
	mut major, mut minor := 2, 0
	if C.XIQueryVersion(dpy, &major, &minor) != 0 || major < 2 {
		return 0
	}
	return opcode
}

// watch_pointer turns PointerMovedEvent on or off. Raw motion arrives
// wherever the pointer is, even over windows that keep their motion events to
// themselves. Without XInput 2 it does nothing.
pub fn (c &X11Connection) watch_pointer(on bool) {
	if c.xi_opcode == 0 {
		return
	}
	mut bits := [u8(0), 0, 0]!
	if on {
		bits[xi_raw_motion / 8] = u8(1) << (xi_raw_motion % 8)
	}
	mut m := C.XIEventMask{
		deviceid: xi_all_master_devices
		mask_len: bits.len
		mask:     unsafe { &bits[0] } // XISelectEvents copies it
	}
	C.XISelectEvents(c.dpy, u64(c.root), &m, 1)
}

// ------------------------------------------------------------------ grabs

// lock_variants are the NumLock/CapsLock combinations we must also grab, or
// bindings silently stop working while those are on.
const lock_variants = [u32(0), lock_mask, mod2_mask, lock_mask | mod2_mask]

// keysym_to_keycode resolves a keysym name ("Return", "j", "1") to a keycode.
// Returns 0 if the name is unknown or unmapped.
pub fn (c &X11Connection) keysym_to_keycode(name string) u32 {
	ks := C.XStringToKeysym(&char(name.str))
	if ks == 0 {
		return 0
	}
	return u32(C.XKeysymToKeycode(c.dpy, ks))
}

// grab_key grabs keycode+modifiers on the root window for all lock states.
pub fn (c &X11Connection) grab_key(keycode u32, mods u32) {
	for lv in lock_variants {
		C.XGrabKey(c.dpy, int(keycode), mods | lv, u64(c.root), 1, 1, 1)
	}
}

pub fn (c &X11Connection) ungrab_all_keys() {
	C.XUngrabKey(c.dpy, 0, 1 << 15, u64(c.root)) // AnyKey, AnyModifier
}

// clean_mods strips NumLock/CapsLock from an event's modifier state.
pub fn clean_mods(state u32) u32 {
	return state & ~(lock_mask | mod2_mask) & 0xff
}
