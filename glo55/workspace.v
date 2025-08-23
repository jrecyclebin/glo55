module glo55

import x11

// Workspace containing windows and layout configuration
pub struct Workspace {
pub:
	title  string
	layout &Layout
mut:
	windows []WindowSpec
}

// Window specification with window reference and position/size
pub struct WindowSpec {
pub:
	info &Window
mut:
	rect ScreenRect
}
