module x11

#include <X11/Xlib.h>
#flag -lX11

// C function declarations
fn C.XGetWindowAttributes(&C.Display, u64, &C.XWindowAttributes) int
fn C.XNextEvent(&C.Display, &C.XEvent) int
fn C.XPending(&C.Display) int
fn C.XFlush(&C.Display) int

// Core X11 types
pub type Client = u64
pub type Atom = u64
pub type X11Color = u64

// C types
@[typedef]
struct C.XWindowAttributes {
	x            int
	y            int
	width        int
	height       int
	border_width int
	depth        int
	// ... other fields we don't need for now
}

// X11 Event structure (simplified)
@[typedef]
struct C.XEvent {
	type int
	// ... other fields we'll access as needed
}
