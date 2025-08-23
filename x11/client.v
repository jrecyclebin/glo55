module x11

import log

#include <X11/Xlib.h>
#flag -lX11

// C function declarations
fn C.XOpenDisplay(voidptr) &C.Display
fn C.XCloseDisplay(&C.Display) int
fn C.XDefaultScreen(&C.Display) int
fn C.XRootWindow(&C.Display, int) u64
fn C.XGetWindowAttributes(&C.Display, u64, &C.XWindowAttributes) int

// Core X11 types
type Client = u64
type Atom = u64
type X11Color = u64

// C types
@[typedef]
struct C.Display {}

@[typedef]
struct C.XWindowAttributes {
    x               int
    y               int
    width           int
    height          int
    border_width    int
    depth           int
    // ... other fields we don't need for now
}

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
        x: 0
        y: 0
        width: u32(root_attrs.width)
        height: u32(root_attrs.height)
    }
}