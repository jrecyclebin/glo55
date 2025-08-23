module main

import log
import x11
import glo55

fn main() {
	log.info('Glo55 Window Manager starting...')

	// Initialize X11 connection
	mut conn := x11.connect() or {
		log.error('Failed to connect to X11 server: ${err}')
		return
	}

	// Ensure cleanup on exit
	defer {
		conn.close()
	}

	// Log screen information
	screen_rect := conn.default_screen_rect()
	log.info('Screen dimensions: ${screen_rect.width}x${screen_rect.height}')

	// Initialize window manager
	mut wm := glo55.new_window_manager()
	log.info('Window manager initialized')

	// Create event dispatcher and register window manager as handler
	mut dispatcher := x11.new_event_dispatcher()
	dispatcher.add_handler(&mut wm)

	// Set up signal handling for graceful shutdown
	setup_signal_handlers(mut dispatcher, mut wm)

	log.info('Starting main event loop')
	
	// Run the event loop
	dispatcher.run_event_loop(mut conn) or {
		log.error('Event loop failed: ${err}')
	}

	log.info('Glo55 Window Manager shutting down gracefully')
}

// Set up signal handlers for graceful shutdown
fn setup_signal_handlers(mut dispatcher x11.EventDispatcher, mut wm glo55.WindowManager) {
	// TODO: Implement proper signal handling
	// For now, we'll rely on the event loop running state
	
	log.info('Signal handlers set up (placeholder)')
}
