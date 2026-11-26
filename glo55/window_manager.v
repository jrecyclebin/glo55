module glo55

// window_manager.v - the WindowManager: central event router and
// multi-monitor coordinator. It owns all state and is the only place that
// performs X side effects for window management; the layout/workspace/theme
// code it drives is pure and unit tested.
//
// Flow for a new window (see SPEC.md "Layout Management Workflow"):
//   MapRequest -> on_window_open -> Workspace.add -> Layout.arrange
//   -> WindowUpdate list -> X moves frames -> Workspace.apply_updates
import log
import os
import time
import x11

// WindowUpdate describes one window operation. It contains only windows
// requiring actual changes. `window_index` refers to an index in a
// workspace's array of windows (passed into `Layout.arrange`).
pub struct WindowUpdate {
pub:
	window_index int
	target_rect  ScreenRect
}

// BoundKey is a keybinding resolved to an X keycode (needs a live display).
struct BoundKey {
	keycode u32
	mods    u32
	action  Action
}

// WindowManager contains all monitor and window state. It implements both
// ConfigTarget and ThemeTarget (their fields are the pub mut ones below).
pub struct WindowManager {
pub:
	conn &x11.X11Connection
pub mut:
	monitors []Monitor
	layouts  []Layout
	draw     DrawingContext
	windows  []&Window
	// -- ConfigTarget
	mod_mask        u32
	monitor_configs []MonitorConfig
	keybindings     []KeyBinding
	master_ratio    f32
	theme_path      string
	timezone        string
	time_format     string
	date_format     string
	// -- ThemeTarget
	theme_vars              map[string]string
	theme_dir               string
	window_themes           []ThemeSection
	toolbar_themes          []ThemeSection
	theme_font_files        []string
	theme_background        string
	theme_background_scale  string
	theme_background_filter string
	// -- runtime state
	active_monitor       MonitorId
	focused_client       x11.Client // client that has input focus (0 = none)
	running              bool = true
	collapse_seq         u64
	bound_keys           []BoundKey
	config_path          string       // config.toml the WM was started with (for `reload`)
	orig_tz              string       // $TZ at startup, restored when a reload drops [general] timezone
	shaped_frames        map[u64]bool // frames that currently carry an XShape clip
	frame_hover_win      x11.Client   // client whose title-bar button is hovered (0 = none)
	frame_hover_action   string
	frame_pressed_win    x11.Client
	frame_pressed_action string
	cpu_percent          int
	cpu_prev_total       u64
	cpu_prev_idle        u64
	cpu_last_unix        i64
}

// new_window_manager creates the (still empty) WindowManager right after the
// X connection is up, so config/theme loading has an object to fill in.
pub fn new_window_manager(conn &x11.X11Connection) !&WindowManager {
	draw := DrawingContext.create(conn, conn.root, conn.width, conn.height)!
	return &WindowManager{
		conn:    conn
		draw:    draw
		orig_tz: os.getenv('TZ')
	}
}

// ------------------------------------------------------------------ build

const fallback_titles = ['1', '2', '3', '4', '5']

// make_layout builds the layout of monitor `i` from the current config and theme.
fn (wm &WindowManager) make_layout(i int) Layout {
	sec := wm.window_themes[pick_section(wm.window_themes, i)]
	return Layout(TilingLayout{
		master_ratio:     wm.master_ratio
		gap_width:        sec.window_gap
		border_width:     sec.border_width
		insets:           if sec.has_insets { sec.insets } else { Insets{} }
		collapsed_height: sec.rolled_height()
	})
}

// Placement says where an adopted window goes (restart): -1 = "wherever the
// active workspace is", like a brand-new window.
struct Placement {
	mon       int = -1
	ws        int = -1
	idx       int = -1
	collapsed bool
}

// build is step 5 of initialisation: create monitors (from Xinerama), their
// layouts, workspaces and toolbars, grab keys, and adopt existing windows.
pub fn (mut wm WindowManager) build() ! {
	if wm.window_themes.len == 0 {
		return error('theme not loaded')
	}
	geos := wm.conn.query_monitors()
	log.info('found ${geos.len} monitor(s)')
	if wm.monitor_configs.len < geos.len {
		log.info('config.toml defines ${wm.monitor_configs.len} [[monitors]] but ${geos.len} are connected: extra monitors get workspaces ${fallback_titles}')
	}
	// layouts first (one per monitor) so pointers into the array stay valid
	wm.layouts = []Layout{}
	for i in 0 .. geos.len {
		wm.layouts << wm.make_layout(i)
	}
	wm.monitors = []Monitor{}
	for i, g in geos {
		geo := ScreenRect{g.x, g.y, g.width, g.height}
		wm.monitors << new_monitor(geo, []ThemeSection{}, []u32{}, wm.monitor_titles(i),
			unsafe { &wm.layouts[i] })
		wm.sync_toolbars(MonitorId(i))
		heights := wm.monitors[i].toolbars.map(wm.toolbar_themes[it.theme_index].height)
		log.info('monitor ${i}: ${geo.width}x${geo.height}+${geo.x}+${geo.y}, ${wm.monitors[i].workspaces.len} workspaces, ${wm.monitors[i].toolbars.len} toolbar(s), ${heights}px')
	}
	wm.bind_keys()
	desk := wm.theme_vars['desktop_color'] or { '#1b1f2a' }
	if c := parse_color(desk) {
		wm.conn.set_root_background(wm.draw.to_pixel(c))
	}
	wm.draw_desktop_background()
	wm.conn.init_cursor()
	px, py := wm.conn.pointer_position()
	wm.active_monitor = wm.get_monitor_at(px, py) or { 0 }
	wm.conn.publish_supported()
	wm.adopt_existing_windows()
	if wm.conn.xi_opcode == 0 {
		log.warn('no XInput 2: focus follows the mouse only when it crosses into a window')
	}
	wm.settle_pointer()
	log.info('toolbar clock reads ${wm.clock()} (timezone "${os.getenv('TZ')}")')
	wm.draw_all_toolbars(true)
}

// monitor_titles is monitor i's workspace title list: the config's, or the
// fallback when more monitors are connected than the config has [[monitors]].
fn (wm &WindowManager) monitor_titles(i int) []string {
	if i < wm.monitor_configs.len {
		return wm.monitor_configs[i].workspaces
	}
	return fallback_titles
}

// sync_toolbars matches a monitor's bars to the current theme: picks its
// toolbar sections, lays them out in rows, and creates, moves or destroys the
// bar windows. Both build() and a reload go through here.
fn (mut wm WindowManager) sync_toolbars(mon_id MonitorId) {
	mut mon := &wm.monitors[mon_id]
	titles := wm.monitor_titles(mon_id)
	indices := pick_toolbar_sections(wm.toolbar_themes, mon_id)
	sections := indices.map(wm.toolbar_themes[it])
	mut widths := []u32{cap: sections.len}
	for sec in sections {
		widths << wm.toolbar_wanted_width_for(sec, titles)
	}
	rects, reserved := layout_toolbars(mon.geometry, sections, widths)
	for bar, tidx in indices {
		if bar >= mon.toolbars.len {
			mon.toolbars << Toolbar{}
		}
		mut tb := &mon.toolbars[bar]
		tb.theme_index = tidx
		tb.rect = rects[bar]
		tb.hover = -1
		tb.pressed = -1
		tb.buttons = []ScreenRect{}
		tb.buttons_desc = ''
		tb.last_drawn = ''
		if tb.win == 0 {
			tb.win = wm.conn.create_bar(tb.rect.x, tb.rect.y, tb.rect.width, tb.rect.height)
			wm.conn.map_window(tb.win)
		} else {
			wm.conn.move_resize(tb.win, tb.rect.x, tb.rect.y, tb.rect.width, tb.rect.height)
		}
		log.debug('${toolbar_label(mon_id, bar)} rect: ${tb.rect.x}:${tb.rect.y}:${tb.rect.width}:${tb.rect.height}')
	}
	for bar in indices.len .. mon.toolbars.len {
		wm.conn.destroy_window(mon.toolbars[bar].win)
	}
	if mon.toolbars.len > indices.len {
		mon.toolbars = mon.toolbars[..indices.len].clone()
	}
	mon.work_area = work_area_below_toolbar(mon.geometry, reserved)
}

// toolbar_label names one bar of a monitor for log lines.
fn toolbar_label(mon_id MonitorId, bar_id int) string {
	if bar_id == 0 {
		return 'monitor ${mon_id} toolbar'
	}
	return 'monitor ${mon_id} toolbar ${bar_id}'
}

// draw_desktop_background paints the theme's `background` image on the root
// window: tiled (default), `background_scale = "stretch"` to fill the whole
// X screen (what E16 does with its desktop images), or "none" for the original
// size at the top-left, or "cover" (keep the aspect ratio, fill the screen,
// crop the overflow). Stretch and cover resample nearest-neighbour (pixel art
// stays crisp) unless `background_filter = "linear"` asks for bilinear.
// The desktop_color stays as the fallback.
fn (mut wm WindowManager) draw_desktop_background() {
	if wm.theme_background == '' {
		return
	}
	mut img := wm.draw.load_image(wm.theme_background) or { return }
	w, h := wm.conn.width, wm.conn.height
	buf := wm.draw.new_buffer(w, h)
	mut mode := ScaleMode.parse(wm.theme_background_scale) or { ScaleMode.tile }
	mut area := ScreenRect{0, 0, w, h}
	if wm.theme_background_scale == 'cover' {
		area = cover_rect(int(w), int(h), img.width, img.height)
		mode = .stretch
	}
	if wm.theme_background_filter == 'linear' && mode == .stretch {
		// smooth artwork: resample once with bilinear filtering, then paint 1:1
		pixels := scale_bilinear(img, int(area.width), int(area.height))
		img = LoadedImage{
			width:  int(area.width)
			height: int(area.height)
			data:   pixels.data
		}
		mode = .none
	}
	wm.draw.draw_image(buf, ScreenRect{0, 0, w, h}, area, img, mode, [
		0,
		0,
		0,
		0,
	]!)
	wm.conn.set_root_background_pixmap(buf)
	wm.draw.free_buffer(buf)
}

// bind_keys resolves keybindings to keycodes and grabs them on the root.
fn (mut wm WindowManager) bind_keys() {
	wm.bound_keys = []BoundKey{}
	wm.conn.ungrab_all_keys()
	for kb in with_default_bindings(wm.keybindings, wm.mod_mask) {
		code := wm.conn.keysym_to_keycode(kb.key)
		if code == 0 {
			log.error('keybinding "${kb.source}": unknown key "${kb.key}", ignored')
			continue
		}
		wm.bound_keys << BoundKey{code, kb.mods, kb.action}
		wm.conn.grab_key(code, kb.mods)
	}
	log.info('grabbed ${wm.bound_keys.len} keybindings')
}

// ------------------------------------------------------------------ lookup

fn (wm &WindowManager) find_window(c x11.Client) ?&Window {
	for w in wm.windows {
		if w.id == c {
			return w
		}
	}
	return none
}

// find_by_any matches either the client id or the frame id.
fn (wm &WindowManager) find_by_any(c x11.Client) ?&Window {
	for w in wm.windows {
		if w.id == c || w.frame == c {
			return w
		}
	}
	return none
}

// monitor_of returns the monitor a window lives on.
fn (wm &WindowManager) monitor_of(c x11.Client) ?MonitorId {
	for i, m in wm.monitors {
		if m.has_window(c) {
			return MonitorId(i)
		}
	}
	return none
}

fn (wm &WindowManager) window_theme(m MonitorId) &ThemeSection {
	return unsafe { &wm.window_themes[pick_section(wm.window_themes, m)] }
}

// get_monitor_work_area returns the usable area of a monitor (below its toolbars).
pub fn (wm &WindowManager) get_monitor_work_area(monitor_id MonitorId) ScreenRect {
	return wm.monitors[monitor_id].work_area
}

// get_monitor_at determines which physical monitor contains the coordinates.
pub fn (wm &WindowManager) get_monitor_at(x int, y int) ?MonitorId {
	for i, m in wm.monitors {
		if m.geometry.contains(x, y) {
			return MonitorId(i)
		}
	}
	return none
}

// set_monitor_as_active makes a monitor the target of keybindings.
pub fn (mut wm WindowManager) set_monitor_as_active(monitor_id MonitorId) {
	if monitor_id == wm.active_monitor || monitor_id < 0 || monitor_id >= wm.monitors.len {
		return
	}
	old := wm.active_monitor
	wm.active_monitor = monitor_id
	// the keyboard focus follows the active monitor's remembered window
	wm.focus_window(wm.monitors[monitor_id].workspaces[wm.monitors[monitor_id].active].focused)
	wm.draw_toolbar(old, true)
	wm.draw_toolbar(monitor_id, true)
}

// ------------------------------------------------------------ window events

// on_window_open starts managing a new window. `rect` comes from X11's
// XWindowAttributes, so we know the window's initial position and size.
pub fn (mut wm WindowManager) on_window_open(c x11.Client, rect ScreenRect) {
	wm.on_window_open_ex(c, rect, 0, Placement{})
}

fn (mut wm WindowManager) on_window_open_ex(c x11.Client, rect ScreenRect, ignore_unmaps int, place Placement) {
	if wm.find_window(c) != none || wm.monitors.len == 0 {
		return
	}
	adopted := place.mon >= 0
	mon_id := if adopted && place.mon < wm.monitors.len { place.mon } else { wm.active_monitor }
	ws_idx := if adopted && place.ws >= 0 {
		clamp_i(place.ws, 0, wm.monitors[mon_id].workspaces.len - 1)
	} else {
		wm.monitors[mon_id].active
	}
	mut win := &Window{
		id:            c
		title:         wm.conn.get_title(c)
		ignore_unmaps: ignore_unmaps
	}
	if wm.conn.is_transient(c) {
		win.set_floating(true) // dialogs float where they asked to be
	}
	ins := wm.window_theme(mon_id).frame_insets()
	mut initial := rect
	if win.is_floating() {
		// keep the requested size; centre it on the monitor if it asked for 0,0
		wa := wm.monitors[mon_id].work_area
		if rect.x == 0 && rect.y == 0 {
			cx, cy := wa.center()
			initial =
				ScreenRect{cx - int(rect.width) / 2, cy - int(rect.height) / 2, rect.width, rect.height}
		}
	}
	// frame wraps the client and draws the theme around it
	fr := wm.frame_rect(initial, ins)
	win.frame = wm.conn.create_frame(fr.x, fr.y, fr.width, fr.height)
	wm.conn.select_input(c, x11.property_change_mask | x11.enter_window_mask)
	wm.conn.add_to_save_set(c)
	wm.conn.set_border_width(c, 0)
	wm.conn.reparent(c, win.frame, int(ins.left), int(ins.top))
	wm.conn.move_resize(c, int(ins.left), int(ins.top), initial.width, initial.height)
	mut mon := &wm.monitors[mon_id]
	on_active := ws_idx == mon.active
	prev_focus := mon.workspaces[ws_idx].focused
	win.set_visible(on_active)
	if place.collapsed && !win.is_floating() {
		wm.collapse_seq++
		win.collapsed_at = wm.collapse_seq
		win.set_collapsed(true)
	}
	wm.windows << win
	wm.restack(win)

	if place.idx >= 0 {
		mon.workspaces[ws_idx].add_at(win, initial, place.idx)
	} else {
		mon.workspaces[ws_idx].add(win, initial)
	}
	if on_active {
		wm.apply_layout(mon_id)
		// make sure floating windows (not touched by the layout) are placed too
		wm.place_window(win, wm.spec_rect(mon_id, c))
	}
	wm.conn.map_window(c)
	if on_active {
		wm.conn.map_window(win.frame)
	}
	log.info('managing window 0x${c:x} "${win.title}" on monitor ${mon_id} workspace "${mon.workspaces[ws_idx].title}"')
	wm.publish_desktop(c)
	if wm.conn.has_atom_in(c, wm.conn.atom_net_wm_state, wm.conn.atom_net_wm_state_fs) {
		wm.set_fullscreen(c, true) // it asked for (or kept, across a restart) fullscreen
	}
	if on_active && !adopted {
		// a tiled window opening behind a fullscreen one leaves the focus where it was
		wm.focus_window(if wm.is_covered(win) { prev_focus } else { c })
	}
	wm.draw_toolbar(mon_id, true)
}

// Found is a window adopt_existing_windows is about to manage.
struct Found {
	c      x11.Client
	rect   ScreenRect
	unmaps int
	place  Placement
}

// adopt_existing_windows takes over the windows that are already on the
// display: viewable ones, and unmapped ones that carry a saved placement (a
// previous glo55 hid them on another workspace before it re-exec'd). The saved
// _GLO55_WORKSPACE = [monitor, workspace, slot, rolled-up] puts every window
// back where it was; windows without it go to the active workspace.
fn (mut wm WindowManager) adopt_existing_windows() {
	mut found := []Found{}
	for w in wm.conn.existing_windows() {
		attrs := wm.conn.get_attributes(w) or { continue }
		if attrs.override_redirect {
			continue
		}
		saved := wm.conn.get_longs(w, wm.conn.atom_glo55_workspace) or { []i64{} }
		if !attrs.viewable && saved.len < 4 {
			continue
		}
		wm.conn.delete_property(w, wm.conn.atom_glo55_workspace)
		mut place := Placement{}
		if saved.len >= 4 {
			place = Placement{
				mon:       int(saved[0])
				ws:        int(saved[1])
				idx:       int(saved[2])
				collapsed: saved[3] != 0
			}
		}
		found << Found{
			c:      w
			rect:   ScreenRect{attrs.x, attrs.y, attrs.width, attrs.height}
			unmaps: if attrs.viewable { 1 } else { 0 }
			place:  place
		}
	}
	// ascending slot order, so each add_at lands on its old slot
	found.sort_with_compare(fn (a &Found, b &Found) int {
		return a.place.idx - b.place.idx
	})
	for f in found {
		wm.on_window_open_ex(f.c, f.rect, f.unmaps, f.place)
	}
	// a restart leaves the active monitor/workspaces and focus in a root property
	if sess := wm.conn.get_longs(wm.conn.root, wm.conn.atom_glo55_session) {
		wm.conn.delete_property(wm.conn.root, wm.conn.atom_glo55_session)
		if sess.len >= 2 {
			if int(sess[0]) >= 0 && int(sess[0]) < wm.monitors.len {
				wm.active_monitor = int(sess[0])
			}
			for i in 0 .. wm.monitors.len {
				if i + 2 < sess.len && int(sess[i + 2]) >= 0
					&& int(sess[i + 2]) < wm.monitors[i].workspaces.len
					&& int(sess[i + 2]) != wm.monitors[i].active {
					wm.switch_workspace_ex(i, int(sess[i + 2]), false)
				}
			}
			wm.focused_client = 0
			mut want := x11.Client(sess[1])
			if wm.find_window(want) == none {
				want = wm.monitors[wm.active_monitor].workspaces[wm.monitors[wm.active_monitor].active].focused
			}
			wm.focus_window(want)
		}
	} else if found.len > 0 {
		wm.focused_client = 0
		mon := wm.monitors[wm.active_monitor]
		wm.focus_window(mon.workspaces[mon.active].focused)
	}
}

// publish_desktop writes _NET_WM_DESKTOP (the workspace index on its monitor).
fn (wm &WindowManager) publish_desktop(c x11.Client) {
	for m in wm.monitors {
		for i, ws in m.workspaces {
			if ws.has(c) {
				wm.conn.set_cardinals(c, wm.conn.atom_net_wm_desktop, [i64(i)])
				return
			}
		}
	}
}

// on_window_close stops managing a window that was destroyed or withdrawn.
// `destroyed` is true when the client no longer exists.
pub fn (mut wm WindowManager) on_window_close(c x11.Client, destroyed bool) {
	win := wm.find_window(c) or { return }
	mon_id := wm.monitor_of(c) or { MonitorId(-1) }
	if !destroyed {
		// give the client back to the root so it survives our frame
		rx, ry := wm.frame_origin(win)
		wm.conn.reparent(c, wm.conn.root, rx, ry)
	}
	if wm.frame_hover_win == c {
		wm.frame_hover_win = 0
		wm.frame_hover_action = ''
	}
	if wm.frame_pressed_win == c {
		wm.frame_pressed_win = 0
		wm.frame_pressed_action = ''
	}
	wm.conn.destroy_window(win.frame)
	wm.shaped_frames.delete(win.frame)
	was_focused := wm.focused_client == c
	for mut m in wm.monitors {
		m.remove_window(c)
	}
	wm.windows = wm.windows.filter(it.id != c)
	log.info('window 0x${c:x} gone (${if destroyed { 'destroyed' } else { 'withdrawn' }})')
	if mon_id >= 0 {
		wm.apply_layout(mon_id)
		if was_focused || wm.focused_client == 0 {
			wm.focused_client = 0
			wm.focus_window(wm.monitors[mon_id].workspaces[wm.monitors[mon_id].active].focused)
		}
		wm.draw_toolbar(mon_id, true)
	}
}

fn (mut wm WindowManager) handle_map_request(e x11.MapRequestEvent) {
	if wm.find_window(e.window) != none {
		return
	}
	attrs := wm.conn.get_attributes(e.window) or { return }
	if attrs.override_redirect {
		wm.conn.map_window(e.window)
		return
	}
	wm.on_window_open(e.window, ScreenRect{attrs.x, attrs.y, attrs.width, attrs.height})
}

// handle_configure_request: tiled windows get their layout position back
// (we tell them so, as ICCCM requires); floating windows may move/resize;
// windows we don't manage are passed through.
fn (mut wm WindowManager) handle_configure_request(e x11.ConfigureRequestEvent) {
	mut win := wm.find_window(e.window) or {
		wm.conn.configure_passthrough(e)
		return
	}
	mon_id := wm.monitor_of(e.window) or { 0 }
	mut rect := wm.spec_rect(mon_id, e.window)
	if win.is_floating() && !win.is_fullscreen() {
		x := if e.value_mask & u64(x11.cw_x) != 0 { e.x } else { rect.x }
		y := if e.value_mask & u64(x11.cw_y) != 0 { e.y } else { rect.y }
		w := if e.value_mask & u64(x11.cw_width) != 0 { e.width } else { rect.width }
		h := if e.value_mask & u64(x11.cw_height) != 0 { e.height } else { rect.height }
		rect = ScreenRect{x, y, w, h}
		wm.set_spec_rect(mon_id, e.window, rect)
		wm.place_window(win, rect)
		wm.draw_frame(win)
		wm.settle_pointer()
	}
	wm.conn.send_configure_notify(e.window, rect.x, rect.y, rect.width, rect.height, 0)
}

fn (mut wm WindowManager) handle_unmap(e x11.UnmapNotifyEvent) {
	mut win := wm.find_window(e.window) or { return } // frames etc: ignore
	if win.ignore_unmaps > 0 {
		win.ignore_unmaps--
		return
	}
	wm.on_window_close(e.window, false)
}

fn (mut wm WindowManager) handle_property(e x11.PropertyNotifyEvent) {
	if e.atom != wm.conn.atom_net_wm_name && e.atom != x11.xa_wm_name {
		return
	}
	mut win := wm.find_window(e.window) or { return }
	title := wm.conn.get_title(e.window)
	if title == win.title {
		return
	}
	win.title = title
	log.debug('window 0x${e.window:x} retitled "${title}"')
	wm.draw_frame(win)
	if mon := wm.monitor_of(e.window) {
		wm.draw_toolbar(mon, false)
	}
}

// --------------------------------------------------------- mouse / hover

// on_window_hover: focus follows mouse movement (no configuration). It never
// restacks: a dialog stays above the window the pointer moves on to.
pub fn (mut wm WindowManager) on_window_hover(c x11.Client) {
	win := wm.find_by_any(c) or { return }
	if !win.is_visible() || win.id == wm.focused_client || wm.is_covered(win) {
		return
	}
	wm.focus_window(win.id)
}

// on_pointer_moved: the user moved the mouse after the windows changed under
// it (settle_pointer). Focus goes to the window the pointer is in, even when
// that window keeps its own motion events, without leaving it first. One
// movement is enough: from then on crossing events keep focus in step.
fn (mut wm WindowManager) on_pointer_moved() {
	under, button_held := wm.conn.pointer_window()
	if button_held {
		// a drag: look again at the next movement
		return
	}
	wm.conn.watch_pointer(false)
	wm.on_window_hover(under)
}

// settle_pointer runs after the WM moved, opened or closed windows: the enter
// events that caused are dropped (the pointer did not move, so a window that
// slid under it must not take the focus), and the next real mouse movement
// brings focus to the pointer (on_pointer_moved).
fn (mut wm WindowManager) settle_pointer() {
	wm.conn.drop_enter_events()
	wm.conn.watch_pointer(true)
}

// on_motion_notify tracks the active monitor from the pointer position.
pub fn (mut wm WindowManager) on_motion_notify(x_root int, y_root int) {
	if m := wm.get_monitor_at(x_root, y_root) {
		wm.set_monitor_as_active(m)
	}
}

// frame_action_at returns the `action` of the frame element under (x, y)
// (frame-relative), or '' if there is none. Later elements are drawn on top,
// so they win. Image buttons are hit only where their pixels are opaque, so a
// slanted plate does not steal clicks in the wallpaper triangle beside it.
fn (mut wm WindowManager) frame_action_at(win &Window, x int, y int) string {
	mon_id := wm.monitor_of(win.id) or { return '' }
	sec := wm.window_theme(mon_id)
	bounds := wm.frame_bounds(win, mon_id)
	base := wm.active_states_for(win.id)
	runtime := {
		'title':     win.title
		'workspace': wm.monitors[mon_id].active_title()
		'time':      wm.clock()
		'date':      wm.date()
	}
	vars := sec.resolve_vars(wm.theme_vars, base, runtime)
	mut i := sec.elements.len
	for i > 0 {
		i--
		ele := sec.elements[i]
		st := wm.element_states(win, ele, base)
		if ele.action == '' || !ele.active_in(st) {
			continue
		}
		rect := ele.area.resolve(bounds)
		if !rect.contains(x, y) {
			continue
		}
		if ele.kind in [.image, .pattern] {
			if img := wm.draw.load_image(substitute(ele.path, vars)) {
				if !image_covers(rect, img, ele.scale, ele.slice, x, y) {
					continue
				}
			}
		}
		return ele.action
	}
	return ''
}

// image_covers is whether (x, y) lands on an opaque pixel of img as drawn
// into rect (the same rule the shape mask uses).
fn image_covers(rect ScreenRect, img LoadedImage, mode ScaleMode, slice [4]int, x int, y int) bool {
	sx, sy := scale_source(x, y, rect, img.width, img.height, mode, slice) or { return false }
	return unsafe { img.data[(sy * img.width + sx) * 4 + 3] } >= u8(shape_alpha_threshold)
}

// element_states is the window's state list plus hover/pressed when this
// element's action is the one under the pointer.
fn (wm &WindowManager) element_states(win &Window, ele &Element, base []string) []string {
	mut st := base.clone()
	if ele.action != '' && win.id == wm.frame_hover_win && ele.action == wm.frame_hover_action {
		st << 'hover'
	}
	if ele.action != '' && win.id == wm.frame_pressed_win && ele.action == wm.frame_pressed_action {
		st << 'pressed'
		st << 'clicked'
	}
	return st
}

// frame_screen_rect is the frame's rectangle in root coordinates.
fn (wm &WindowManager) frame_screen_rect(win &Window) ScreenRect {
	mon_id := wm.monitor_of(win.id) or { return ScreenRect{} }
	rect := wm.spec_rect(mon_id, win.id)
	if win.is_collapsed() {
		return rect
	}
	return wm.frame_rect(rect, wm.insets_of(win, mon_id))
}

// on_button_press: a left click on a frame element that has an `action`
// (close, collapse, fullscreen) arms it; the action runs on release over the
// same button (so hover/pressed art can show). Any click also activates the
// monitor it happened on.
pub fn (mut wm WindowManager) on_button_press(e x11.ButtonPressEvent) {
	if m := wm.get_monitor_at(e.x_root, e.y_root) {
		wm.set_monitor_as_active(m)
	}
	if e.button != 1 {
		return
	}
	if loc := wm.toolbar_monitor(e.window) {
		wm.on_toolbar_press(loc, e.x, e.y)
		return
	}
	win := wm.find_by_any(e.window) or { return }
	if win.frame != e.window || !win.is_visible() {
		return
	}
	if win.is_floating() {
		wm.restack(win) // clicking a dialog's frame brings it to the front
	}
	act := wm.frame_action_at(win, e.x, e.y)
	if act == '' {
		return
	}
	wm.focus_window(win.id)
	wm.set_frame_pressed(win.id, act)
}

// run_frame_action is close / collapse / fullscreen on a frame button.
fn (mut wm WindowManager) run_frame_action(win_id x11.Client, act string) {
	match act {
		'close' { wm.conn.close_window(win_id) }
		'collapse' { wm.toggle_collapse(win_id) }
		'fullscreen' { wm.toggle_fullscreen(win_id) }
		else { log.debug('frame action "${act}" is not implemented') }
	}
}

pub fn (mut wm WindowManager) on_screen_resize() {
	// monitors are read once at startup: a changed screen layout needs a restart
	log.info('screen layout changed: restart glo55 to pick up the new monitors')
}

// -------------------------------------------------------------------- keys

pub fn (mut wm WindowManager) on_key_press(e x11.KeyPressEvent) {
	mods := x11.clean_mods(e.state)
	for bk in wm.bound_keys {
		if bk.keycode == e.keycode && bk.mods == mods {
			wm.run_action(bk.action)
			return
		}
	}
}

pub fn (mut wm WindowManager) run_action(a Action) {
	if wm.monitors.len == 0 {
		return
	}
	mon_id := wm.active_monitor
	match a.kind {
		.workspace {
			wm.switch_workspace(mon_id, a.n)
		}
		.warp {
			wm.warp_focused(mon_id, a.n)
		}
		.focus {
			ws := wm.monitors[mon_id].workspaces[wm.monitors[mon_id].active]
			if wm.focused_is_fullscreen() {
				return
			}
			if target := ws.focus_direction(a.dir) {
				// a dialog over a fullscreen window: the tiles are out of reach
				if wm.is_covered(wm.find_window(target) or { return }) {
					return
				}
				wm.focus_window(target)
				wm.warp_pointer_to_focus(mon_id)
			}
		}
		.move {
			mut mon := &wm.monitors[mon_id]
			if wm.focused_is_fullscreen() {
				return
			}
			if mon.workspaces[mon.active].move_direction(a.dir) {
				wm.apply_layout(mon_id)
				wm.warp_pointer_to_focus(mon_id)
			}
		}
		.exec {
			wm.spawn(a.cmd)
		}
		.close {
			if wm.focused_client != 0 {
				wm.conn.close_window(wm.focused_client)
			}
		}
		.collapse {
			wm.toggle_collapse(wm.focused_client)
		}
		.restore {
			wm.restore_last(mon_id)
		}
		.quit {
			log.info('quit requested')
			wm.running = false
		}
		.workspace_next {
			wm.switch_workspace(mon_id, wm.monitors[mon_id].next_workspace())
		}
		.workspace_prev {
			wm.switch_workspace(mon_id, wm.monitors[mon_id].prev_workspace())
		}
		.reload {
			wm.reload()
		}
		.restart {
			wm.restart()
		}
		.fullscreen {
			wm.toggle_fullscreen(wm.focused_client)
		}
	}
}

// spawn runs a shell command in the background. If the command is `kitty`
// and kitty isn't installed we fall back to xterm (and say so), so the
// "open a terminal" binding still does something on a minimal system.
fn (mut wm WindowManager) spawn(cmd string) {
	mut command := cmd
	prog := cmd.all_before(' ')
	if !on_path(prog) {
		if prog == 'kitty' && on_path('xterm') {
			log.info('kitty is not on PATH: falling back to xterm')
			command = 'xterm'
		} else {
			log.error('cannot run "${cmd}": ${prog} not found on PATH')
			return
		}
	}
	log.info('exec: ${command}')
	// the shell backgrounds the program and exits at once, so no zombies
	// os.system runs this through /bin/sh (portable across V versions)
	os.system('${command} >/dev/null 2>&1 &')
}

// ----------------------------------------------------- workspace operations

// switch_workspace shows workspace `idx` on a monitor (keyboard switching:
// the pointer follows to the workspace's focused window).
pub fn (mut wm WindowManager) switch_workspace(mon_id MonitorId, idx int) {
	wm.switch_workspace_ex(mon_id, idx, true)
}

// switch_workspace_ex is switch_workspace; `warp` says whether the pointer
// jumps to the focused window afterwards (not wanted for a toolbar click: the
// pointer stays on the button that was clicked).
pub fn (mut wm WindowManager) switch_workspace_ex(mon_id MonitorId, idx int, warp bool) {
	mut mon := &wm.monitors[mon_id]
	sw := mon.switch_to(idx) or {
		log.error('monitor ${mon_id} has no workspace ${idx + 1}')
		return
	}
	for id in sw.hide {
		if mut w := wm.find_window(id) {
			w.set_visible(false)
			wm.conn.unmap_window(w.frame)
		}
	}
	// refresh the layout of the new workspace and place every window of it
	wm.apply_layout(mon_id)
	for spec in mon.workspaces[mon.active].windows {
		wm.place_window(spec.info, spec.rect)
	}
	for id in sw.show {
		if mut w := wm.find_window(id) {
			w.set_visible(true)
			wm.conn.map_window(w.frame)
			wm.draw_frame(w)
		}
	}
	log.info('monitor ${mon_id}: workspace "${mon.active_title()}"')
	mut focus_id := mon.workspaces[mon.active].focused
	if focus_id == 0 {
		focus_id = mon.workspaces[mon.active].fallback_focus(0)
	}
	wm.focused_client = 0
	wm.focus_window(focus_id)
	if warp {
		wm.warp_pointer_to_focus(mon_id)
	}
	wm.draw_toolbar(mon_id, true)
}

// warp_focused moves the focused window to workspace `idx` of its monitor.
fn (mut wm WindowManager) warp_focused(mon_id MonitorId, idx int) {
	c := wm.focused_client
	if c == 0 {
		return
	}
	mut mon := &wm.monitors[mon_id]
	if !mon.workspaces[mon.active].has(c) {
		return
	}
	sw := mon.warp(c, idx) or { return }
	for id in sw.hide {
		if mut w := wm.find_window(id) {
			w.set_visible(false)
			wm.conn.unmap_window(w.frame)
		}
	}
	log.info('window 0x${c:x} warped to workspace "${mon.workspaces[idx].title}"')
	wm.publish_desktop(c)
	wm.apply_layout(mon_id)
	wm.focused_client = 0
	wm.focus_window(mon.workspaces[mon.active].focused)
	wm.warp_pointer_to_focus(mon_id)
	wm.draw_toolbar(mon_id, true)
}

// toggle_collapse rolls a window up, or unrolls it if it already is (the
// minimise button of a rolled bar and the collapse key both do this).
fn (mut wm WindowManager) toggle_collapse(c x11.Client) {
	win := wm.find_window(c) or { return }
	mon_id := wm.monitor_of(c) or { return }
	if win.is_collapsed() {
		wm.restore_window(mon_id, c)
	} else {
		wm.collapse_window(mon_id, c)
	}
}

// collapse_window rolls a window up: its frame shrinks to a title bar that
// joins the bars at the bottom of the stack, the client is moved out of view
// (it stays mapped and keeps its size), and focus goes to the nearest normal
// window (or stays on the bar if nothing else is left). The window keeps its
// slot in the workspace order, so restoring puts it back where it was.
fn (mut wm WindowManager) collapse_window(mon_id MonitorId, c x11.Client) {
	mut mon := &wm.monitors[mon_id]
	mut win := wm.find_window(c) or { return }
	if !mon.workspaces[mon.active].has(c) || win.is_collapsed() {
		return
	}
	if win.is_floating() {
		log.info('window 0x${c:x} is floating (a dialog): not rolled up')
		return
	}
	wm.collapse_seq++
	win.collapsed_at = wm.collapse_seq
	win.set_collapsed(true)
	idx := mon.workspaces[mon.active].index_of(c)
	log.info('rolled up window 0x${c:x} (slot ${idx})')
	wm.apply_layout(mon_id)
	// its rect changed meaning (client -> bar frame): always place and redraw
	wm.place_window(win, wm.spec_rect(mon_id, c))
	wm.draw_frame(win)
	if wm.focused_client == c {
		mon.workspaces[mon.active].focus(mon.workspaces[mon.active].fallback_focus(idx))
		wm.focused_client = 0
		wm.focus_window(mon.workspaces[mon.active].focused)
		wm.warp_pointer_to_focus(mon_id)
	}
	wm.draw_toolbar(mon_id, true)
}

// restore_window unrolls a window back into the layout at its old slot.
fn (mut wm WindowManager) restore_window(mon_id MonitorId, c x11.Client) {
	mut win := wm.find_window(c) or { return }
	if !win.is_collapsed() {
		return
	}
	win.set_collapsed(false)
	wm.apply_layout(mon_id)
	wm.place_window(win, wm.spec_rect(mon_id, c))
	wm.draw_frame(win)
	log.info('unrolled window 0x${c:x}')
	wm.focused_client = 0
	wm.focus_window(c)
	wm.warp_pointer_to_focus(mon_id)
	wm.draw_toolbar(mon_id, true)
}

// restore_last unrolls the focused window if it is rolled up, otherwise the
// most recently rolled-up window of the active workspace.
fn (mut wm WindowManager) restore_last(mon_id MonitorId) {
	mon := wm.monitors[mon_id]
	ws := mon.workspaces[mon.active]
	if f := wm.find_window(ws.focused) {
		if f.is_collapsed() {
			wm.restore_window(mon_id, f.id)
			return
		}
	}
	c := ws.last_collapsed() or { return }
	wm.restore_window(mon_id, c)
}

// ------------------------------------------------------------- fullscreen

// fullscreen_window returns the fullscreen window on the same monitor and
// workspace as window `c`, if there is one.
fn (wm &WindowManager) fullscreen_window(c x11.Client) ?x11.Client {
	mon_id := wm.monitor_of(c) or { return none }
	mon := wm.monitors[mon_id]
	for spec in mon.workspaces[mon.active].windows {
		if spec.info.is_fullscreen() && spec.info.is_visible() {
			return spec.info.id
		}
	}
	return none
}

fn (wm &WindowManager) focused_is_fullscreen() bool {
	w := wm.find_window(wm.focused_client) or { return false }
	return w.is_fullscreen()
}

// toggle_fullscreen is mod+f and the titlebar's fullscreen button.
pub fn (mut wm WindowManager) toggle_fullscreen(c x11.Client) {
	win := wm.find_window(c) or { return }
	wm.set_fullscreen(c, !win.is_fullscreen())
}

// set_fullscreen makes a window cover its whole monitor (toolbar included,
// no frame) or puts it back. A fullscreen window is laid out like a floating
// one, so the tiled windows behind it fill the space it left; on the way back
// it returns to its tiled slot, or to its old floating rectangle. The EWMH
// state _NET_WM_STATE_FULLSCREEN follows (clients see it and can ask for it).
pub fn (mut wm WindowManager) set_fullscreen(c x11.Client, on bool) {
	mut win := wm.find_window(c) or { return }
	mon_id := wm.monitor_of(c) or { return }
	if win.is_fullscreen() == on {
		return
	}
	geometry := wm.monitors[mon_id].geometry
	if on {
		if win.is_collapsed() {
			win.set_collapsed(false) // a rolled-up window is unrolled first
		}
		win.was_floating = win.is_floating()
		win.saved_rect = wm.spec_rect(mon_id, c)
		win.set_fullscreen(true)
		win.set_floating(true)
		wm.set_spec_rect(mon_id, c, geometry)
	} else {
		win.set_fullscreen(false)
		win.set_floating(win.was_floating)
		if win.was_floating {
			wm.set_spec_rect(mon_id, c, win.saved_rect)
		}
	}
	wm.conn.set_atoms(c, wm.conn.atom_net_wm_state, if on {
		[wm.conn.atom_net_wm_state_fs]
	} else {
		[]x11.Atom{}
	})
	log.info('window 0x${c:x} ${if on { 'is now fullscreen' } else { 'left fullscreen' }}')
	wm.apply_layout(mon_id)
	wm.place_window(win, wm.spec_rect(mon_id, c))
	wm.draw_frame(win)
	if win.is_visible() {
		wm.restack(win)
		wm.focused_client = 0
		wm.focus_window(c)
		r := wm.spec_rect(mon_id, c)
		wm.conn.send_configure_notify(c, r.x, r.y, r.width, r.height, 0)
	}
	wm.draw_toolbar(mon_id, true)
}

// handle_client_message answers EWMH _NET_WM_STATE requests for fullscreen:
// data[0] is 0 (remove), 1 (add) or 2 (toggle); data[1], data[2] the properties.
fn (mut wm WindowManager) handle_client_message(e x11.ClientMessageEvent) {
	if e.message_type != wm.conn.atom_net_wm_state || e.format != 32 {
		return
	}
	fs := i64(wm.conn.atom_net_wm_state_fs)
	if e.data[1] != fs && e.data[2] != fs {
		return
	}
	win := wm.find_window(e.window) or { return }
	match e.data[0] {
		0 { wm.set_fullscreen(win.id, false) }
		1 { wm.set_fullscreen(win.id, true) }
		2 { wm.toggle_fullscreen(win.id) }
		else {}
	}
}

// ---------------------------------------------------------------- geometry

fn (wm &WindowManager) frame_rect(client_rect ScreenRect, ins Insets) ScreenRect {
	return ScreenRect{client_rect.x - int(ins.left), client_rect.y - int(ins.top), u32(
		int(client_rect.width) + int(ins.left + ins.right)), u32(int(client_rect.height) +
		int(ins.top + ins.bottom))}
}

fn (wm &WindowManager) spec_rect(mon_id MonitorId, c x11.Client) ScreenRect {
	for ws in wm.monitors[mon_id].workspaces {
		i := ws.index_of(c)
		if i >= 0 {
			return ws.windows[i].rect
		}
	}
	return ScreenRect{}
}

fn (mut wm WindowManager) set_spec_rect(mon_id MonitorId, c x11.Client, r ScreenRect) {
	for mut ws in wm.monitors[mon_id].workspaces {
		i := ws.index_of(c)
		if i >= 0 {
			ws.windows[i].rect = r
		}
	}
}

// place_window moves a window's frame and client into place. `rect` is the
// client rect, or for a rolled-up window the frame rect (the bar): then the
// client is parked just below the frame, where the frame clips it away.
fn (mut wm WindowManager) place_window(win &Window, rect ScreenRect) {
	mon_id := wm.monitor_of(win.id) or { return }
	ins := wm.insets_of(win, mon_id)
	if win.is_collapsed() {
		wm.conn.move_resize(win.frame, rect.x, rect.y, rect.width, rect.height)
		wm.conn.move_window(win.id, int(ins.left), int(rect.height))
		return
	}
	fr := wm.frame_rect(rect, ins)
	wm.conn.move_resize(win.frame, fr.x, fr.y, fr.width, fr.height)
	wm.conn.move_resize(win.id, int(ins.left), int(ins.top), rect.width, rect.height)
}

// apply_layout is the heart of the workflow: ask the active workspace's
// layout for updates, tell X to apply them, then let the workspace record them.
fn (mut wm WindowManager) apply_layout(mon_id MonitorId) {
	mut mon := &wm.monitors[mon_id]
	updates := mon.workspaces[mon.active].compute_updates(mon.work_area)
	for u in updates {
		spec := mon.workspaces[mon.active].windows[u.window_index]
		wm.place_window(spec.info, u.target_rect)
	}
	mon.workspaces[mon.active].apply_updates(updates)
	for u in updates {
		w := mon.workspaces[mon.active].windows[u.window_index].info
		if w.is_visible() {
			wm.draw_frame(w)
		}
	}
}

// warp_pointer_to_focus follows a keyboard action: a floating focused window
// comes to the front, and the pointer moves into the focused window, to the
// spot nearest its centre that no dialog covers (it stays put if dialogs hide
// the whole window, so it cannot land on one and hand it the focus).
fn (mut wm WindowManager) warp_pointer_to_focus(mon_id MonitorId) {
	mon := wm.monitors[mon_id]
	ws := mon.workspaces[mon.active]
	i := ws.index_of(ws.focused)
	if i < 0 {
		cx, cy := mon.work_area.center()
		wm.conn.warp_pointer(cx, cy)
		return
	}
	win := ws.windows[i].info
	mut covers := []ScreenRect{}
	if win.is_floating() {
		wm.restack(win)
	} else {
		for spec in ws.windows {
			if spec.info.is_floating() {
				covers << wm.frame_screen_rect(spec.info)
			}
		}
	}
	x, y := ws.windows[i].rect.open_point(covers) or { return }
	wm.conn.warp_pointer(x, y)
}

// ------------------------------------------------------------------- focus

// restack puts a window in its layer: floating windows (dialogs, fullscreen)
// on top, tiled ones directly under the lowest floating window, so a dialog is
// never buried by a tiled window, focused or not. Tiled windows don't overlap
// each other or the toolbars, so their order among themselves doesn't matter.
fn (mut wm WindowManager) restack(win &Window) {
	if win.is_floating() {
		wm.conn.raise_window(win.frame)
		return
	}
	for w in wm.conn.existing_windows() { // bottom to top
		if other := wm.find_by_any(w) {
			if other.frame == w && other.is_floating() {
				wm.conn.stack_below(win.frame, w)
				return
			}
		}
	}
}

// is_covered: a tiled window under a fullscreen one on its workspace. It
// can't take the focus (not by pointer, keys, or opening).
fn (wm &WindowManager) is_covered(win &Window) bool {
	if win.is_floating() {
		return false
	}
	wm.fullscreen_window(win.id) or { return false }
	return true
}

// focus_window gives keyboard focus to a window (0 = nobody), remembers it as
// its workspace's focus and repaints the affected borders. It doesn't restack
// (see restack and warp_pointer_to_focus).
pub fn (mut wm WindowManager) focus_window(c x11.Client) {
	old := wm.focused_client
	mut mon_id := wm.active_monitor
	if c != 0 {
		win := wm.find_window(c) or { return }
		if !win.is_visible() {
			return
		}
		mon_id = wm.monitor_of(c) or { return }
		wm.active_monitor = mon_id
		mut mon := &wm.monitors[mon_id]
		mon.workspaces[mon.active].focus(c)
		wm.conn.set_input_focus(c)
	} else {
		wm.conn.set_input_focus(wm.conn.root)
		mut mon := &wm.monitors[mon_id]
		mon.workspaces[mon.active].focus(0)
	}
	wm.focused_client = c
	if old != c {
		wm.redraw_frame(old)
		wm.redraw_frame(c)
		for i in 0 .. wm.monitors.len {
			wm.draw_toolbar(i, false)
		}
	}
}

// ------------------------------------------------------------------ drawing

fn (wm &WindowManager) active_states_for(c x11.Client) []string {
	mut st := []string{}
	if c != 0 && c == wm.focused_client {
		st << 'focused'
	}
	if win := wm.find_window(c) {
		if win.is_collapsed() {
			st << 'collapsed'
		}
	}
	return st
}

// insets_of is how much the frame grows a window's client: the theme's insets,
// or nothing for a fullscreen window.
fn (wm &WindowManager) insets_of(win &Window, mon_id MonitorId) Insets {
	if win.is_fullscreen() {
		return Insets{}
	}
	return wm.window_theme(mon_id).frame_insets()
}

// frame_bounds is the size of a window's frame: its client plus the theme's
// insets, or for a rolled-up window the bar rect itself.
fn (wm &WindowManager) frame_bounds(win &Window, mon_id MonitorId) ScreenRect {
	rect := wm.spec_rect(mon_id, win.id)
	if win.is_collapsed() {
		return ScreenRect{0, 0, rect.width, rect.height}
	}
	ins := wm.insets_of(win, mon_id)
	return ScreenRect{0, 0, u32(int(rect.width) + int(ins.left + ins.right)), u32(
		int(rect.height) + int(ins.top + ins.bottom))}
}

// draw_frame repaints a window's frame (borders/decorations) from the theme.
pub fn (mut wm WindowManager) draw_frame(win &Window) {
	mon_id := wm.monitor_of(win.id) or { return }
	rect := wm.spec_rect(mon_id, win.id)
	sec := wm.window_theme(mon_id)
	ins := wm.insets_of(win, mon_id)
	fb := wm.frame_bounds(win, mon_id)
	fw := fb.width
	fh := fb.height
	if fw == 0 || fh == 0 {
		return
	}
	if win.is_fullscreen() {
		// the client fills the frame: nothing to decorate, and no shape clip
		if wm.shaped_frames[win.frame] {
			wm.conn.clear_shape(win.frame)
			wm.shaped_frames.delete(win.frame)
		}
		return
	}
	states := wm.active_states_for(win.id)
	runtime := {
		'title':     win.title
		'workspace': wm.monitors[mon_id].active_title()
		'time':      wm.clock()
		'date':      wm.date()
	}
	vars := sec.resolve_vars(wm.theme_vars, states, runtime)
	buf := wm.draw.new_buffer(fw, fh)
	bounds := ScreenRect{0, 0, fw, fh}
	for ele in sec.elements {
		if ele.active_in(wm.element_states(win, ele, states)) {
			ele.render(mut wm.draw, buf, bounds, vars)
		}
	}
	// set the shape before copying the picture in: a copy is clipped to the
	// window's current shape, so painting first would leave any area the new
	// shape adds (a focused title's slip, say) unpainted until the next expose.
	if sec.shaped {
		mut mask := new_shape_mask(int(fw), int(fh))
		for ele in sec.elements {
			if ele.active_in(wm.element_states(win, ele, states)) {
				ele.mark_shape(mut wm.draw, bounds, vars, mut mask)
			}
		}
		if !win.is_collapsed() { // a rolled-up window's client is hidden
			mask.mark_rect(ScreenRect{int(ins.left), int(ins.top), rect.width, rect.height}) // the client
		}
		wm.conn.set_shape(win.frame, fw, fh, mask.pack())
		wm.shaped_frames[win.frame] = true
	}
	wm.draw.present(buf, win.frame, fw, fh)
	wm.draw.free_buffer(buf)
}

// redraw_frame repaints a window's frame when it is managed and on screen.
fn (mut wm WindowManager) redraw_frame(c x11.Client) {
	if w := wm.find_window(c) {
		if w.is_visible() {
			wm.draw_frame(w)
		}
	}
}

// focused_title returns the title of the focused window on a monitor.
fn (wm &WindowManager) focused_title(mon_id MonitorId) string {
	mon := wm.monitors[mon_id]
	ws := mon.workspaces[mon.active]
	i := ws.index_of(ws.focused)
	if i >= 0 {
		return ws.windows[i].info.title
	}
	return ''
}

// toolbar_signature is everything a toolbar displays; we only repaint when it
// changes (that includes the hover / pressed button, so pointer motion that
// stays on one button costs nothing).
fn (wm &WindowManager) toolbar_signature(mon_id MonitorId, bar_id int) string {
	mon := wm.monitors[mon_id]
	mut ws := []string{}
	for w in mon.workspaces {
		ws << '${w.title}:${w.windows.len > 0}'
	}
	cpu := if wm.toolbar_uses_cpu(mon_id, bar_id) { '${wm.cpu_percent}' } else { '' }
	tb := mon.toolbars[bar_id]
	return '${mon_id == wm.active_monitor}|${mon.active}|${ws.join(',')}|${wm.focused_title(mon_id)}|${wm.clock()}|${wm.date()}|${cpu}|${tb.hover}|${tb.pressed}'
}

// draw_toolbar paints every toolbar on a monitor.
pub fn (mut wm WindowManager) draw_toolbar(mon_id MonitorId, force bool) {
	for bar in 0 .. wm.monitors[mon_id].toolbars.len {
		wm.draw_one_toolbar(mon_id, bar, force)
	}
}

// draw_one_toolbar skips a repaint when nothing visible changed, unless forced.
fn (mut wm WindowManager) draw_one_toolbar(mon_id MonitorId, bar_id int, force bool) {
	sig := wm.toolbar_signature(mon_id, bar_id)
	if !force && wm.monitors[mon_id].toolbars[bar_id].last_drawn == sig {
		return
	}
	wm.monitors[mon_id].toolbars[bar_id].last_drawn = sig
	log.debug('${toolbar_label(mon_id, bar_id)} repaint')
	wm.place_toolbar(mon_id, bar_id)
	tb := wm.monitors[mon_id].toolbars[bar_id]
	if tb.rect.width == 0 || tb.rect.height == 0 {
		return
	}
	sec := wm.toolbar_themes[tb.theme_index]
	mut states := []string{}
	if mon_id == wm.active_monitor {
		states << 'focused'
	}
	runtime := {
		'title':      wm.focused_title(mon_id)
		'workspace':  wm.monitors[mon_id].active_title()
		'workspaces': wm.monitors[mon_id].workspace_list()
		'time':       wm.clock()
		'date':       wm.date()
		'cpu':        '${wm.cpu_percent}'
	}
	vars := sec.resolve_vars(wm.theme_vars, states, runtime)
	buf := wm.draw.new_buffer(tb.rect.width, tb.rect.height)
	bounds := ScreenRect{0, 0, tb.rect.width, tb.rect.height}
	for ele in sec.elements {
		ele.render(mut wm.draw, buf, bounds, vars)
	}
	if sec.has_workspace_buttons {
		wm.draw_workspace_buttons(mon_id, bar_id, sec.workspace_buttons, buf, bounds, vars)
	} else {
		wm.monitors[mon_id].toolbars[bar_id].buttons = []ScreenRect{}
	}
	wm.draw.present(buf, tb.win, tb.rect.width, tb.rect.height)
	wm.draw.free_buffer(buf)
	wm.conn.flush()
}

// button_states_of is the state list of workspace button `i` on a monitor.
// `layout_only` leaves out hover/pressed, which must never change a button's
// size.
fn (wm &WindowManager) button_states_of(mon_id MonitorId, bar_id int, i int, layout_only bool) []string {
	mon := wm.monitors[mon_id]
	tb := mon.toolbars[bar_id]
	pressed := !layout_only && tb.pressed == i && tb.hover == i
	hover := !layout_only && tb.hover == i
	return button_states(i == mon.active, mon.workspaces[i].windows.len > 0, hover, pressed)
}

// button_width_for measures one workspace button of a template: the width
// of its label text (in the label element's font, with `base` variables
// applied) plus the template's padding, clamped to min_width / max_width.
// 0 when the template has no label element or its font cannot be opened.
fn (mut wm WindowManager) button_width_for(wb &WorkspaceButtons, title string, number int, st []string, base map[string]string) int {
	bv := wb.resolve_vars(base, st, {
		'workspace': title
		'number':    '${number}'
	})
	mut tw := 0
	if lbl := wb.label_element(st) {
		if font := wm.draw.font(font_pattern(substitute(lbl.font, bv), lbl.size)) {
			tw = wm.draw.text_width(font, apply_transform(substitute(lbl.content, bv),
				lbl.transform))
		}
	}
	return wb.button_width(tw)
}

// draw_workspace_buttons lays the monitor's workspaces out as buttons inside
// the theme's region and paints each from the button template. The rects are
// kept in the toolbar for hit testing.
fn (mut wm WindowManager) draw_workspace_buttons(mon_id MonitorId, bar_id int, wb WorkspaceButtons, buf u64, bounds ScreenRect, bar_vars map[string]string) {
	n := wm.monitors[mon_id].workspaces.len
	region := wb.area.resolve(bounds)
	mut widths := []int{cap: n}
	for i in 0 .. n {
		title := wm.monitors[mon_id].workspaces[i].title
		st := wm.button_states_of(mon_id, bar_id, i, true)
		widths << wm.button_width_for(wb, title, i + 1, st, bar_vars)
	}
	rects := layout_buttons(region, widths, wb.spacing, wb.align, wb.button_height)
	desc := rects.map('${it.x}:${it.y}:${it.width}:${it.height}').join(',')
	if desc != wm.monitors[mon_id].toolbars[bar_id].buttons_desc {
		wm.monitors[mon_id].toolbars[bar_id].buttons_desc = desc
		log.debug('${toolbar_label(mon_id, bar_id)} workspace buttons: ${desc}')
	}
	wm.monitors[mon_id].toolbars[bar_id].buttons = rects
	for i, r in rects {
		st := wm.button_states_of(mon_id, bar_id, i, false)
		bv := wb.resolve_vars(bar_vars, st, {
			'workspace': wm.monitors[mon_id].workspaces[i].title
			'number':    '${i + 1}'
		})
		for ele in wb.elements {
			if ele.active_in(st) {
				ele.render_in(mut wm.draw, buf, bounds, r, bv)
			}
		}
	}
}

// ------------------------------------------------------- toolbar pointer

// ToolbarLocation identifies one window in a monitor's toolbar stack.
struct ToolbarLocation {
	monitor MonitorId
	bar     int
}

// toolbar_monitor says which toolbar window `w` is.
fn (wm &WindowManager) toolbar_monitor(w x11.Client) ?ToolbarLocation {
	for i, m in wm.monitors {
		for bar, tb in m.toolbars {
			if tb.win == w {
				return ToolbarLocation{MonitorId(i), bar}
			}
		}
	}
	return none
}

// on_toolbar_pointer follows the pointer over a toolbar (motion and enter
// events): the button under it gets the hover state. Repaints only when the
// hovered button changes.
pub fn (mut wm WindowManager) on_toolbar_pointer(w x11.Client, x int, y int) {
	loc := wm.toolbar_monitor(w) or { return }
	wm.set_toolbar_hover(loc, button_at(wm.monitors[loc.monitor].toolbars[loc.bar].buttons, x, y))
	wm.draw_one_toolbar(loc.monitor, loc.bar, false)
}

fn (mut wm WindowManager) set_toolbar_hover(loc ToolbarLocation, i int) {
	if wm.monitors[loc.monitor].toolbars[loc.bar].hover != i {
		log.debug('${toolbar_label(loc.monitor, loc.bar)} hover: button ${i}')
	}
	wm.monitors[loc.monitor].toolbars[loc.bar].hover = i
}

// on_toolbar_leave clears the hover state when the pointer leaves a toolbar.
pub fn (mut wm WindowManager) on_toolbar_leave(w x11.Client) {
	loc := wm.toolbar_monitor(w) or { return }
	wm.set_toolbar_hover(loc, -1)
	wm.draw_one_toolbar(loc.monitor, loc.bar, false)
}

// on_toolbar_press: the left button went down on a toolbar. A workspace button
// shows `pressed`; nothing happens until the release.
fn (mut wm WindowManager) on_toolbar_press(loc ToolbarLocation, x int, y int) {
	i := button_at(wm.monitors[loc.monitor].toolbars[loc.bar].buttons, x, y)
	wm.set_toolbar_hover(loc, i)
	wm.monitors[loc.monitor].toolbars[loc.bar].pressed = i
	log.debug('${toolbar_label(loc.monitor, loc.bar)} press: button ${i}')
	wm.draw_one_toolbar(loc.monitor, loc.bar, false)
}

// on_frame_pointer updates the hovered title-bar button as the pointer moves
// over a frame (or enters it).
fn (mut wm WindowManager) on_frame_pointer(w x11.Client, x int, y int) {
	win := wm.find_by_any(w) or { return }
	if win.frame != w || !win.is_visible() {
		return
	}
	wm.set_frame_hover(win.id, wm.frame_action_at(win, x, y))
}

// on_frame_leave clears the hover when the pointer leaves a frame (including
// when it moves onto the client, which is a child of the frame).
fn (mut wm WindowManager) on_frame_leave(w x11.Client) {
	win := wm.find_by_any(w) or { return }
	if win.frame == w {
		wm.set_frame_hover(win.id, '')
	}
}

fn (mut wm WindowManager) set_frame_hover(id x11.Client, act string) {
	if act == '' {
		if wm.frame_hover_win == 0 {
			return
		}
		old := wm.frame_hover_win
		wm.frame_hover_win = 0
		wm.frame_hover_action = ''
		wm.redraw_frame(old)
		return
	}
	if wm.frame_hover_win == id && wm.frame_hover_action == act {
		return
	}
	old := wm.frame_hover_win
	wm.frame_hover_win = id
	wm.frame_hover_action = act
	if old != 0 && old != id {
		wm.redraw_frame(old)
	}
	wm.redraw_frame(id)
}

fn (mut wm WindowManager) set_frame_pressed(id x11.Client, act string) {
	wm.frame_pressed_win = id
	wm.frame_pressed_action = act
	wm.set_frame_hover(id, act)
	wm.redraw_frame(id)
}

fn (mut wm WindowManager) clear_frame_pressed() {
	old := wm.frame_pressed_win
	wm.frame_pressed_win = 0
	wm.frame_pressed_action = ''
	if old != 0 {
		wm.redraw_frame(old)
	}
}

// on_button_release: letting go over the same workspace button that was
// pressed switches that monitor to it (letting go elsewhere cancels). A
// title-bar button that was armed on press runs on release over the same button.
pub fn (mut wm WindowManager) on_button_release(e x11.ButtonReleaseEvent) {
	if e.button != 1 {
		wm.clear_frame_pressed()
		return
	}
	if loc := wm.toolbar_monitor(e.window) {
		mon := loc.monitor
		pressed := wm.monitors[mon].toolbars[loc.bar].pressed
		i := button_at(wm.monitors[mon].toolbars[loc.bar].buttons, e.x, e.y)
		wm.monitors[mon].toolbars[loc.bar].pressed = -1
		wm.set_toolbar_hover(loc, i)
		log.debug('${toolbar_label(mon, loc.bar)} release: button ${i} (pressed ${pressed})')
		if pressed >= 0 && i == pressed && i != wm.monitors[mon].active {
			wm.switch_workspace_ex(mon, i, false) // redraws the monitor's toolbars
		}
		wm.draw_one_toolbar(mon, loc.bar, false)
		return
	}
	// a frame button: the release may arrive on a different window if the
	// pointer moved, so we use root coordinates against the armed frame.
	if wm.frame_pressed_win == 0 {
		return
	}
	win := wm.find_window(wm.frame_pressed_win) or {
		wm.clear_frame_pressed()
		return
	}
	fr := wm.frame_screen_rect(win)
	act := wm.frame_action_at(win, e.x_root - fr.x, e.y_root - fr.y)
	armed := wm.frame_pressed_action
	id := win.id
	wm.clear_frame_pressed()
	if act == armed && act != '' {
		wm.run_frame_action(id, act)
	}
}

pub fn (mut wm WindowManager) draw_all_toolbars(force bool) {
	for i in 0 .. wm.monitors.len {
		wm.draw_toolbar(i, force)
	}
}

// ---------------------------------------------------------------- event loop

fn (mut wm WindowManager) handle_event(ev x11.Event) {
	match ev {
		x11.MapRequestEvent {
			wm.handle_map_request(ev)
			wm.settle_pointer()
		}
		x11.ConfigureRequestEvent {
			wm.handle_configure_request(ev)
		}
		x11.DestroyNotifyEvent {
			wm.on_window_close(ev.window, true)
			wm.settle_pointer()
		}
		x11.UnmapNotifyEvent {
			wm.handle_unmap(ev)
			wm.settle_pointer()
		}
		x11.KeyPressEvent {
			wm.on_key_press(ev)
			wm.settle_pointer()
		}
		x11.ButtonPressEvent {
			wm.on_button_press(ev)
		}
		x11.ButtonReleaseEvent {
			wm.on_button_release(ev)
			wm.settle_pointer()
		}
		x11.MotionNotifyEvent {
			wm.on_toolbar_pointer(ev.window, ev.x, ev.y)
			wm.on_frame_pointer(ev.window, ev.x, ev.y)
			wm.on_motion_notify(ev.x_root, ev.y_root)
		}
		x11.LeaveNotifyEvent {
			wm.on_toolbar_leave(ev.window)
			wm.on_frame_leave(ev.window)
		}
		x11.EnterNotifyEvent {
			wm.on_toolbar_pointer(ev.window, ev.x, ev.y)
			wm.on_frame_pointer(ev.window, ev.x, ev.y)
			// ignore crossings caused by grabs and moves between a window's own children
			if ev.mode == 0 && ev.detail != 2 {
				if m := wm.get_monitor_at(ev.x_root, ev.y_root) {
					if wm.find_by_any(ev.window) == none {
						wm.set_monitor_as_active(m) // entered a toolbar
					}
				}
				wm.on_window_hover(ev.window)
			} else if ev.mode == 2 {
				// NotifyUngrab: a menu or drag ended, maybe over another window
				wm.conn.watch_pointer(true)
			}
		}
		x11.PointerMovedEvent {
			wm.on_pointer_moved()
		}
		x11.ExposeEvent {
			if ev.count == 0 {
				wm.handle_expose(ev.window)
			}
		}
		x11.PropertyNotifyEvent {
			wm.handle_property(ev)
		}
		x11.ClientMessageEvent {
			wm.handle_client_message(ev)
			wm.settle_pointer()
		}
		x11.UnknownEvent {}
	}
}

fn (mut wm WindowManager) handle_expose(w x11.Client) {
	if win := wm.find_by_any(w) {
		if win.frame == w {
			wm.draw_frame(win)
		}
		return
	}
	for i, m in wm.monitors {
		for bar, tb in m.toolbars {
			if tb.win == w {
				wm.draw_one_toolbar(i, bar, true)
			}
		}
	}
}

// run is step 8: the single main event loop. It wakes at least once a second
// so toolbar clocks stay current.
pub fn (mut wm WindowManager) run() {
	log.info('entering event loop')
	for wm.running {
		wm.conn.wait_for_events(1000)
		for wm.conn.pending() > 0 && wm.running {
			wm.handle_event(wm.conn.next_event())
		}
		wm.sample_cpu()
		wm.draw_all_toolbars(false)
		wm.conn.flush()
	}
}

// clock formats the current local time for $time. [general] timezone in
// config.toml (or the TZ environment variable) picks the zone; time_format is a
// V time format (default "HH:mm").
fn (wm &WindowManager) clock() string {
	return time.now().custom_format(if wm.time_format == '' { 'HH:mm' } else { wm.time_format })
}

// date is the toolbar's calendar line (e.g. "FRI 20 NOV"): a V time format of
// "ddd DD MMM". Themes typically `transform = "upper"` it.
fn (wm &WindowManager) date() string {
	fmt := if wm.date_format == '' { 'ddd DD MMM' } else { wm.date_format }
	return time.now().custom_format(fmt)
}

// toolbar_uses_cpu is true when this toolbar's theme reads $cpu, so we only
// put the meter in the repaint signature for themes that show it.
fn (wm &WindowManager) toolbar_uses_cpu(mon_id MonitorId, bar_id int) bool {
	sec := wm.toolbar_themes[wm.monitors[mon_id].toolbars[bar_id].theme_index]
	for ele in sec.elements {
		if ele.fill.contains('$cpu') || ele.content.contains('$cpu') {
			return true
		}
	}
	if sec.has_workspace_buttons {
		for ele in sec.workspace_buttons.elements {
			if ele.fill.contains('$cpu') || ele.content.contains('$cpu') {
				return true
			}
		}
	}
	return false
}

// parse_cpu_line reads the "cpu  user nice system idle ..." first line of
// /proc/stat as (total, idle); idle includes iowait. none if malformed.
fn parse_cpu_line(line string) ?(u64, u64) {
	parts := line.split(' ').filter(it != '')
	if parts.len < 5 || parts[0] != 'cpu' {
		return none
	}
	mut total := u64(0)
	mut idle := u64(0)
	for i, p in parts[1..] {
		v := u64(p.int()) // /proc fields are plain numbers; junk reads as 0
		total += v
		if i == 3 || i == 4 {
			idle += v
		}
	}
	return total, idle
}

// sample_cpu reads /proc/stat and sets cpu_percent to the busy fraction since
// the previous sample (0-100). The first sample is discarded so the meter
// starts empty rather than at the since-boot average. At most one sample
// is taken per second, so event-loop wakes (pointer motion, etc.) do not
// retrigger a toolbar repaint.
fn (mut wm WindowManager) sample_cpu() {
	now := time.now().unix()
	if now == wm.cpu_last_unix {
		return
	}
	wm.cpu_last_unix = now
	text := os.read_file('/proc/stat') or { return }
	mut line := text
	if nl := text.index('\n') {
		line = text[..nl]
	}
	total, idle := parse_cpu_line(line) or { return }
	if wm.cpu_prev_total > 0 {
		dtotal := total - wm.cpu_prev_total
		didle := idle - wm.cpu_prev_idle
		if dtotal > 0 {
			wm.cpu_percent = clamp_i(int((dtotal - didle) * 100 / dtotal), 0, 100)
		}
	}
	wm.cpu_prev_total = total
	wm.cpu_prev_idle = idle
}

// toolbar_wanted_width_for is the toolbar's pixel width for this section:
// the monitor width, a fixed `width`, or (when auto_width is set) the right
// edge of the left-packed contents plus the workspace buttons.
fn (mut wm WindowManager) toolbar_wanted_width_for(sec ThemeSection, titles []string) u32 {
	if !sec.auto_width {
		if sec.width > 0 {
			return sec.width
		}
		return 0 // toolbar_bar_rect treats 0 as "the monitor"
	}
	dummy := ScreenRect{0, 0, 4096, sec.height}
	mut end := 0
	for ele in sec.elements {
		if ele.area.right.edge == .right {
			continue // stretches with the bar; not a content edge
		}
		r := ele.area.resolve(dummy)
		right := r.x + int(r.width)
		if right > end {
			end = right
		}
	}
	if sec.has_workspace_buttons {
		wb := sec.workspace_buttons
		region := wb.area.resolve(dummy)
		mut total := 0
		for i, title in titles {
			st := button_states(false, false, false, false)
			total += wm.button_width_for(wb, title, i + 1, st, map[string]string{})
			if i < titles.len - 1 {
				total += wb.spacing
			}
		}
		mut pad := 4
		if wb.area.right.edge == .right {
			pad = -wb.area.right.offset
			if pad < 0 {
				pad = 0
			}
		}
		br := region.x + total + pad
		if br > end {
			end = br
		}
	}
	if end < int(sec.width) {
		end = int(sec.width)
	}
	if end < 16 {
		end = 16
	}
	return u32(end)
}

// place_toolbar adjusts only width and horizontal alignment around the
// anchor chosen at setup. It never recomputes rows or changes y / height.
fn (mut wm WindowManager) place_toolbar(mon_id MonitorId, bar_id int) {
	mon := wm.monitors[mon_id]
	tb := mon.toolbars[bar_id]
	sec := wm.toolbar_themes[tb.theme_index]
	titles := mon.workspaces.map(it.title)
	w := wm.toolbar_wanted_width_for(sec, titles)
	new_rect := toolbar_resize_rect(mon.geometry, tb.rect, w, sec.align)
	if new_rect == tb.rect {
		return
	}
	wm.monitors[mon_id].toolbars[bar_id].rect = new_rect
	log.debug('${toolbar_label(mon_id, bar_id)} rect: ${new_rect.x}:${new_rect.y}:${new_rect.width}:${new_rect.height}')
	if tb.win != 0 {
		wm.conn.move_resize(tb.win, new_rect.x, new_rect.y, new_rect.width, new_rect.height)
	}
}

// frame_origin is where a withdrawn client should be dropped on the root.
fn (wm &WindowManager) frame_origin(win &Window) (int, int) {
	if mon := wm.monitor_of(win.id) {
		r := wm.spec_rect(mon, win.id)
		return r.x, r.y
	}
	return 0, 0
}

fn on_path(prog string) bool {
	os.find_abs_path_of_executable(prog) or { return false }
	return true
}
