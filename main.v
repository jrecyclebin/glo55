module main

// main.v - entry point: orchestrates the initialisation sequence from SPEC.md
// and starts the event loop.
import glo55
import log
import os
import x11

const usage = 'usage: glo55 [-c config.toml]

Config lookup (first hit wins): -c PATH, $GLO55_CONFIG, ./config.toml,
~/.config/glo55/config.toml, then the installed default (share/glo55/config.toml).
Set GLO55_DEBUG=1 for verbose logging.'

fn find_config() string {
	mut args := os.args[1..].clone()
	for i, a in args {
		if a == '-h' || a == '--help' {
			println(usage)
			exit(0)
		}
		if a == '-c' && i + 1 < args.len {
			return args[i + 1]
		}
	}
	env := os.getenv('GLO55_CONFIG')
	if env != '' {
		return env
	}
	for p in ['config.toml', os.join_path(os.config_dir() or { '' }, 'glo55', 'config.toml')] {
		if os.exists(p) {
			return p
		}
	}
	installed := glo55.installed_config(os.executable())
	if installed != '' {
		return installed
	}
	return 'config.toml'
}

// fatal logs a critical failure with log.error and exits.
fn fatal(msg string) {
	log.error(msg)
	exit(1)
}

fn main() {
	if os.getenv('GLO55_DEBUG') != '' {
		log.set_level(.debug)
	}
	// Xlib's text converters (window titles in COMPOUND_TEXT) need LC_CTYPE set
	x11.init_locale()
	// 1. Connect to the X11 display
	conn := x11.X11Connection.open() or {
		fatal('${err}')
		return
	}
	// 2. Check if another window manager is running (exits via log.error if so)
	conn.become_window_manager()

	// The WindowManager object doubles as ConfigTarget and ThemeTarget, so it
	// has to exist before steps 3 and 4 (SPEC.md lists "build" as step 5).
	mut wm := glo55.new_window_manager(&conn) or {
		fatal('cannot create window manager: ${err}')
		return
	}

	// 3. Load configuration (config.toml)
	cfg_path := find_config()
	wm.config_path = os.real_path(cfg_path)
	glo55.load_config_into(mut wm, cfg_path) or {
		fatal('config: ${err}')
		return
	}
	log.info('loaded config ${cfg_path}')
	if wm.timezone != '' {
		glo55.apply_timezone(wm.timezone) // libc local time follows TZ
	}

	// 4. Load theme (theme.toml) and associated resources (fonts, images)
	theme_path := glo55.theme_path_for(cfg_path, wm.theme_path)
	glo55.load_theme_into(mut wm, theme_path) or {
		fatal('theme: ${err}')
		return
	}
	wm.draw.image_dir = wm.theme_dir
	for f in wm.theme_font_files {
		full := if os.is_abs_path(f) { f } else { os.join_path(wm.theme_dir, f) }
		if !x11.add_app_font(full) {
			log.error('cannot register theme font ${full}')
		}
	}
	wanted := glo55.theme_get_fonts(wm)
	loaded := wm.draw.load_fonts(wanted)
	if loaded.len < wanted.len {
		log.error('${wanted.len - loaded.len} theme font(s) could not be loaded; falling back to monospace')
	}
	log.info('loaded theme ${theme_path} (${wm.window_themes.len} window, ${wm.toolbar_themes.len} toolbar styles, ${loaded.len} fonts)')

	// 5. Build the WindowManager state from display information
	// 6. Initialize cursor        (done inside build)
	// 7. Draw toolbars and window decorations (done inside build / on map)
	wm.build() or {
		fatal('build: ${err}')
		return
	}

	// 8. Begin handling events
	wm.run()
	log.info('bye')
	conn.close()
}
