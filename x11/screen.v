module x11

import log

// C function declarations
fn C.XOpenDisplay(voidptr) &C.Display
fn C.XCloseDisplay(&C.Display) int
fn C.XDefaultScreen(&C.Display) int
fn C.XRootWindow(&C.Display, int) Client
fn C.XCreateFontCursor(&C.Display, u32) C.Cursor
fn C.XDefineCursor(&C.Display, Client, C.Cursor) int
fn C.XUndefineCursor(&C.Display, Client) int
fn C.XChangeWindowAttributes(&C.Display, Client, u32, &C.XSetWindowAttributes) int
fn C.XGetWindowAttributes(&C.Display, Client, &C.XWindowAttributes) int
fn C.XSelectInput(&C.Display, Client, i32)

// C types
@[typedef]
struct C.Display {}

struct C.Pixmap {}

struct C.Colormap {}

type C.Cursor = int

@[typedef]
struct C.XSetWindowAttributes {
	background_pixmap     C.Pixmap
	background_pixel      u32
	border_pixmap         C.Pixmap
	border_pixel          u32
	bit_gravity           int
	win_gravity           int
	backing_store         int
	backing_planes        u32
	backing_pixel         u32
	save_under            int
	event_mask            u32
	do_not_propagate_mask u32
	override_redirect     bool
	colormap              C.Colormap
	cursor                C.Cursor
}

@[typedef]
struct C.XWindowAttributes {
	x            int
	y            int
	width        int
	height       int
	border_width int
}

// X11 connection handle
pub struct X11Connection {
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

pub fn (conn X11Connection) setup_root_window() Client {
	screen := C.XDefaultScreen(conn.display)
	root_window := C.XRootWindow(conn.display, screen)

	// Set event mask and cursor for root window
	cursor := C.XCreateFontCursor(conn.display, xc_left_ptr)
	wa := C.XSetWindowAttributes{
		event_mask: substructure_redirect_mask | substructure_notify_mask | button_press_mask | button_press_mask | pointer_motion_mask | enter_window_mask | leave_window_mask | structure_notify_mask | property_change_mask
		cursor:     cursor
	}
	C.XChangeWindowAttributes(conn.display, root_window, cw_event_mask | cw_cursor, &wa)
	C.XSelectInput(conn.display, root_window, wa.event_mask)
	return root_window
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

// Cursor constants (standard X11 cursor shapes)
pub const xc_x_cursor = 0
pub const xc_arrow = 2
pub const xc_based_arrow_down = 4
pub const xc_based_arrow_up = 6
pub const xc_boat = 8
pub const xc_bogosity = 10
pub const xc_bottom_left_corner = 12
pub const xc_bottom_right_corner = 14
pub const xc_bottom_side = 16
pub const xc_bottom_tee = 18
pub const xc_box_spiral = 20
pub const xc_center_ptr = 22
pub const xc_circle = 24
pub const xc_clock = 26
pub const xc_coffee_mug = 28
pub const xc_cross = 30
pub const xc_cross_reverse = 32
pub const xc_crosshair = 34
pub const xc_diamond_cross = 36
pub const xc_dot = 38
pub const xc_dotbox = 40
pub const xc_double_arrow = 42
pub const xc_draft_large = 44
pub const xc_draft_small = 46
pub const xc_draped_box = 48
pub const xc_exchange = 50
pub const xc_fleur = 52
pub const xc_gobbler = 54
pub const xc_gumby = 56
pub const xc_hand1 = 58
pub const xc_hand2 = 60
pub const xc_heart = 62
pub const xc_icon = 64
pub const xc_iron_cross = 66
pub const xc_left_ptr = 68
pub const xc_left_side = 70
pub const xc_left_tee = 72
pub const xc_leftbutton = 74
pub const xc_ll_angle = 76
pub const xc_lr_angle = 78
pub const xc_man = 80
pub const xc_middlebutton = 82
pub const xc_mouse = 84
pub const xc_pencil = 86
pub const xc_pirate = 88
pub const xc_plus = 90
pub const xc_question_arrow = 92
pub const xc_right_ptr = 94
pub const xc_right_side = 96
pub const xc_right_tee = 98
pub const xc_rightbutton = 100
pub const xc_rtl_logo = 102
pub const xc_sailboat = 104
pub const xc_sb_down_arrow = 106
pub const xc_sb_h_double_arrow = 108
pub const xc_sb_left_arrow = 110
pub const xc_sb_right_arrow = 112
pub const xc_sb_up_arrow = 114
pub const xc_sb_v_double_arrow = 116
pub const xc_shuttle = 118
pub const xc_sizing = 120
pub const xc_spider = 122
pub const xc_spraycan = 124
pub const xc_star = 126
pub const xc_target = 128
pub const xc_tcross = 130
pub const xc_top_left_arrow = 132
pub const xc_top_left_corner = 134
pub const xc_top_right_corner = 136
pub const xc_top_side = 138
pub const xc_top_tee = 140
pub const xc_trek = 142
pub const xc_ul_angle = 144
pub const xc_umbrella = 146
pub const xc_ur_angle = 148
pub const xc_watch = 150
pub const xc_xterm = 152

// Event mask constants for X11 window attributes
// NoEventMask             = 0
pub const key_press_mask = 1 << 0
pub const key_release_mask = 1 << 1
pub const button_press_mask = 1 << 2
pub const button_release_mask = 1 << 3
pub const enter_window_mask = 1 << 4
pub const leave_window_mask = 1 << 5
pub const pointer_motion_mask = 1 << 6
pub const pointer_motion_hint_mask = 1 << 7
pub const button1_motion_mask = 1 << 8
pub const button2_motion_mask = 1 << 9
pub const button3_motion_mask = 1 << 10
pub const button4_motion_mask = 1 << 11
pub const button5_motion_mask = 1 << 12
pub const button_motion_mask = 1 << 13
pub const keymap_state_mask = 1 << 14
pub const exposure_mask = 1 << 15
pub const visibility_change_mask = 1 << 16
pub const structure_notify_mask = 1 << 17
pub const resize_redirect_mask = 1 << 18
pub const substructure_notify_mask = 1 << 19
pub const substructure_redirect_mask = 1 << 20
pub const focus_change_mask = 1 << 21
pub const property_change_mask = 1 << 22
pub const colormap_change_mask = 1 << 23
pub const owner_grab_button_mask = 1 << 24

// Window attribute value mask constants
pub const cw_back_pixmap = 1 << 0
pub const cw_back_pixel = 1 << 1
pub const cw_border_pixmap = 1 << 2
pub const cw_border_pixel = 1 << 3
pub const cw_bit_gravity = 1 << 4
pub const cw_win_gravity = 1 << 5
pub const cw_backing_store = 1 << 6
pub const cw_backing_planes = 1 << 7
pub const cw_backing_pixel = 1 << 8
pub const cw_override_redirect = 1 << 9
pub const cw_save_under = 1 << 10
pub const cw_event_mask = 1 << 11
pub const cw_do_not_propagate_mask = 1 << 12
pub const cw_colormap = 1 << 13
pub const cw_cursor = 1 << 14

// Set cursor for a window
pub fn (conn X11Connection) set_cursor(window Client, cursor C.Cursor) ! {
	result := C.XDefineCursor(conn.display, window, cursor)
	if result != 0 {
		return error('Failed to set cursor')
	}
}

// Remove cursor from a window (revert to default)
pub fn (conn X11Connection) unset_cursor(window Client) ! {
	result := C.XUndefineCursor(conn.display, window)
	if result != 0 {
		return error('Failed to unset cursor')
	}
}

// Convert X11 event to our Event structure
fn x11_event_to_event(xevent C.XEvent) Event {
	event_type := x11_event_to_type(xevent.type)

	// TODO: Extract event-specific data based on event type
	// For now, we'll create basic event structures
	mut data := unsafe { nil }

	match event_type {
		.key_press, .key_release {
			key_data := KeyEvent{
				keycode: 0
				state:   0
				root:    0
				child:   0
				x_root:  0
				y_root:  0
				x:       0
				y:       0
			}
			data = unsafe { &key_data }
		}
		.motion_notify {
			motion_data := MotionEvent{
				x:           0
				y:           0
				x_root:      0
				y_root:      0
				state:       0
				is_hint:     0
				same_screen: false
			}
			data = unsafe { &motion_data }
		}
		.create_notify, .destroy_notify, .map_request, .configure_request {
			window_data := WindowEvent{
				window:            0
				parent:            0
				x:                 0
				y:                 0
				width:             0
				height:            0
				border_width:      0
				override_redirect: false
			}
			data = unsafe { &window_data }
		}
		else {
			data = unsafe { nil }
		}
	}

	return Event{
		type:       event_type
		window:     0 // Will be filled based on event type
		time:       0 // Will be filled based on event type
		serial:     0
		send_event: false
		data:       data
	}
}
