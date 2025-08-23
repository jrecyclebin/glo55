module x11

import log

// C function declarations
fn C.XOpenDisplay(voidptr) &C.Display
fn C.XCloseDisplay(&C.Display) int
fn C.XDefaultScreen(&C.Display) int
fn C.XRootWindow(&C.Display, int) u64

// C types
@[typedef]
struct C.Display {}

// X11 connection handle
struct X11Connection {
mut:
	display &C.Display = unsafe { nil }
}

// Screen rectangle for positioning
pub struct ScreenRect {
pub:
	x      int
	y      int
	width  u32
	height u32
}

// Helper methods for ScreenRect
fn (r ScreenRect) area() u32 {
	return r.width * r.height
}

fn (r ScreenRect) contains_point(x int, y int) bool {
	return x >= r.x && x < r.x + int(r.width) && y >= r.y && y < r.y + int(r.height)
}

// Connect to X11 server
pub fn connect() !X11Connection {
	display := C.XOpenDisplay(unsafe { nil })
	if display == unsafe { nil } {
		return error('Failed to open X11 display')
	}

	log.info('Successfully connected to X11 display')
	return X11Connection{
		display: display
	}
}

// Close X11 connection
pub fn (mut conn X11Connection) close() {
	if conn.display != unsafe { nil } {
		C.XCloseDisplay(conn.display)
		conn.display = unsafe { nil }
		log.info('X11 display connection closed')
	}
}

// Get the default screen rectangle
pub fn (conn X11Connection) default_screen_rect() ScreenRect {
	screen := C.XDefaultScreen(conn.display)
	root := C.XRootWindow(conn.display, screen)

	mut root_attrs := C.XWindowAttributes{}
	C.XGetWindowAttributes(conn.display, root, &root_attrs)

	return ScreenRect{
		x:      0
		y:      0
		width:  u32(root_attrs.width)
		height: u32(root_attrs.height)
	}
}

// Check if there are pending events
pub fn (conn X11Connection) pending_events() bool {
	return C.XPending(conn.display) > 0
}

// Get the next event (blocking)
pub fn (mut conn X11Connection) next_event() !Event {
	mut xevent := C.XEvent{}
	result := C.XNextEvent(conn.display, &xevent)
	
	if result != 0 {
		return error('Failed to get next event')
	}
	
	return x11_event_to_event(xevent)
}

// Flush the output buffer
pub fn (conn X11Connection) flush() {
	C.XFlush(conn.display)
}

// Convert X11 event to our Event structure
fn x11_event_to_event(xevent C.XEvent) Event {
	event_type := x11_event_to_type(xevent.type)
	
	// TODO: Extract event-specific data based on event type
	// For now, we'll create basic event structures
	mut data := voidptr(0)
	
	match event_type {
		.key_press, .key_release {
			key_data := KeyEvent{
				keycode: 0
				state: 0
				root: 0
				child: 0
				x_root: 0
				y_root: 0
				x: 0
				y: 0
			}
			data = unsafe { &key_data }
		}
		.motion_notify {
			motion_data := MotionEvent{
				x: 0
				y: 0
				x_root: 0
				y_root: 0
				state: 0
				is_hint: 0
				same_screen: false
			}
			data = unsafe { &motion_data }
		}
		.create_notify, .destroy_notify, .map_request, .configure_request {
			window_data := WindowEvent{
				window: 0
				parent: 0
				x: 0
				y: 0
				width: 0
				height: 0
				border_width: 0
				override_redirect: false
			}
			data = unsafe { &window_data }
		}
		else {
			data = voidptr(0)
		}
	}
	
	return Event{
		type: event_type
		window: 0 // Will be filled based on event type
		time: 0   // Will be filled based on event type
		serial: 0
		send_event: false
		data: data
	}
}
