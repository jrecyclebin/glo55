module glo55

import x11
import log
import time

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
	running bool
	event_stats EventStats
	// Other global state will be added as needed
}

// Create new window manager
pub fn new_window_manager() WindowManager {
    return WindowManager{
        monitors: []
        layouts: []
        draw: DrawingContext{}
        windows: []
        running: true
        event_stats: EventStats{
            total_events: 0
            key_press_events: 0
            key_release_events: 0
            motion_events: 0
            window_events: 0
            unknown_events: 0
            start_time: time.now()
            last_event_time: time.now()
        }
    }
}

// Event processing statistics
pub struct EventStats {
pub mut:
	total_events      u64
	key_press_events  u64
	key_release_events u64
	motion_events     u64
	window_events     u64
	unknown_events    u64
	start_time        time.Time
	last_event_time   time.Time
}

// Monitor representation with workspaces and geometry
pub struct Monitor {
pub:
	workspaces []Workspace
	geometry   x11.ScreenRect
	work_area  x11.ScreenRect
}

// Window representation with client handle and properties
pub struct Window {
pub:
	id x11.Client
mut:
	title string
	flags u32
}

// Implement EventHandler interface for WindowManager
pub fn (mut wm WindowManager) handle_event(mut event x11.Event) ! {
    wm.event_stats.total_events++
    wm.event_stats.last_event_time = time.now()
    
    log.debug('WindowManager handling event: ${event.type}')
    
    match event.type {
        .key_press {
            wm.event_stats.key_press_events++
            wm.on_key_press(unsafe { &x11.KeyEvent(event.data) })!
        }
        .key_release {
            wm.event_stats.key_release_events++
            // Handle key release if needed
        }
        .motion_notify {
            wm.event_stats.motion_events++
            wm.on_motion_notify(unsafe { &x11.MotionEvent(event.data) })!
        }
        .create_notify {
            wm.event_stats.window_events++
            wm.on_window_open(unsafe { &x11.WindowEvent(event.data) })!
        }
        .destroy_notify {
            wm.event_stats.window_events++
            wm.on_window_close(unsafe { &x11.WindowEvent(event.data) })!
        }
        .map_request {
            wm.event_stats.window_events++
            wm.on_window_map_request(unsafe { &x11.WindowEvent(event.data) })!
        }
        .configure_request {
            wm.event_stats.window_events++
            wm.on_window_configure(unsafe { &x11.WindowEvent(event.data) })!
        }
        else {
            wm.event_stats.unknown_events++
            log.debug('Unhandled event type: ${event.type}')
        }
    }
    
    // Log event statistics periodically
    if wm.event_stats.total_events % 50 == 0 {
        wm.log_event_stats()
    }
}

// Event handler methods
pub fn (mut wm WindowManager) on_window_open(window_event &x11.WindowEvent) ! {
    log.info('Window opened: ${window_event.window} at (${window_event.x}, ${window_event.y}) size ${window_event.width}x${window_event.height}')
    
    // Create new window in our tracking
    new_window := Window{
        id: window_event.window
        title: 'Window ${window_event.window}'
        flags: 0
    }
    
    wm.windows << new_window
    log.info('Now managing ${wm.windows.len} windows')
}

pub fn (mut wm WindowManager) on_window_close(window_event &x11.WindowEvent) ! {
    log.info('Window closed: ${window_event.window}')
    
    // Find and remove the window from our tracking
    mut i := 0
    for i < wm.windows.len {
        if wm.windows[i].id == window_event.window {
            wm.windows.delete(i)
            log.info('Removed window, now managing ${wm.windows.len} windows')
            break
        }
        i++
    }
}

pub fn (mut wm WindowManager) on_key_press(key_event &x11.KeyEvent) ! {
    log.info('Key pressed: keycode=${key_event.keycode} state=${key_event.state} at (${key_event.x}, ${key_event.y})')
    
    // Basic key handling for window manager operations
    // TODO: Add specific key bindings for window manager functions
    // For example: Alt+Tab for window switching, etc.
    log.debug('Unbound key pressed: ${key_event.keycode}')
}

pub fn (mut wm WindowManager) on_motion_notify(motion_event &x11.MotionEvent) ! {
    // Only log motion events occasionally to avoid spam
    if wm.event_stats.motion_events % 10 == 0 {
        log.debug('Motion: (${motion_event.x}, ${motion_event.y}) state=${motion_event.state}')
    }
}

pub fn (mut wm WindowManager) on_window_map_request(window_event &x11.WindowEvent) ! {
    log.info('Map request for window: ${window_event.window}')
    // TODO: Implement window mapping logic
}

pub fn (mut wm WindowManager) on_window_configure(window_event &x11.WindowEvent) ! {
    log.debug('Configure request for window: ${window_event.window} ${window_event.width}x${window_event.height}')
    // TODO: Implement window configuration logic
}

// Event logging and statistics
pub fn (mut wm WindowManager) log_event_stats() {
    elapsed := time.now() - wm.event_stats.start_time
    rate := if elapsed.seconds() > 0 { f64(wm.event_stats.total_events) / elapsed.seconds() } else { 0.0 }
    
    log.info('Event Stats - Total: ${wm.event_stats.total_events}, Rate: ${rate:.2f}/sec, ' +
             'Keys: ${wm.event_stats.key_press_events}, Motion: ${wm.event_stats.motion_events}, ' +
             'Windows: ${wm.event_stats.window_events}, Unknown: ${wm.event_stats.unknown_events}')
}

// Initialize event statistics
pub fn (mut wm WindowManager) init_event_stats() {
    wm.event_stats = EventStats{
        total_events: 0
        key_press_events: 0
        key_release_events: 0
        motion_events: 0
        window_events: 0
        unknown_events: 0
        start_time: time.now()
        last_event_time: time.now()
    }
}

// Check if window manager should continue running
pub fn (wm WindowManager) is_running() bool {
    return wm.running
}

// Request graceful shutdown
pub fn (mut wm WindowManager) shutdown() {
    wm.running = false
    log.info('Window manager shutdown requested')
    wm.log_event_stats()
}
