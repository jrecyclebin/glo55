module x11

fn test_valid_utf8_passes_through_untouched() {
	s := 'Café — naïve 日本語 Ελληνικά ✓ ★ 🙂'
	assert sanitize_title(s.bytes()) == s
}

fn test_invalid_bytes_become_replacement_characters() {
	// a Latin-1 "é" (0xe9) on its own is not UTF-8; neither is a stray continuation byte
	assert sanitize_title([u8(`C`), 0xe9, `!`]) == 'C\xef\xbf\xbd!'
	assert sanitize_title([u8(0x80), `a`]) == '\xef\xbf\xbda'
	// truncated 3-byte sequence at the end
	assert sanitize_title([u8(`a`), 0xe6, 0x97]) == 'a\xef\xbf\xbd\xef\xbf\xbd'
	// overlong "/" (C0 AF), surrogate (ED A0 80) and > U+10FFFF (F5 ..) are rejected
	assert sanitize_title([u8(0xc0), 0xaf]) == '\xef\xbf\xbd\xef\xbf\xbd'
	assert sanitize_title([u8(0xed), 0xa0, 0x80]).count('\xef\xbf\xbd') == 3
	assert sanitize_title([u8(0xf5), 0x80, 0x80, 0x80]).count('\xef\xbf\xbd') == 4
}

fn test_control_characters_become_spaces() {
	assert sanitize_title('a\nb\tc\x1b[0md'.bytes()) == 'a b c [0md'
	assert sanitize_title('x\xc2\x85y'.bytes()) == 'x y' // C1 control U+0085
}

fn test_latin1_is_converted_to_utf8() {
	// "Café naïve" in ISO 8859-1
	b := [u8(`C`), `a`, `f`, 0xe9, ` `, `n`, `a`, 0xef, `v`, `e`]
	assert latin1_to_utf8(b) == 'Café naïve'
	assert latin1_to_utf8([u8(0xa9), 0xff]) == '©ÿ'
}

fn test_group_runs_merges_neighbours_with_the_same_font() {
	runes := 'ab日本c'.runes()
	runs := group_runs(runes, [0, 0, 1, 1, 0])
	assert runs.len == 3
	assert runs[0].text == 'ab' && runs[0].font == 0
	assert runs[1].text == '日本' && runs[1].font == 1
	assert runs[2].text == 'c' && runs[2].font == 0
}

fn test_group_runs_keeps_whole_codepoints() {
	// every run must be valid UTF-8 and the runs must add up to the input
	s := 'Café — naïve 日本語 Ελληνικά ✓ ★ 🙂'
	runes := s.runes()
	mut fonts := []int{}
	for r in runes {
		fonts << if int(r) > 0x2000 { 1 } else { 0 }
	}
	runs := group_runs(runes, fonts)
	mut joined := ''
	for run in runs {
		assert sanitize_title(run.text.bytes()) == run.text
		joined += run.text
	}
	assert joined == s
}

fn test_neutral_runes_follow_the_previous_font() {
	// a variation selector / ZWJ / combining accent stays with its base letter's font
	runes := ['✓'.runes()[0], rune(0xfe0f), rune(0x200d), `a`, rune(0x301)]
	runs := group_runs(runes, [1, 0, 0, 0, 1])
	assert runs.len == 2
	assert runs[0].font == 1 && runs[0].text.runes().len == 3
	assert runs[1].font == 0 && runs[1].text.runes().len == 2
	assert is_neutral(rune(0x200d)) && is_neutral(rune(0xfe0f)) && !is_neutral(`a`)
}

fn test_group_runs_of_nothing_is_nothing() {
	assert group_runs([]rune{}, []int{}).len == 0
}

fn test_requested_family_and_matching() {
	assert requested_family('Noto Sans:pixelsize=12') == 'Noto Sans'
	assert requested_family('Noto Sans') == 'Noto Sans'
	assert family_matches('Noto Sans', 'noto sans')
	assert family_matches('Foo, Noto Sans:x', 'Noto Sans') == false // the pattern tail is not part of the family
	assert family_matches(requested_family('Foo, Noto Sans:pixelsize=9'), 'Noto Sans')
	assert !family_matches('Noto Sans Regular', 'DejaVu Sans')
	assert is_generic_family('monospace') && is_generic_family('Sans-Serif')
	assert !is_generic_family('Noto Sans')
}

fn test_a_style_name_glued_to_the_family_is_split_off() {
	assert split_trailing_style('Noto Sans Regular:pixelsize=12')? == 'Noto Sans:style=Regular:pixelsize=12'
	assert split_trailing_style('Noto Sans Bold Italic')? == 'Noto Sans:style=Bold Italic'
	assert split_trailing_style('Noto Sans:pixelsize=12') == none
	assert split_trailing_style('Regular') == none
	assert split_trailing_style('A, B Bold') == none
}
