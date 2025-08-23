module main

import log
import x11

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
    
    // TODO: Add main event loop
    
    log.info('Glo55 Window Manager shutting down')
}