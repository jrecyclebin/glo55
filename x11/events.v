module x11

// X11 event types enum
pub enum EventType {
	key_press
	key_release
	button_press
	button_release
	motion_notify
	enter_notify
	leave_notify
	focus_in
	focus_out
	keymap_notify
	expose
	graphics_expose
	no_expose
	visibility_notify
	create_notify
	destroy_notify
	unmap_notify
	map_notify
	map_request
	reparent_notify
	configure_notify
	configure_request
	gravity_notify
	resize_request
	circulate_notify
	circulate_request
	property_notify
	selection_clear
	selection_request
	selection_notify
	colormap_notify
	client_message
	mapping_notify
	unknown
}

// Basic event structure
pub struct Event {
pub:
	type       EventType
	window     Client
	time       u64
	serial     u64
	send_event bool
	data       voidptr // Type-specific data
}

// Key event data
pub struct KeyEvent {
pub:
	keycode u8
	state   u32 // Modifier keys state
	root    Client
	child   Client
	x_root  int
	y_root  int
	x       int
	y       int
}

// Motion event data
pub struct MotionEvent {
pub:
	x           int
	y           int
	x_root      int
	y_root      int
	state       u32 // Button and modifier state
	is_hint     u8
	same_screen bool
}

// Window event data
pub struct WindowEvent {
pub:
	window            Client
	parent            Client
	x                 int
	y                 int
	width             u32
	height            u32
	border_width      u32
	override_redirect bool
}

// Convert X11 event type to our enum
fn x11_event_to_type(x11_type int) EventType {
	match x11_type {
		2 { return .key_press }
		3 { return .key_release }
		4 { return .button_press }
		5 { return .button_release }
		6 { return .motion_notify }
		7 { return .enter_notify }
		8 { return .leave_notify }
		9 { return .focus_in }
		10 { return .focus_out }
		11 { return .keymap_notify }
		12 { return .expose }
		13 { return .graphics_expose }
		14 { return .no_expose }
		15 { return .visibility_notify }
		16 { return .create_notify }
		17 { return .destroy_notify }
		18 { return .unmap_notify }
		19 { return .map_notify }
		20 { return .map_request }
		21 { return .reparent_notify }
		22 { return .configure_notify }
		23 { return .configure_request }
		24 { return .gravity_notify }
		25 { return .resize_request }
		26 { return .circulate_notify }
		27 { return .circulate_request }
		28 { return .property_notify }
		29 { return .selection_clear }
		30 { return .selection_request }
		31 { return .selection_notify }
		32 { return .colormap_notify }
		33 { return .client_message }
		34 { return .mapping_notify }
		else { return .unknown }
	}
}
