module x11

// Pure helper only: the rest of x11 is verified functionally (see test/).

fn test_clean_mods_ignores_numlock_and_capslock() {
	assert clean_mods(mod4_mask) == mod4_mask
	assert clean_mods(mod4_mask | lock_mask | mod2_mask) == mod4_mask
	assert clean_mods(mod4_mask | shift_mask | mod2_mask) == (mod4_mask | shift_mask)
	// button state bits above the 8 modifier bits are dropped
	assert clean_mods(mod1_mask | (u32(1) << 8)) == mod1_mask
}

fn test_client_message_is_decoded_from_the_lp64_layout() {
	mut ev := C.XEvent{}
	unsafe {
		ev.pad[0] = ev_client_message
		ev.pad[4] = 0x600001
		ev.pad[5] = 77
		ev.pad[6] = 32 | (i64(0x7ead) << 40) // format is an int; the padding beside it is garbage
		ev.pad[7] = 2 // _NET_WM_STATE_TOGGLE
		ev.pad[8] = 1234
		ev.pad[9] = 0
	}
	e := convert_event(&ev, 0)
	assert e is ClientMessageEvent
	if e is ClientMessageEvent {
		assert e.window == Client(0x600001)
		assert e.message_type == Atom(77)
		assert e.format == 32
		assert e.data[0] == 2 && e.data[1] == 1234 && e.data[2] == 0
	}
}

// raw_motion is an XGenericEvent in the LP64 layout: type@0, extension@32 and
// evtype@36 (two ints sharing pad[4]).
fn raw_motion(extension int, evtype int) C.XEvent {
	mut ev := C.XEvent{}
	unsafe {
		ev.pad[0] = ev_generic
		ev.pad[4] = i64(extension) | (i64(evtype) << 32)
	}
	return ev
}

fn test_xinput_raw_motion_becomes_pointer_moved() {
	ev := raw_motion(131, xi_raw_motion)
	assert convert_event(&ev, 131) is PointerMovedEvent
	// another extension's event, another XInput event, or no XInput at all
	other := raw_motion(140, xi_raw_motion)
	assert convert_event(&other, 131) is UnknownEvent
	press := raw_motion(131, 15) // XI_RawButtonPress
	assert convert_event(&press, 131) is UnknownEvent
	assert convert_event(&ev, 0) is UnknownEvent
}
