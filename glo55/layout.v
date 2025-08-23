module glo55

import x11

// Layout interface for different window arrangement strategies
pub interface Layout {
	// Arrange windows within the given workspace area
	arrange(workspace &Workspace, area ScreenRect) []WindowUpdate
}

// Window update information for layout changes
pub struct WindowUpdate {
pub:
	window_index int
	target_rect  ScreenRect
}

// Tiling layout implementation with master/stack configuration
pub struct TilingLayout {
pub:
	master_ratio f32
	gap_width    u32
	border_width u32
}
