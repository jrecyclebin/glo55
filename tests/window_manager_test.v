module tests

import glo55

// Test basic event filtering functionality
fn test_new_window_manager() {
	wm := glo55.new_window_manager()
  assert wm.is_running() == true
}
