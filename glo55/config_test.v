module glo55

// Tests for config parsing: keybinding strings, actions, and whole-file loading.

struct TestConfig {
mut:
	mod_mask        u32
	monitor_configs []MonitorConfig
	keybindings     []KeyBinding
	master_ratio    f32
	theme_path      string
	timezone        string
	time_format     string
	date_format     string
}

const mod4 = u32(1) << 6
const shift = u32(1)

fn test_parse_keybinding_modifiers_and_keys() {
	m, k := parse_keybinding('Mod+Shift+Enter', mod4)!
	assert m == mod4 | shift
	assert k == 'Return'
	m2, k2 := parse_keybinding('Mod+1', mod4)!
	assert m2 == mod4 && k2 == '1'
	m3, k3 := parse_keybinding('Alt+Ctrl+J', mod4)!
	assert m3 == (u32(1) << 3) | (u32(1) << 2)
	assert k3 == 'j'
	m4, k4 := parse_keybinding('F5', mod4)!
	assert m4 == 0 && k4 == 'F5'
}

fn test_parse_keybinding_errors() {
	if _, _ := parse_keybinding('Hyper+x', mod4) {
		assert false
	}
	if _, _ := parse_keybinding('Mod+', mod4) {
		assert false
	}
}

fn test_parse_action_variants() {
	assert parse_action('workspace 3')! == Action{
		kind: .workspace
		n:    2
	}
	assert parse_action('warp 10')! == Action{
		kind: .warp
		n:    9
	}
	assert parse_action('focus left')! == Action{
		kind: .focus
		dir:  .left
	}
	assert parse_action('move down')! == Action{
		kind: .move
		dir:  .down
	}
	a := parse_action('exec kitty --single-instance')!
	assert a.kind == .exec && a.cmd == 'kitty --single-instance'
	assert parse_action('close')!.kind == .close
	assert parse_action('collapse')!.kind == .collapse
	assert parse_action('restore')!.kind == .restore
	assert parse_action('quit')!.kind == .quit
}

fn test_parse_action_errors() {
	for bad in ['workspace', 'workspace 0', 'workspace 11', 'workspace x', 'focus sideways', 'exec',
		'dance', ''] {
		if _ := parse_action(bad) {
			assert false, 'should have failed: ${bad}'
		}
	}
}

const sample = '
[general]
mod = "Mod1"
theme = "themes/x.toml"

[layout]
master_ratio = 0.6

[[monitors]]
workspaces = ["main", "web"]

[[monitors]]
workspaces = ["a", "b", "c"]

[keybindings]
"Mod+1" = "workspace 1"
"Mod+Shift+1" = "warp 1"
"Mod+j" = "focus down"
"Mod+Shift+Enter" = "exec xterm"
'

fn test_load_whole_config() {
	mut c := TestConfig{}
	parse_config_into(mut c, sample, '/etc/glo55')!
	assert c.mod_mask == u32(1) << 3 // Mod1
	assert c.master_ratio == 0.6
	assert c.theme_path == '/etc/glo55/themes/x.toml'
	assert c.monitor_configs.len == 2
	assert c.monitor_configs[0].workspaces == ['main', 'web']
	assert c.monitor_configs[1].workspaces.len == 3
	assert c.keybindings.len == 4
	b := c.keybindings[1]
	assert b.mods == (u32(1) << 3) | shift // Mod resolved to Mod1 + Shift
	assert b.key == '1'
	assert b.action.kind == .warp && b.action.n == 0
	assert c.keybindings[3].action.cmd == 'xterm'
}

fn test_config_defaults_and_validation() {
	mut c := TestConfig{}
	parse_config_into(mut c, '', '')!
	assert c.mod_mask == default_mod_mask
	assert c.master_ratio == default_master_ratio
	assert c.keybindings.len == 0
	if _ := parse_config_into(mut c, '[layout]\nmaster_ratio = 3.0', '') {
		assert false
	}
	if _ := parse_config_into(mut c, '[keybindings]\n"Mod+x" = "nope"', '') {
		assert false
	}
	if _ := parse_config_into(mut c, '[[monitors]]\nworkspaces = []', '') {
		assert false
	}
	if _ := parse_config_into(mut c, 'this is not toml', '') {
		assert false
	}
}

fn test_timezone_and_time_format() {
	mut c := TestConfig{}
	parse_config_into(mut c, '[general]\ntimezone = "America/Denver"\ntime_format = "h:mm a"\n',
		'.')!
	assert c.timezone == 'America/Denver'
	assert c.time_format == 'h:mm a'
	mut d := TestConfig{}
	parse_config_into(mut d, '[general]\n', '.')!
	assert d.timezone == '' && d.time_format == ''
}

// ---- actions added in patch 0007

fn test_parse_workspace_next_prev_reload_restart_fullscreen() {
	assert parse_action('workspace next')!.kind == .workspace_next
	assert parse_action('workspace prev')!.kind == .workspace_prev
	assert parse_action('workspace previous')!.kind == .workspace_prev
	assert parse_action('reload')!.kind == .reload
	assert parse_action('restart')!.kind == .restart
	assert parse_action('fullscreen')!.kind == .fullscreen
	assert parse_action('workspace 3')!.n == 2 // numbers still work
	if _ := parse_action('workspace sideways') {
		assert false
	}
}

fn test_default_bindings_are_added_unless_overridden() {
	none_set := with_default_bindings([]KeyBinding{}, mod4)
	assert none_set.len == 5
	mut has_tab := false
	for b in none_set {
		if b.key == 'Tab' && b.mods == mod4 {
			has_tab = true
			assert b.action.kind == .workspace_next
		}
	}
	assert has_tab
	// the action is already bound to another key: no second default for it
	moved := [
		KeyBinding{mod4, 'F5', Action{
			kind: .reload
		}, 'Mod+F5'},
	]
	out := with_default_bindings(moved, mod4)
	assert out.len == 5 // F5 reload + the other four defaults
	for b in out {
		assert !(b.key == 'r' && b.mods == mod4)
	}
	// the key combination is bound to something else: that wins
	taken := [
		KeyBinding{mod4, 'f', Action{
			kind: .exec
			cmd:  'thunar'
		}, 'Mod+f'},
	]
	out2 := with_default_bindings(taken, mod4)
	for b in out2 {
		if b.key == 'f' && b.mods == mod4 {
			assert b.action.kind == .exec
		}
	}
	assert out2.len == 5 // thunar + the other four (fullscreen has no key now)
}
