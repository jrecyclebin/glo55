module glo55

// Tests for the toolbar workspace buttons: theme parsing, the legacy
// `$workspaces` conversion, states, and the automatic layout / hit testing.
// No X server needed.
import os

struct ButtonsTestTheme {
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

fn test_layout_aligns_left_center_right() {
	region := ScreenRect{100, 0, 200, 20}
	w := [30, 40, 30]
	left := layout_buttons(region, w, 5, 'left', 0)
	assert left.len == 3
	assert left[0] == ScreenRect{100, 0, 30, 20}
	assert left[1] == ScreenRect{135, 0, 40, 20}
	assert left[2] == ScreenRect{180, 0, 30, 20}
	// total = 100 + 10 gaps = 110, so 90 spare
	right := layout_buttons(region, w, 5, 'right', 0)
	assert right[0].x == 190
	assert right[2].right() == 300
	centre := layout_buttons(region, w, 5, 'center', 0)
	assert centre[0].x == 145
}

fn test_layout_negative_spacing_overlaps_up_to_half_the_narrowest() {
	region := ScreenRect{0, 0, 300, 20}
	r := layout_buttons(region, [40, 40, 40], -10, 'right', 0)
	assert r[1].x == r[0].x + 30
	assert r[2].right() == 300
	capped := layout_buttons(region, [40, 20, 40], -50, 'left', 0)
	assert capped[1].x == 30 // overlap capped at 20 / 2
}

fn test_layout_follows_the_workspace_count() {
	region := ScreenRect{0, 0, 300, 20}
	three := layout_buttons(region, [20, 20, 20], 2, 'right', 0)
	ten := layout_buttons(region, [20, 20, 20, 20, 20, 20, 20, 20, 20, 20], 2, 'right', 0)
	assert three.len == 3 && ten.len == 10
	assert three[2].right() == 300
	assert ten[9].right() == 300
	assert ten[0].x == 300 - (10 * 20 + 9 * 2)
	assert layout_buttons(region, []int{}, 2, 'left', 0).len == 0
}

fn test_layout_shrinks_buttons_that_do_not_fit() {
	region := ScreenRect{10, 0, 100, 20}
	r := layout_buttons(region, [60, 60, 60], 2, 'left', 0)
	assert r.len == 3
	assert r[0].x == 10
	// nothing sticks out of the region, and the buttons do not overlap
	assert r[2].right() <= 110
	assert r[1].x >= r[0].right() && r[2].x >= r[1].right()
	// far too many for the width: still one pixel each at least, inside the region
	tiny := layout_buttons(ScreenRect{0, 0, 5, 20}, [10, 10, 10, 10, 10, 10], 3, 'left', 0)
	assert tiny.len == 6
	for b in tiny {
		assert b.width >= 1
	}
}

fn test_layout_button_height_is_centred() {
	r := layout_buttons(ScreenRect{0, 2, 100, 20}, [30], 0, 'left', 12)
	assert r[0].height == 12
	assert r[0].y == 2 + (20 - 12) / 2
	full := layout_buttons(ScreenRect{0, 2, 100, 20}, [30], 0, 'left', 0)
	assert full[0].y == 2 && full[0].height == 20
	// a button_height bigger than the region is capped to it
	big := layout_buttons(ScreenRect{0, 2, 100, 20}, [30], 0, 'left', 50)
	assert big[0].height == 20
}

fn test_button_at_hit_testing() {
	rects := layout_buttons(ScreenRect{0, 0, 200, 20}, [30, 30], 4, 'left', 0)
	assert button_at(rects, 0, 5) == 0
	assert button_at(rects, 29, 19) == 0
	assert button_at(rects, 30, 5) == -1 // the gap
	assert button_at(rects, 34, 5) == 1
	assert button_at(rects, 64, 5) == -1
	assert button_at(rects, 10, 20) == -1
	assert button_at([]ScreenRect{}, 1, 1) == -1
}

fn test_button_states_and_exclusive_hover_pressed() {
	assert button_states(false, false, false, false) == ['normal']
	assert button_states(false, true, false, false) == ['occupied', 'normal']
	assert button_states(true, false, false, false) == ['active']
	assert button_states(true, true, true, false) == ['active', 'occupied', 'hover']
	// pressed wins over hover
	assert button_states(false, false, true, true) == ['pressed']
}

const buttons_theme = '
[vars]
fore = "#aaaaaa"

[[windows]]

[[toolbars]]
height = 22

[toolbars.focused]
fore = "#ffffff"

[toolbars.title]
type = "text"
content = "$title"

[toolbars.workspace_buttons]
left = { edge = "left", offset = 100 }
right = { edge = "right", offset = -8 }
top = { edge = "top", offset = 2 }
bottom = { edge = "bottom", offset = -2 }
align = "right"
spacing = 3
padding = 9
min_width = 30
max_width = 120
button_height = 16

[toolbars.workspace_buttons.hover]
fore = "#00ff00"

[toolbars.workspace_buttons.active]
fore = "#ff0000"

[toolbars.workspace_buttons.00_face]
type = "solid"
fore = "$fore"
when = "active,hover"

[toolbars.workspace_buttons.01_label]
type = "text"
content = "$workspace"
font = "mono"
size = 11
unless = "pressed"
'

fn test_parse_workspace_buttons_section() {
	mut tt := ButtonsTestTheme{}
	parse_theme_into(mut tt, buttons_theme)!
	sec := tt.toolbar_themes[0]
	assert sec.has_workspace_buttons
	// the bar's own elements do not include the button template
	assert sec.elements.map(it.name) == ['title']
	wb := sec.workspace_buttons
	assert wb.elements.map(it.name) == ['00_face', '01_label']
	assert wb.align == 'right'
	assert wb.spacing == 3 && wb.padding == 9
	assert wb.min_width == 30 && wb.max_width == 120 && wb.button_height == 16
	assert wb.area.left.offset == 100 && wb.area.right.edge == .right && wb.area.right.offset == -8
	assert wb.states['hover']['fore'] == '#00ff00'
	assert wb.states['active']['fore'] == '#ff0000'
	// the region keys are positions, not elements or states
	assert wb.elements.len == 2
}

fn test_button_vars_layer_over_the_toolbar_vars() {
	mut tt := ButtonsTestTheme{}
	parse_theme_into(mut tt, buttons_theme)!
	wb := tt.toolbar_themes[0].workspace_buttons
	base := {
		'fore': '#aaaaaa'
		'time': '12:00'
	}
	rt := {
		'workspace': 'web'
		'number':    '2'
	}
	n := wb.resolve_vars(base, ['normal'], rt)
	assert n['fore'] == '#aaaaaa' && n['workspace'] == 'web' && n['time'] == '12:00'
	assert wb.resolve_vars(base, ['active'], rt)['fore'] == '#ff0000'
	assert wb.resolve_vars(base, ['hover'], rt)['fore'] == '#00ff00'
	// hover is applied after active, so it wins when both are on
	assert wb.resolve_vars(base, ['active', 'hover'], rt)['fore'] == '#00ff00'
	// the bar's variables are not modified
	assert base['fore'] == '#aaaaaa'
}

fn test_button_width_uses_padding_min_and_max() {
	mut tt := ButtonsTestTheme{}
	parse_theme_into(mut tt, buttons_theme)!
	wb := tt.toolbar_themes[0].workspace_buttons
	assert wb.button_width(10) == 30 // 10 + 18 = 28 -> min 30
	assert wb.button_width(20) == 38
	assert wb.button_width(500) == 120 // max
}

fn test_label_element_depends_on_the_state() {
	mut tt := ButtonsTestTheme{}
	parse_theme_into(mut tt, buttons_theme)!
	wb := tt.toolbar_themes[0].workspace_buttons
	l := wb.label_element(['normal']) or { panic('no label') }
	assert l.name == '01_label'
	assert wb.label_element(['pressed']) == none
}

fn test_when_and_unless_take_comma_lists() {
	both := Element{
		when: ['active', 'hover']
	}
	assert both.active_in(['active', 'hover', 'occupied'])
	assert !both.active_in(['active'])
	assert !both.active_in(['hover'])
	any := Element{
		unless: ['active', 'pressed']
	}
	assert any.active_in(['hover'])
	assert !any.active_in(['active'])
	assert !any.active_in(['pressed', 'hover'])
	assert any.active_in([])
}

fn test_theme_fonts_include_button_fonts() {
	mut tt := ButtonsTestTheme{}
	parse_theme_into(mut tt, buttons_theme)!
	assert 'mono:pixelsize=11' in theme_get_fonts(tt)
}

const legacy_theme = '
[[windows]]

[[toolbars]]
height = 24

[toolbars.logo]
type = "solid"
fore = "#ff0000"

[toolbars.workspaces]
type = "text"
content = "$workspaces"
fore = "#abcdef"
font = "monospace"
size = 13
left = { edge = "left", offset = 34 }
right = { edge = "left", offset = 420 }

[toolbars.title]
type = "text"
content = "$title"
'

fn test_old_workspaces_text_becomes_a_clickable_row() {
	mut tt := ButtonsTestTheme{}
	parse_theme_into(mut tt, legacy_theme)!
	sec := tt.toolbar_themes[0]
	assert sec.has_workspace_buttons
	// the $workspaces element is gone from the bar, the rest is untouched
	assert sec.elements.map(it.name) == ['logo', 'title']
	wb := sec.workspace_buttons
	assert wb.area.left.offset == 34 && wb.area.right.offset == 420
	assert wb.elements.len == 2
	// plain names, with the current workspace in brackets, same colour and font
	idle := wb.label_element(['normal']) or { panic('no label') }
	cur := wb.label_element(['active']) or { panic('no label') }
	assert idle.content == '\$workspace' && cur.content == '[\$workspace]'
	assert idle.fore == '#abcdef' && cur.fore == '#abcdef'
	assert idle.size == 13 && cur.font == 'monospace'
	assert wb.padding == 0
	// a theme without any workspace text keeps having no buttons
	mut plain := ButtonsTestTheme{}
	parse_theme_into(mut plain, '[[windows]]\n[[toolbars]]\nheight = 20\n')!
	assert !plain.toolbar_themes[0].has_workspace_buttons
}

fn test_bad_align_is_an_error() {
	mut tt := ButtonsTestTheme{}
	parse_theme_into(mut tt,
		'[[windows]]\n[[toolbars]]\n[toolbars.workspace_buttons]\nalign = "middle"\n') or {
		assert err.msg().contains('align')
		return
	}
	assert false
}

fn test_shipped_themes_parse_with_buttons() {
	root := os.dir(os.dir(@FILE))
	for rel in ['themes/default/theme.toml', 'themes/bluesteel/theme.toml'] {
		mut tt := ButtonsTestTheme{}
		load_theme_into(mut tt, os.join_path(root, rel))!
		sec := tt.toolbar_themes[0]
		assert sec.has_workspace_buttons
		assert sec.workspace_buttons.elements.len >= 2
	}
}
