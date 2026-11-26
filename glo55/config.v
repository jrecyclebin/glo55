module glo55

// config.v - config.toml loading: monitors/workspaces, keybindings, a few
// layout settings. `load_config_into` fills any object implementing
// ConfigTarget (the WindowManager does).
import os
import toml

fn C.tzset()

// MonitorConfig is one `[[monitors]]` entry.
pub struct MonitorConfig {
pub:
	workspaces []string
}

pub enum ActionKind {
	workspace      // workspace N: show workspace N on the active monitor
	warp           // warp N: move the focused window to workspace N
	focus          // focus up|down|left|right
	move           // move up|down|left|right
	exec           // exec CMD: run a command
	close          // close: ask the focused window to close
	collapse       // collapse: minimise the focused window (others fill its space)
	restore        // restore: bring back the most recently collapsed window
	quit           // quit: leave the window manager
	workspace_next // workspace next: the next workspace of the active monitor (wraps)
	workspace_prev // workspace prev: the previous one (wraps)
	reload         // reload: re-read config.toml and theme.toml in place
	restart        // restart: re-exec the window manager; the windows stay
	fullscreen     // fullscreen: toggle the focused window over its whole monitor
}

// Action is a parsed keybinding action.
pub struct Action {
pub:
	kind ActionKind
	n    int       // 0-based workspace index for workspace/warp
	dir  Direction // for focus/move
	cmd  string    // for exec
}

// KeyBinding is a parsed `"Mod+Shift+1" = "warp 1"` line.
pub struct KeyBinding {
pub:
	mods   u32    // X modifier mask (Mod already resolved)
	key    string // keysym name, e.g. "Return", "j", "1"
	action Action
	source string // the original "Mod+..." text, for logging
}

// ConfigTarget is implemented by whatever wants to receive configuration.
pub interface ConfigTarget {
mut:
	mod_mask        u32 // what "Mod" means in keybindings
	monitor_configs []MonitorConfig
	keybindings     []KeyBinding
	master_ratio    f32
	theme_path      string // path of theme.toml (relative paths are relative to config.toml)
	timezone        string // IANA zone for the toolbar clock ('' = system/TZ)
	time_format     string // clock format for $time ('' = "HH:mm")
	date_format     string // calendar format for $date ('' = "ddd DD MMM")
}

// apply_timezone points libc's local time at `tz`: an IANA zone name, or ''
// for "no TZ" (the system default). The toolbar clock ($time / $date) follows.
// Parsing a config never touches the environment; the caller applies this on
// commit, so a config that fails to load leaves the running zone alone.
pub fn apply_timezone(tz string) {
	if tz == '' {
		os.unsetenv('TZ')
	} else {
		os.setenv('TZ', tz, true)
	}
	C.tzset()
}

// load_config_into reads a config.toml file into ct.
pub fn load_config_into(mut ct ConfigTarget, path string) ! {
	text := os.read_file(path) or { return error('cannot read ${path}: ${err}') }
	parse_config_into(mut ct, text, os.dir(path)) or { return error('${path}: ${err}') }
}

// parse_config_into is the file-less half of load_config_into (used by tests).
pub fn parse_config_into(mut ct ConfigTarget, text string, base_dir string) ! {
	doc := toml.parse_text(text) or { return error('invalid TOML: ${err}') }
	root := doc.to_any().as_map()

	// [general]
	mut mod := u32(0)
	if g := root['general'] {
		gm := g.as_map()
		if m := gm['mod'] {
			mod = parse_modifier_name(m.string(), 0) or { return error('general.mod: ${err}') }
		}
		if t := gm['theme'] {
			ct.theme_path = resolve_path(base_dir, t.string())
		}
		if tz := gm['timezone'] {
			ct.timezone = tz.string() // applied by the caller on commit (see apply_timezone)
		}
		if tf := gm['time_format'] {
			ct.time_format = tf.string()
		}
		if df := gm['date_format'] {
			ct.date_format = df.string()
		}
	}
	if mod == 0 {
		mod = default_mod_mask
	}
	ct.mod_mask = mod

	// [layout]
	ct.master_ratio = default_master_ratio
	if l := root['layout'] {
		if r := l.as_map()['master_ratio'] {
			ratio := r.f32()
			if ratio < 0.1 || ratio > 0.9 {
				return error('layout.master_ratio must be between 0.1 and 0.9')
			}
			ct.master_ratio = ratio
		}
	}

	// [[monitors]]
	ct.monitor_configs = []MonitorConfig{}
	if ms := root['monitors'] {
		for m in ms.array() {
			mut titles := []string{}
			if w := m.as_map()['workspaces'] {
				for t in w.array() {
					titles << t.string()
				}
			}
			if titles.len == 0 || titles.len > 10 {
				return error('each [[monitors]] entry needs 1..10 workspaces')
			}
			ct.monitor_configs << MonitorConfig{titles}
		}
	}

	// [keybindings]
	ct.keybindings = []KeyBinding{}
	if kb := root['keybindings'] {
		for k, v in kb.as_map() {
			mods, key := parse_keybinding(k, mod) or { return error('keybinding "${k}": ${err}') }
			action := parse_action(v.string()) or {
				return error('keybinding "${k}" action "${v.string()}": ${err}')
			}
			ct.keybindings << KeyBinding{mods, key, action, k}
		}
	}
}

// with_default_bindings adds the built-in bindings that the config did not
// already cover: a default is skipped when its key combination is bound to
// something else, or when its action is bound to some other key (so rebinding
// "reload" to "Mod+F5" doesn't leave Mod+r around as well).
pub fn with_default_bindings(bindings []KeyBinding, mod_mask u32) []KeyBinding {
	mut out := bindings.clone()
	for src, text in default_bindings {
		mods, key := parse_keybinding(src, mod_mask) or { continue }
		action := parse_action(text) or { continue }
		mut taken := false
		for b in bindings {
			if (b.mods == mods && b.key == key) || b.action.kind == action.kind {
				taken = true
				break
			}
		}
		if !taken {
			out << KeyBinding{mods, key, action, src}
		}
	}
	return out
}

// default_bindings are the built-in keys for the actions added after the
// first release; config.toml can rebind any of them (see with_default_bindings).
pub const default_bindings = {
	'Mod+Tab':       'workspace next'
	'Mod+Shift+Tab': 'workspace prev'
	'Mod+r':         'reload'
	'Mod+Shift+r':   'restart'
	'Mod+f':         'fullscreen'
}

pub const default_mod_mask = u32(1) << 6 // Mod4 (Super)
pub const default_master_ratio = f32(0.55)

fn resolve_path(base_dir string, p string) string {
	if os.is_abs_path(p) || base_dir == '' {
		return p
	}
	return os.join_path(base_dir, p)
}

// parse_modifier_name maps a modifier word to its X mask. "Mod" is whatever
// the config's [general] mod says (passed in as mod_mask; 0 = not allowed).
pub fn parse_modifier_name(name string, mod_mask u32) !u32 {
	return match name.to_lower() {
		'shift' {
			u32(1) << 0
		}
		'ctrl', 'control' {
			u32(1) << 2
		}
		'alt', 'mod1' {
			u32(1) << 3
		}
		'mod2' {
			u32(1) << 4
		}
		'mod3' {
			u32(1) << 5
		}
		'super', 'win', 'mod4' {
			u32(1) << 6
		}
		'mod5' {
			u32(1) << 7
		}
		'mod' {
			if mod_mask == 0 {
				return error('"Mod" cannot be used to define itself')
			}
			mod_mask
		}
		else {
			return error('unknown modifier "${name}"')
		}
	}
}

// parse_keybinding splits "Mod+Shift+Enter" into (modifier mask, keysym name).
// The last '+'-separated part is the key; everything before it is a modifier.
pub fn parse_keybinding(s string, mod_mask u32) !(u32, string) {
	parts := s.split('+').map(it.trim_space())
	if parts.len == 0 || parts.last() == '' {
		return error('empty key')
	}
	mut mods := u32(0)
	for p in parts[..parts.len - 1] {
		mods |= parse_modifier_name(p, mod_mask)!
	}
	return mods, normalize_key_name(parts.last())
}

// normalize_key_name maps friendly names to X keysym names.
pub fn normalize_key_name(k string) string {
	return match k.to_lower() {
		'enter' {
			'Return'
		}
		'return' {
			'Return'
		}
		'space' {
			'space'
		}
		'tab' {
			'Tab'
		}
		'esc', 'escape' {
			'Escape'
		}
		'backspace' {
			'BackSpace'
		}
		'left' {
			'Left'
		}
		'right' {
			'Right'
		}
		'up' {
			'Up'
		}
		'down' {
			'Down'
		}
		else {
			if k.len == 1 {
				k.to_lower()
			} else {
				k
			}
		}
	}
}

// parse_action parses "workspace 3", "warp 2", "focus left", "move down",
// "exec kitty", "close", "collapse", "restore", "quit", "workspace next",
// "workspace prev", "reload", "restart", "fullscreen".
// Workspace numbers are 1-based in the file (and 10 is the "0" key's workspace).
pub fn parse_action(s string) !Action {
	text := s.trim_space()
	word := text.all_before(' ')
	arg := text.all_after_first(' ').trim_space()
	arg_is_empty := text.index(' ') == none
	match word {
		'workspace', 'warp' {
			if word == 'workspace' && arg in ['next', 'prev', 'previous'] {
				return Action{
					kind: if arg == 'next' {
						ActionKind.workspace_next
					} else {
						ActionKind.workspace_prev
					}
				}
			}
			n := arg.int()
			if arg_is_empty || n < 1 || n > 10 || n.str() != arg {
				return error('"${word}" needs a workspace number 1..10' +
					if word == 'workspace' { ', "next" or "prev"' } else { '' })
			}
			return Action{
				kind: if word == 'workspace' { ActionKind.workspace } else { ActionKind.warp }
				n:    n - 1
			}
		}
		'focus', 'move' {
			dir := Direction.parse(arg) or {
				return error('"${word}" needs up, down, left or right')
			}
			return Action{
				kind: if word == 'focus' { ActionKind.focus } else { ActionKind.move }
				dir:  dir
			}
		}
		'exec' {
			if arg_is_empty || arg == '' {
				return error('"exec" needs a command')
			}
			return Action{
				kind: .exec
				cmd:  arg
			}
		}
		'close' {
			return Action{
				kind: .close
			}
		}
		'collapse' {
			return Action{
				kind: .collapse
			}
		}
		'restore' {
			return Action{
				kind: .restore
			}
		}
		'quit' {
			return Action{
				kind: .quit
			}
		}
		'reload' {
			return Action{
				kind: .reload
			}
		}
		'restart' {
			return Action{
				kind: .restart
			}
		}
		'fullscreen' {
			return Action{
				kind: .fullscreen
			}
		}
		else {
			return error('unknown action "${word}"')
		}
	}
}
