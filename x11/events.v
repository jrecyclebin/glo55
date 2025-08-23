module x11

import log
import time

// X11 event types enum
pub enum EventType {
    key_press
    key_release
    button_press
    button_release
    motion_notify
    enter_notify
    leave_notify
    focus_in
    focus_out
    keymap_notify
    expose
    graphics_expose
    no_expose
    visibility_notify
    create_notify
    destroy_notify
    unmap_notify
    map_notify
    map_request
    reparent_notify
    configure_notify
    configure_request
    gravity_notify
    resize_request
    circulate_notify
    circulate_request
    property_notify
    selection_clear
    selection_request
    selection_notify
    colormap_notify
    client_message
    mapping_notify
    unknown
}

// Basic event structure
pub struct Event {
pub:
    type     EventType
    window   Client
    time     u64
    serial   u64
    send_event bool
    data     voidptr // Type-specific data
}

// Key event data
pub struct KeyEvent {
pub:
    keycode  u8
    state    u32 // Modifier keys state
    root     Client
    child    Client
    x_root   int
    y_root   int
    x        int
    y        int
}

// Motion event data
pub struct MotionEvent {
pub:
    x        int
    y        int
    x_root   int
    y_root   int
    state    u32 // Button and modifier state
    is_hint  u8
    same_screen bool
}

// Window event data
pub struct WindowEvent {
pub:
    window   Client
    parent   Client
    x        int
    y        int
    width    u32
    height   u32
    border_width u32
    override_redirect bool
}

// Event handler interface
pub interface EventHandler {
mut:
    handle_event(mut event Event) !
}

// Event dispatcher
pub struct EventDispatcher {
mut:
    handlers []EventHandler
    running  bool
    event_count u64
    start_time time.Time
}

// Create new event dispatcher
pub fn new_event_dispatcher() EventDispatcher {
    return EventDispatcher{
        handlers: []
        running: false
        event_count: 0
        start_time: time.now()
    }
}

// Add event handler
pub fn (mut disp EventDispatcher) add_handler(handler EventHandler) {
    disp.handlers << handler
}

// Remove event handler
pub fn (mut disp EventDispatcher) remove_handler(handler EventHandler) {
    mut i := 0
    for i < disp.handlers.len {
        if disp.handlers[i] == handler {
            disp.handlers.delete(i)
            break
        }
        i++
    }
}

// Dispatch event to all handlers
pub fn (mut disp EventDispatcher) dispatch(mut event Event) ! {
    disp.event_count++
    
    log.debug('Dispatching event: ${event.type} for window ${event.window}')
    
    for mut handler in disp.handlers {
        handler.handle_event(mut event) or {
            log.error('Event handler failed for ${event.type}: ${err}')
            // Continue with other handlers even if one fails
        }
    }
}

// Check if dispatcher is running
pub fn (disp EventDispatcher) is_running() bool {
    return disp.running
}

// Get event processing statistics
pub fn (disp EventDispatcher) stats() string {
    elapsed := time.now() - disp.start_time
    rate := if elapsed.seconds() > 0 { f64(disp.event_count) / elapsed.seconds() } else { 0.0 }
    
    return 'Events processed: ${disp.event_count}, Rate: ${rate:.2f} events/sec, Running: ${disp.running}'
}

// Event loop skeleton
pub fn (mut disp EventDispatcher) run_event_loop(mut conn X11Connection) ! {
    disp.running = true
    disp.start_time = time.now()
    
    log.info('Starting event loop')
    
    for disp.running {
        // Check for pending events
        if conn.pending_events() {
            // Process all available events
            for conn.pending_events() && disp.running {
                mut event := conn.next_event() or {
                    log.error('Failed to get next event: ${err}')
                    continue
                }
                
                // Dispatch the event
                disp.dispatch(mut event) or {
                    log.error('Failed to dispatch event: ${err}')
                    continue
                }
            }
        } else {
            // No events pending, sleep briefly to avoid busy waiting
            time.sleep(1 * time.millisecond)
        }
        
        // Flush any pending output
        conn.flush()
        
        // Log statistics periodically
        if disp.event_count % 100 == 0 && disp.event_count > 0 {
            log.info(disp.stats())
        }
    }
    
    log.info('Event loop stopped')
}

// Stop event loop
pub fn (mut disp EventDispatcher) stop() {
    disp.running = false
    log.info('Event loop stop requested')
}

// Convert X11 event type to our enum
fn x11_event_to_type(x11_type int) EventType {
    match x11_type {
        2 { return .key_press }
        3 { return .key_release }
        4 { return .button_press }
        5 { return .button_release }
        6 { return .motion_notify }
        7 { return .enter_notify }
        8 { return .leave_notify }
        9 { return .focus_in }
        10 { return .focus_out }
        11 { return .keymap_notify }
        12 { return .expose }
        13 { return .graphics_expose }
        14 { return .no_expose }
        15 { return .visibility_notify }
        16 { return .create_notify }
        17 { return .destroy_notify }
        18 { return .unmap_notify }
        19 { return .map_notify }
        20 { return .map_request }
        21 { return .reparent_notify }
        22 { return .configure_notify }
        23 { return .configure_request }
        24 { return .gravity_notify }
        25 { return .resize_request }
        26 { return .circulate_notify }
        27 { return .circulate_request }
        28 { return .property_notify }
        29 { return .selection_clear }
        30 { return .selection_request }
        31 { return .selection_notify }
        32 { return .colormap_notify }
        33 { return .client_message }
        34 { return .mapping_notify }
        else { return .unknown }
    }
}
