module glo55

import os

// Tests for theme parsing, variable replacement, state overrides and element
// positioning. No X server needed.

struct TestTheme {
mut:
	theme_vars              map[string]string
	theme_dir               string
	window_themes           []ThemeSection
	toolbar_themes          []ThemeSection
	theme_font_files        []string
	theme_background        string
	theme_background_scale  string
	theme_background_filter string
}

fn test_substitute_replaces_known_vars() {
	vars := {
		'primary_color': '#112233'
		'primary':       'WRONG'
		'x':             '1'
	}
	assert substitute('$primary_color', vars) == '#112233'
	assert substitute('a $x b', vars) == 'a 1 b'
	assert substitute('\$x\$x', vars) == '11'
}

fn test_substitute_is_greedy_and_leaves_unknowns() {
	vars := {
		'primary': 'P'
	}
	// longest identifier wins: $primary_color is unknown, so left as-is
	assert substitute('$primary_color', vars) == '$primary_color'
	assert substitute('$primary!', vars) == 'P!'
	assert substitute('$unknown $title', vars) == '$unknown $title'
	assert substitute('no vars', vars) == 'no vars'
	assert substitute('cost: $', vars) == 'cost: $'
}

fn test_resolve_vars_state_overrides_priority_and_runtime() {
	mut sec := ThemeSection{}
	sec.states['focused'] = {
		'primary_color': '#ffd700'
	}
	sec.states['hover'] = {
		'primary_color': '#add8e6'
	}
	globals := {
		'primary_color': '#87ceeb'
		'text_color':    '#ffffff'
	}
	plain := sec.resolve_vars(globals, []string{}, map[string]string{})
	assert plain['primary_color'] == '#87ceeb'
	foc := sec.resolve_vars(globals, ['focused'], map[string]string{})
	assert foc['primary_color'] == '#ffd700'
	assert foc['text_color'] == '#ffffff' // inherited from [vars]
	// when several states are active the later one in focused<hover<clicked<collapsed wins
	both := sec.resolve_vars(globals, ['hover', 'focused'], map[string]string{})
	assert both['primary_color'] == '#add8e6'
	// runtime variables always win and are merged in
	rt := sec.resolve_vars(globals, []string{}, {
		'title': 'hello'
	})
	assert rt['title'] == 'hello'
}

fn test_vars_can_reference_other_vars() {
	sec := ThemeSection{}
	globals := {
		'base': '#102030'
		'bar':  '$base'
	}
	v := sec.resolve_vars(globals, []string{}, map[string]string{})
	assert v['bar'] == '#102030'
}

fn test_theme_area_resolution() {
	b := ScreenRect{0, 0, 200, 100}
	// full-area background
	full :=
		ThemeArea{EdgeRef{.left, 0, 0}, EdgeRef{.top, 0, 0}, EdgeRef{.right, 0, 0}, EdgeRef{.bottom, 0, 0}}
	assert full.resolve(b) == ScreenRect{0, 0, 200, 100}
	// 2px strip along the top (spec's border_top: bottom = top edge + 2)
	top :=
		ThemeArea{EdgeRef{.left, 0, 0}, EdgeRef{.top, 0, 0}, EdgeRef{.right, 0, 0}, EdgeRef{.top, 2, 0}}
	assert top.resolve(b) == ScreenRect{0, 0, 200, 2}
	// negative offsets move inwards from right/bottom (spec's clock: right -100 .. -10)
	clock :=
		ThemeArea{EdgeRef{.right, -100, 0}, EdgeRef{.top, 4, 0}, EdgeRef{.right, -10, 0}, EdgeRef{.bottom, -4, 0}}
	assert clock.resolve(b) == ScreenRect{100, 4, 90, 92}
	// inverted rectangles collapse to zero size instead of wrapping around
	bad :=
		ThemeArea{EdgeRef{.left, 50, 0}, EdgeRef{.top, 0, 0}, EdgeRef{.left, 10, 0}, EdgeRef{.bottom, 0, 0}}
	assert bad.resolve(b).width == 0
}

const sample_theme = '
[vars]
primary_color = "#87ceeb"
text_color = "#ffffff"

[[windows]]
border_width = 3
window_gap = 6

[windows.focused]
primary_color = "#ffd700"

[windows.hover]
primary_color = "#add8e6"

[windows.background]
type = "solid"
left = { edge = "left", offset = 0 }
top = { edge = "top", offset = 0 }
right = { edge = "right", offset = 0 }
bottom = { edge = "bottom", offset = 0 }
fore = "$primary_color"
back = "#000000"

[windows.border_top]
type = "gradient"
bottom = { edge = "top", offset = 2 }
fore = "$primary_color"
back = "#4682b4"
direction = 90

[[toolbars]]
height = 30

[toolbars.title]
type = "text"
content = "$title"
font = "monospace"
size = 11
fore = "$text_color"
align = "center"

[[toolbars]]
monitor = 3
height = 20
'

fn test_load_theme() {
	mut t := TestTheme{}
	parse_theme_into(mut t, sample_theme)!
	assert t.theme_vars['primary_color'] == '#87ceeb'
	assert t.window_themes.len == 1
	w := t.window_themes[0]
	assert w.border_width == 3 && w.window_gap == 6
	assert w.elements.len == 2
	// element order follows the file (background is drawn first)
	assert w.elements[0].name == 'background'
	assert w.elements[0].fore == '\$primary_color'
	assert w.elements[1].name == 'border_top'
	assert w.elements[1].kind == .gradient && w.elements[1].direction == 90
	// state tables are NOT elements
	assert w.states['focused']['primary_color'] == '#ffd700'
	assert w.states['hover']['primary_color'] == '#add8e6'
	// toolbars
	assert t.toolbar_themes.len == 2
	assert t.toolbar_themes[0].height == 30
	assert t.toolbar_themes[0].elements[0].kind == .text
	assert t.toolbar_themes[0].elements[0].align == 'center'
	assert t.toolbar_themes[1].monitor == 3
}

fn test_theme_fonts_are_collected() {
	mut t := TestTheme{}
	parse_theme_into(mut t, sample_theme)!
	assert theme_get_fonts(t) == ['monospace:pixelsize=11']
}

fn test_theme_validation() {
	mut t := TestTheme{}
	if _ := parse_theme_into(mut t, '[vars]\na = "b"') {
		assert false, 'a theme without [[windows]] must be rejected'
	}
	if _ := parse_theme_into(mut t, '[[windows]]\n[windows.x]\ntype = "bogus"') {
		assert false, 'unknown element type must be rejected'
	}
	if _ := parse_theme_into(mut t, '[[windows]]\n[windows.x]\nleft = { edge = "left" }') {
		assert false, 'element without type must be rejected'
	}
}

fn test_pick_section_by_monitor() {
	mut a := ThemeSection{}
	mut b := ThemeSection{}
	mut c := ThemeSection{}
	b.monitor = -1
	c.monitor = 5
	secs := [a, b, c]
	assert pick_section(secs, 0) == 0
	assert pick_section(secs, 1) == 1 // by position
	assert pick_section(secs, 2) == 0 // entry 2 is pinned to monitor 5, so default
	assert pick_section(secs, 5) == 2 // explicit monitor wins
	assert pick_section(secs, 9) == 0 // unknown monitor -> first entry
	_ = a
}

fn test_pick_toolbar_sections_stacks_explicit_monitor_entries() {
	default := ThemeSection{}
	second := ThemeSection{}
	first_top := ThemeSection{
		monitor: 0
		height:  30
	}
	second_top := ThemeSection{
		monitor: 0
		height:  20
	}
	other := ThemeSection{
		monitor: 1
		height:  12
	}
	sections := [default, second, first_top, second_top, other]
	assert pick_toolbar_sections(sections, 0) == [2, 3]
	assert pick_toolbar_sections(sections, 1) == [4]
	assert pick_toolbar_sections(sections, 2) == [0]
}

fn test_font_pattern() {
	assert font_pattern('', 12) == 'monospace:pixelsize=12'
	assert font_pattern('DejaVu Sans', 0) == 'DejaVu Sans'
}

fn test_theme_area_ratio_is_a_fraction_of_the_extent() {
	b := ScreenRect{0, 0, 200, 100}
	// "from 16px to the centre line" then "centre+1 .. centre+85"
	title :=
		ThemeArea{EdgeRef{.left, 16, 0}, EdgeRef{.top, 0, 0}, EdgeRef{.left, 0, 0.5}, EdgeRef{.top, 20, 0}}
	assert title.resolve(b) == ScreenRect{16, 0, 84, 20}
	trim :=
		ThemeArea{EdgeRef{.left, 1, 0.5}, EdgeRef{.top, 0, 0}, EdgeRef{.left, 85, 0.5}, EdgeRef{.top, 20, 0}}
	assert trim.resolve(b) == ScreenRect{101, 0, 84, 20}
	// vertical ratio uses the height; a ratio on a right edge is relative to that edge
	mid :=
		ThemeArea{EdgeRef{.left, 0, 0}, EdgeRef{.top, 0, 0.25}, EdgeRef{.right, 0, -0.25}, EdgeRef{.bottom, 0, 0}}
	assert mid.resolve(b) == ScreenRect{0, 25, 150, 75}
}

const insets_theme = '
background = "bg.jpg"
background_scale = "stretch"
font_files = ["a.ttf", "b.ttf"]

[[windows]]
border_width = 3
[windows.insets]
left = 10
right = 11
top = 20
bottom = 12

[windows.bar]
type = "image"
path = "x.png"
scale = "slice"
slice = [1, 2, 3, 4]
left = { edge = "left", ratio = 0.5, offset = 2 }
action = "close"
shadow = "#000000"

[[windows]]
border_width = 5
'

fn test_theme_insets_scale_ratio_and_assets_parse() {
	mut tt := TestTheme{}
	parse_theme_into(mut tt, insets_theme)!
	assert tt.theme_background == 'bg.jpg'
	assert tt.theme_background_scale == 'stretch'
	assert tt.theme_font_files == ['a.ttf', 'b.ttf']
	w := tt.window_themes[0]
	assert w.frame_insets() == Insets{10, 20, 11, 12}
	// no insets table: border_width on every side
	assert tt.window_themes[1].frame_insets() == Insets{5, 5, 5, 5}
	e := w.elements[0]
	assert e.scale == .slice
	assert e.slice == [1, 2, 3, 4]!
	assert e.area.left.ratio == 0.5 && e.area.left.offset == 2
	assert e.action == 'close' && e.shadow == '#000000'
}

fn test_element_scale_defaults_and_errors() {
	mut tt := TestTheme{}
	parse_theme_into(mut tt,
		'[[windows]]\n[windows.a]\ntype = "pattern"\npath = "p.png"\n[windows.b]\ntype = "image"\npath = "p.png"\n')!
	assert tt.window_themes[0].elements[0].scale == .tile
	assert tt.window_themes[0].elements[1].scale == .none
	if _ := parse_theme_into(mut tt, '[[windows]]\n[windows.a]\ntype = "image"\nscale = "slice"\n') {
		assert false
	}
	if _ := parse_theme_into(mut tt, '[[windows]]\n[windows.a]\ntype = "image"\nscale = "wobble"\n') {
		assert false
	}
}

fn test_rolled_height_comes_from_the_title_bar_or_the_setting() {
	// no insets, no setting: the default
	assert ThemeSection{}.rolled_height() == default_rolled_height
	// a themed title bar (top inset) is the rolled height
	mut t := ThemeSection{}
	t.insets = Insets{4, 18, 4, 4}
	t.has_insets = true
	assert t.rolled_height() == 18
	// an explicit collapsed_height wins
	t.collapsed_height = 24
	assert t.rolled_height() == 24
	// insets with no top (a plain border) don't count as a title bar
	mut u := ThemeSection{}
	u.insets = Insets.uniform(0)
	u.has_insets = true
	assert u.rolled_height() == default_rolled_height
}

fn test_collapsed_height_and_when_unless_parse() {
	mut tt := TestTheme{}
	parse_theme_into(mut tt,
		'[[windows]]\ncollapsed_height = 22\n[windows.a]\ntype = "solid"\nwhen = "collapsed"\n[windows.b]\ntype = "solid"\nunless = "collapsed"\n[windows.c]\ntype = "solid"\n')!
	sec := tt.window_themes[0]
	assert sec.collapsed_height == 22
	assert sec.rolled_height() == 22
	a, b, c := sec.elements[0], sec.elements[1], sec.elements[2]
	rolled := ['collapsed']
	plain := ['focused']
	assert a.when == ['collapsed'] && a.unless.len == 0
	assert b.unless == ['collapsed']
	assert a.active_in(rolled) && !a.active_in(plain) && !a.active_in([])
	assert !b.active_in(rolled) && b.active_in(plain) && b.active_in([])
	assert c.active_in(rolled) && c.active_in([])
}

fn test_text_transform() {
	assert apply_transform('Your Corporate Training', 'upper') == 'YOUR CORPORATE TRAINING'
	assert apply_transform('ABC', 'lower') == 'abc'
	assert apply_transform('Abc', '') == 'Abc'
	assert apply_transform('Abc', 'shout') == 'Abc'
	assert apply_transform('Window Title', 'track') == 'W I N D O W T I T L E'
}

const extends_base = '
background = "art/desktop.png"
background_scale = "cover"
font_files = ["../fonts/f.ttf"]

[vars]
ink = "#111111"
cream = "#eeeeee"
title = "$ink"

[[windows]]
window_gap = 6
shaped = true

[windows.insets]
left = 5
top = 36
right = 5
bottom = 5

[windows.00_title]
type = "text"
content = "$title"
fore = "$cream"
outline = "$ink"
shaped = true
'

fn test_text_outline_and_shaped_parse() {
	mut tt := TestTheme{}
	parse_theme_into(mut tt, extends_base)!
	e := tt.window_themes[0].elements[0]
	assert e.outline == '$ink'
	assert e.shaped
	assert tt.theme_background_filter == 'nearest' // the default
	parse_theme_into(mut tt, 'background_filter = "linear"\n' + extends_base)!
	assert tt.theme_background_filter == 'linear'
}

fn test_theme_extends_merges_vars_and_inherits_the_layout() {
	dir := os.join_path(os.temp_dir(), 'glo55_extends_test_${os.getpid()}')
	os.mkdir_all(os.join_path(dir, 'pal'))!
	defer {
		os.rmdir_all(dir) or {}
	}
	os.write_file(os.join_path(dir, 'layout.toml'), extends_base)!
	os.write_file(os.join_path(dir, 'pal', 'theme.toml'),
		'extends = "../layout.toml"\nbackground_scale = "stretch"\n[vars]\ncream = "#abcdef"\nextra = "x"\n')!
	mut tt := TestTheme{}
	load_theme_into(mut tt, os.join_path(dir, 'pal', 'theme.toml'))!
	// paths stay relative to the extending theme's directory
	assert tt.theme_dir == os.join_path(dir, 'pal')
	// top-level keys of the extender win; the rest comes from the base
	assert tt.theme_background_scale == 'stretch'
	assert tt.theme_background == 'art/desktop.png'
	assert tt.theme_font_files == ['../fonts/f.ttf']
	// [vars] is merged key by key
	assert tt.theme_vars['ink'] == '#111111'
	assert tt.theme_vars['cream'] == '#abcdef'
	assert tt.theme_vars['extra'] == 'x'
	assert tt.window_themes[0].frame_insets() == Insets{5, 36, 5, 5}
	assert tt.window_themes[0].shaped
}

fn test_theme_extends_loop_and_missing_base_are_errors() {
	dir := os.join_path(os.temp_dir(), 'glo55_extends_loop_${os.getpid()}')
	os.mkdir_all(dir)!
	defer {
		os.rmdir_all(dir) or {}
	}
	os.write_file(os.join_path(dir, 'a.toml'), 'extends = "b.toml"\n')!
	os.write_file(os.join_path(dir, 'b.toml'), 'extends = "a.toml"\n')!
	mut tt := TestTheme{}
	if _ := load_theme_into(mut tt, os.join_path(dir, 'a.toml')) {
		assert false
	} else {
		assert err.msg().contains('too deeply')
	}
	os.write_file(os.join_path(dir, 'c.toml'), 'extends = "nope.toml"\n')!
	if _ := load_theme_into(mut tt, os.join_path(dir, 'c.toml')) {
		assert false
	} else {
		assert err.msg().contains('cannot read')
	}
}

// Every Fresh Breath palette extends the shared layout and every image it
// names exists in the palette's art/ (both the focused and the unfocused set).
fn test_fresh_breath_palettes_load_and_their_art_exists() {
	root := os.join_path(@VMODROOT, 'themes', 'fresh-breath')
	for pal in ['sedona', 'painted-desert', 'chillwave', 'office-print'] {
		mut tt := TestTheme{}
		load_theme_into(mut tt, os.join_path(root, pal, 'theme.toml'))!
		assert tt.window_themes.len == 1 && tt.toolbar_themes.len == 1
		w := tt.window_themes[0]
		assert w.shaped
		assert w.frame_insets() == Insets{9, 38, 5, 5}
		assert w.collapsed_height == 39
		assert tt.theme_background_scale == 'cover' && tt.theme_background_filter == 'linear'
		assert os.exists(os.join_path(tt.theme_dir, tt.theme_background))
		for f in tt.theme_font_files {
			assert os.exists(os.join_path(tt.theme_dir, f))
		}
		mut paths := []string{}
		for state in ['focused', ''] {
			states := if state == '' { []string{} } else { [state] }
			vars := w.resolve_vars(tt.theme_vars, states, map[string]string{})
			for ele in w.elements {
				if ele.kind == .image {
					paths << substitute(ele.path, vars)
				}
			}
		}
		tb := tt.toolbar_themes[0]
		for ele in tb.elements {
			if ele.kind == .image || ele.kind == .pattern {
				paths << ele.path
			}
		}
		assert tb.has_workspace_buttons
		for ele in tb.workspace_buttons.elements {
			if ele.kind == .image {
				paths << ele.path
			}
		}
		for p in paths {
			assert os.exists(os.join_path(tt.theme_dir, p)), '${pal}: missing ${p}'
		}
		assert 'art/focused/title.png' in paths && 'art/unfocused/title.png' in paths
		assert 'art/btn-close-hover.png' in paths && 'art/ws-active.png' in paths
	}
}

fn test_toolbar_align_and_auto_width_and_fill() {
	mut tt := TestTheme{}
	parse_theme_into(mut tt,
		'[[windows]]\n[[toolbars]]\nheight = 30\nwidth = 200\nalign = "center"\nauto_width = true\n[toolbars.meter]\ntype = "solid"\nfill = "$cpu"\nfore = "#00c000"\n')!
	sec := tt.toolbar_themes[0]
	assert sec.height == 30 && sec.width == 200 && sec.align == 'center' && sec.auto_width
	assert sec.elements[0].fill == '$cpu'
	r := apply_fill('40', ScreenRect{10, 0, 100, 8}, map[string]string{})
	assert r == ScreenRect{10, 0, 40, 8}
	r2 := apply_fill('$cpu', ScreenRect{0, 0, 80, 8}, {
		'cpu': '25'
	})
	assert r2.width == 20
}

fn test_geo55_theme_loads_and_its_art_exists() {
	path := os.join_path(@VMODROOT, 'themes', 'geo55', 'theme.toml')
	mut tt := TestTheme{}
	load_theme_into(mut tt, path)!
	// one window theme, two floating bands pinned to monitor 0 (left and right)
	assert tt.window_themes.len == 1 && tt.toolbar_themes.len == 2
	w := tt.window_themes[0]
	assert w.frame_insets() == Insets{3, 29, 4, 4}
	assert w.collapsed_height == 28
	assert !w.shaped
	assert tt.toolbar_themes[0].height == 30 && tt.toolbar_themes[0].align == 'left'
	assert tt.toolbar_themes[1].align == 'right' && tt.toolbar_themes[1].auto_width
	for f in tt.theme_font_files {
		assert os.exists(os.join_path(tt.theme_dir, f))
	}
	// the window frame art switches with focus: both variants exist
	dark := substitute(w.elements[0].path, w.resolve_vars(tt.theme_vars, []string{},
		map[string]string{}))
	lit := substitute(w.elements[0].path, w.resolve_vars(tt.theme_vars, ['focused'],
		map[string]string{}))
	assert dark == 'art/dk-frame.png' && lit == 'art/frame.png'
	// every image and pattern element (workspace buttons included), with its
	// variables resolved, points at a file that exists
	mut sections := []ThemeSection{}
	sections << tt.window_themes
	sections << tt.toolbar_themes
	for sec in sections {
		vars := sec.resolve_vars(tt.theme_vars, []string{}, map[string]string{})
		mut paths := []string{}
		for ele in sec.elements {
			if ele.kind in [.image, .pattern] {
				paths << substitute(ele.path, vars)
			}
		}
		if sec.has_workspace_buttons {
			for ele in sec.workspace_buttons.elements {
				if ele.kind in [.image, .pattern] {
					paths << substitute(ele.path, vars)
				}
			}
		}
		for p in paths {
			assert os.exists(os.join_path(tt.theme_dir, p)), 'missing ${p}'
		}
	}
}

fn test_theme_parse_rejects_unknown_values() {
	bad := [
		'[[toolbars]]\n[toolbars.a]\ntype = "solid"\nwhen = "focsued"\n',
		'[[toolbars]]\n[toolbars.a]\ntype = "solid"\nunless = "collapsed,activ"\n',
		'[[toolbars]]\n[toolbars.a]\ntype = "image"\naction = "minimise"\n',
		'[[toolbars]]\n[toolbars.a]\ntype = "text"\nalign = "middel"\n',
		'[[toolbars]]\n[toolbars.a]\ntype = "text"\ntransform = "shout"\n',
		'background_scale = "zoom"\n[[windows]]\n',
		'background_filter = "smooth"\n[[windows]]\n',
	]
	for text in bad {
		mut tt := TestTheme{}
		parse_theme_into(mut tt, text) or {
			assert err.msg() != ''
			continue
		}
		assert false, 'theme parsed but should not have: ${text}'
	}
}

// every theme bundled in the tree loads (this also exercises the parse-time
// validation: any unknown key or value in a shipped theme fails or warns
// here rather than at a user's desktop): default, bluesteel, corpo, fossils,
// geo55, pinkline and the four fresh-breath palettes.
fn test_bundled_themes_load() {
	root := @VMODROOT
	mut paths := []string{}
	for d in os.ls(os.join_path(root, 'themes')) or { []string{} } {
		dir := os.join_path(root, 'themes', d)
		if os.is_file(os.join_path(dir, 'theme.toml')) {
			paths << os.join_path(dir, 'theme.toml')
		} else {
			for sd in os.ls(dir) or { []string{} } {
				p := os.join_path(dir, sd, 'theme.toml')
				if os.is_file(p) {
					paths << p
				}
			}
		}
	}
	assert paths.len == 10, 'the bundled set: default, bluesteel, corpo, fossils, geo55, pinkline + 4 palettes'
	for path in paths {
		mut tt := TestTheme{}
		load_theme_into(mut tt, path)!
		assert tt.window_themes.len >= 1, path
		assert tt.toolbar_themes.len >= 1, path
	}
}

fn test_toolbar_position_and_auto_hide_settings() {
	mut tt := TestTheme{}
	parse_theme_into(mut tt, '[[windows]]
[[toolbars]]
position = "bottom"
auto_hide = true
hidden_height = 7
reveal_ms = 800
[toolbars.line]
type = "solid"
when = "hidden"
') or {
		panic(err)
	}
	sec := tt.toolbar_themes[0]
	assert sec.position == 'bottom'
	assert sec.auto_hide
	assert sec.hidden_height == 7
	assert sec.reveal_ms == 800
	assert sec.elements[0].active_in(['hidden'])
	assert !sec.elements[0].active_in(['focused'])
	assert ThemeSection{}.position == 'top'
	assert !ThemeSection{}.auto_hide
	if _ := parse_theme_into(mut tt, '[[windows]]
[[toolbars]]
position = "left"
') {
		assert false, 'position = "left" should be refused'
	}
}
