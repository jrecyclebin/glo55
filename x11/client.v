module x11

#include <X11/Xlib.h>
#flag -lX11

// C function declarations
fn C.XGetWindowAttributes(&C.Display, u64, &C.XWindowAttributes) int

// Core X11 types
type Client = u64
type Atom = u64
type X11Color = u64

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
