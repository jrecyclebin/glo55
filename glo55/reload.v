module glo55

// reload.v - `reload` (re-read config.toml and theme.toml without losing a
// window) and `restart` (re-exec the binary; the clients survive it).
import log
import os
import x11

// ConfigSnapshot and ThemeSnapshot receive a freshly parsed config / theme
// during a reload. Only when both parse is anything copied into the running
// WindowManager, so a typo in the file leaves the current setup untouched.
struct ConfigSnapshot {
pub mut:
	mod_mask        u32
	monitor_configs []MonitorConfig
	keybindings     []KeyBinding
	master_ratio    f32
	theme_path      string
	timezone        string
	time_format     string
	date_format     string
}

struct ThemeSnapshot {
pub mut:
	theme_vars              map[string]string
	theme_dir               string
	window_themes           []ThemeSection
	toolbar_themes          []ThemeSection
	theme_font_files        []string
	theme_background        string
	theme_background_scale  string
	theme_background_filter string
}

// theme_path_for is where theme.toml is: the config's `theme` setting
// (`configured` has already been joined to the config's directory), searched
// for as described at resolve_theme, else a theme.toml next to the config file.
pub fn theme_path_for(config_path string, configured string) string {
	if configured == '' {
		return os.join_path(os.dir(config_path), 'theme.toml')
	}
	base := os.dir(config_path)
	prefix := base + os.path_separator
	if !configured.starts_with(prefix) || os.exists(configured) {
		return configured // absolute in the file, or found where it was written
	}
	return resolve_theme(base, configured[prefix.len..], os.config_dir() or { '' },
		data_dirs(os.executable()))
}

// reload re-reads config.toml and the theme and applies them in place:
// keybindings, colours and frames, toolbars, the per-monitor workspace lists
// (renamed, grown, or shrunk with the dropped workspaces' windows folded into
// the last one), the master ratio, the clock. Windows are never closed or
// unmapped for it. If either file fails to load the error is logged and
// the running configuration is kept.
pub fn (mut wm WindowManager) reload() {
	if wm.config_path == '' {
		log.error('reload: no config file to read')
		return
	}
	mut cs := ConfigSnapshot{}
	load_config_into(mut cs, wm.config_path) or {
		log.error('reload: ${err}: keeping the current configuration')
		return
	}
	theme_path := theme_path_for(wm.config_path, cs.theme_path)
	mut ts := ThemeSnapshot{}
	load_theme_into(mut ts, theme_path) or {
		log.error('reload: ${err}: keeping the current configuration')
		return
	}
	if ts.window_themes.len == 0 || ts.toolbar_themes.len == 0 {
		log.error('reload: ${theme_path} needs at least one [[windows]] and one [[toolbars]]: keeping the current configuration')
		return
	}
	// both parsed: commit
	wm.mod_mask = cs.mod_mask
	wm.monitor_configs = cs.monitor_configs
	wm.keybindings = cs.keybindings
	wm.master_ratio = cs.master_ratio
	wm.theme_path = cs.theme_path
	wm.timezone = cs.timezone
	wm.time_format = cs.time_format
	wm.date_format = cs.date_format
	wm.theme_vars = ts.theme_vars.clone()
	wm.theme_dir = ts.theme_dir
	wm.window_themes = ts.window_themes
	wm.toolbar_themes = ts.toolbar_themes
	wm.theme_font_files = ts.theme_font_files
	wm.theme_background = ts.theme_background
	wm.theme_background_scale = ts.theme_background_scale
	wm.theme_background_filter = ts.theme_background_filter
	// a dropped [general] timezone goes back to the startup zone
	apply_timezone(if wm.timezone == '' { wm.orig_tz } else { wm.timezone })
	wm.apply_settings()
	log.info('reloaded ${wm.config_path} and ${theme_path} (clock now reads ${wm.clock()})')
}

// apply_settings pushes the (new) config and theme into everything derived
// from them: caches, fonts, layouts, workspaces, toolbars, grabs, frames.
fn (mut wm WindowManager) apply_settings() {
	wm.draw.image_dir = wm.theme_dir
	wm.draw.images = map[string]LoadedImage{} // images may have changed on disk
	wm.draw.scaled_images = map[string]ScaledImage{}
	for f in wm.theme_font_files {
		full := if os.is_abs_path(f) { f } else { os.join_path(wm.theme_dir, f) }
		if !x11.add_app_font(full) {
			log.error('cannot register theme font ${full}')
		}
	}
	wanted := theme_get_fonts(wm)
	loaded := wm.draw.load_fonts(wanted)
	if loaded.len < wanted.len {
		log.error('${wanted.len - loaded.len} theme font(s) could not be loaded; falling back to monospace')
	}
	for i in 0 .. wm.monitors.len {
		wm.layouts[i] = wm.make_layout(i) // in place: the workspaces point at these slots
		mut mon := &wm.monitors[i]
		if mon.set_titles(wm.monitor_titles(i), unsafe { &wm.layouts[i] }) {
			log.info('monitor ${i}: now ${mon.workspaces.len} workspaces')
		}
		wm.sync_toolbars(i)
	}
	wm.bind_keys()
	desk := wm.theme_vars['desktop_color'] or { '#1b1f2a' }
	if c := parse_color(desk) {
		wm.conn.set_root_background(wm.draw.to_pixel(c))
	}
	wm.draw_desktop_background()
	for i in 0 .. wm.monitors.len {
		wm.sync_visibility(i)
		wm.apply_layout(i)
		mon := wm.monitors[i]
		for spec in mon.workspaces[mon.active].windows {
			wm.place_window(spec.info, spec.rect) // floating windows: new insets
			wm.draw_frame(spec.info)
		}
		for id in mon.window_ids() {
			wm.publish_desktop(id)
		}
	}
	if wm.focused_client != 0 {
		if w := wm.find_window(wm.focused_client) {
			if !w.is_visible() {
				wm.focused_client = 0
			}
		}
	}
	if wm.focused_client == 0 && wm.monitors.len > 0 {
		mon := wm.monitors[wm.active_monitor]
		wm.focus_window(mon.workspaces[mon.active].focused)
	}
	wm.draw_all_toolbars(true)
	wm.conn.flush()
}

// sync_visibility shows exactly the windows of a monitor's active workspace
// (after the workspace list changed, some windows may have moved).
fn (mut wm WindowManager) sync_visibility(mon_id MonitorId) {
	mon := wm.monitors[mon_id]
	shown := mon.workspaces[mon.active].visible_ids()
	for id in mon.window_ids() {
		mut w := wm.find_window(id) or { continue }
		want := id in shown
		if want && !w.is_visible() {
			w.set_visible(true)
			wm.conn.map_window(w.frame)
		} else if !want && w.is_visible() {
			w.set_visible(false)
			wm.conn.unmap_window(w.frame)
		}
	}
}

// restart replaces this process with a fresh copy of the binary (same
// arguments), keeping every client alive:
//  - each client gets _GLO55_WORKSPACE = [monitor, workspace, slot, rolled-up]
//    and _NET_WM_DESKTOP, and the root gets _GLO55_SESSION (active monitor,
//    focused window, active workspace per monitor);
//  - windows on hidden workspaces are unmapped, every client is reparented back
//    to the root at its place, and the frames and toolbars are destroyed;
//  - the root selection and key grabs are dropped, then execvp.
// The new process finds the clients with XQueryTree and puts each back.
pub fn (mut wm WindowManager) restart() {
	exe := os.executable()
	if exe == '' || !os.is_executable(exe) {
		log.error('restart: cannot find the glo55 binary (${exe}): staying up')
		return
	}
	log.info('restarting: re-executing ${exe} ${os.args[1..]}')
	mut session := [i64(wm.active_monitor), i64(wm.focused_client)]
	for m in wm.monitors {
		session << i64(m.active)
	}
	wm.conn.set_cardinals(wm.conn.root, wm.conn.atom_glo55_session, session)
	for mi, m in wm.monitors {
		for wi, ws in m.workspaces {
			for si, spec in ws.windows {
				w := spec.info
				wm.conn.set_cardinals(w.id, wm.conn.atom_glo55_workspace, [i64(mi), i64(wi), i64(si),
					if w.is_collapsed() { i64(1) } else { i64(0) }])
				wm.conn.set_cardinals(w.id, wm.conn.atom_net_wm_desktop, [i64(wi)])
				if !w.is_visible() {
					wm.conn.unmap_window(w.id)
				}
				rx, ry := wm.frame_origin(w)
				wm.conn.reparent(w.id, wm.conn.root, rx, ry)
			}
		}
	}
	for w in wm.windows {
		wm.conn.destroy_window(w.frame)
	}
	for m in wm.monitors {
		for tb in m.toolbars {
			wm.conn.destroy_window(tb.win)
		}
	}
	wm.conn.release_root()
	wm.conn.flush()
	os.execvp(exe, os.args[1..]) or {
		log.error('restart: exec failed: ${err}')
		exit(1) // the windows are back on the root, but nothing manages them now
	}
}
