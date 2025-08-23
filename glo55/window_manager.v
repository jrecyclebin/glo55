module glo55

import x11

// Monitor identifier type
pub type MonitorId = int

// Core window manager structure
pub struct WindowManager {
pub:
	monitors []Monitor
	layouts  []Layout
	draw     DrawingContext
mut:
	windows []Window
	// Other global state will be added as needed
}

// Monitor representation with workspaces and geometry
pub struct Monitor {
pub:
	workspaces []Workspace
	geometry   ScreenRect
	work_area  ScreenRect
}

// Window representation with client handle and properties
pub struct Window {
pub:
	id Client
mut:
	title string
	flags u32
}
