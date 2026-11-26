module glo55

import x11

// Tests for the colour and gradient maths (no X server needed).

fn test_parse_color_forms() {
	assert parse_color('#ff8000')? == Rgba{255, 128, 0, 255}
	assert parse_color('#FF8000')? == Rgba{255, 128, 0, 255}
	assert parse_color('#f80')? == Rgba{255, 136, 0, 255}
	assert parse_color('#11223344')? == Rgba{0x11, 0x22, 0x33, 0x44}
	assert parse_color('#00000000')?.a == 0
	assert parse_color(' #123456 ')? == Rgba{0x12, 0x34, 0x56, 255}
}

fn test_parse_color_rejects_garbage() {
	for bad in ['', 'red', '#12', '#12345', '#gg0000', 'ff0000', '#1234567'] {
		assert parse_color(bad) == none
	}
}

fn test_lerp_color_endpoints_and_midpoint() {
	a := Rgba{0, 0, 0, 255}
	b := Rgba{200, 100, 50, 255}
	assert lerp_color(a, b, 0) == a
	assert lerp_color(a, b, 1) == b
	assert lerp_color(a, b, 0.5) == Rgba{100, 50, 25, 255}
	// t outside 0..1 is clamped
	assert lerp_color(a, b, -3) == a
	assert lerp_color(a, b, 9) == b
}

fn test_normalize_degrees() {
	assert normalize_degrees(0) == 0
	assert normalize_degrees(360) == 0
	assert normalize_degrees(450) == 90
	assert normalize_degrees(-90) == 270
}

fn test_gradient_direction_zero_is_left_to_right() {
	assert gradient_t(0, 5, 100, 10, 0) == 0
	assert gradient_t(99, 5, 100, 10, 0) == 1
	assert gradient_t(0, 0, 100, 10, 180) == 1
	assert gradient_t(99, 0, 100, 10, 180) == 0
	// rows don't matter horizontally
	assert gradient_t(40, 0, 100, 10, 0) == gradient_t(40, 9, 100, 10, 0)
}

fn test_gradient_direction_90_is_top_to_bottom() {
	assert gradient_t(7, 0, 100, 10, 90) == 0
	assert gradient_t(7, 9, 100, 10, 90) == 1
	assert gradient_t(0, 9, 100, 10, 270) == 0
	assert gradient_t(0, 0, 100, 10, 270) == 1
}

fn test_gradient_diagonal_runs_corner_to_corner() {
	// 45 degrees: top-left is the start, bottom-right the end, monotonic between
	tl := gradient_t(0, 0, 100, 100, 45)
	br := gradient_t(99, 99, 100, 100, 45)
	mid := gradient_t(50, 50, 100, 100, 45)
	assert tl < 0.02
	assert br > 0.98
	assert mid > 0.45 && mid < 0.55
	assert gradient_t(10, 10, 100, 100, 45) < gradient_t(60, 60, 100, 100, 45)
}

fn test_gradient_degenerate_sizes() {
	assert gradient_t(0, 0, 1, 1, 0) == 0
	assert gradient_t(0, 0, 1, 1, 90) == 0
	assert gradient_t(0, 0, 0, 0, 33) == 0
}

fn test_blend_respects_alpha() {
	dst := Rgba{100, 100, 100, 255}
	assert blend(dst, Rgba{200, 0, 0, 255}) == Rgba{200, 0, 0, 255}
	assert blend(dst, Rgba{200, 0, 0, 0}) == dst
	half := blend(Rgba{0, 0, 0, 255}, Rgba{255, 255, 255, 128})
	assert half.r >= 127 && half.r <= 129
	assert half.a == 255
}

fn test_tile_source_single_image_is_clipped_to_its_size() {
	r := ScreenRect{10, 10, 100, 100}
	x0, y0 := tile_source(10, 10, r, 4, 3, false)?
	assert x0 == 0 && y0 == 0
	x1, y1 := tile_source(13, 12, r, 4, 3, false)?
	assert x1 == 3 && y1 == 2
	assert !has_tile_source(14, 10, r, 4, 3, false) // right of the image
	assert !has_tile_source(10, 13, r, 4, 3, false) // below the image
	assert !has_tile_source(9, 10, r, 4, 3, false) // outside the rect
	assert !has_tile_source(10, 10, r, 0, 0, false) // empty image
}

fn test_tile_source_pattern_repeats() {
	r := ScreenRect{5, 5, 50, 50}
	a, b := tile_source(5, 5, r, 4, 4, true)?
	assert a == 0 && b == 0
	c, d := tile_source(9, 5, r, 4, 4, true)? // wrapped around
	assert c == 0 && d == 0
	e, f := tile_source(11, 14, r, 4, 4, true)?
	assert e == 2 && f == 1
	assert !has_tile_source(55, 5, r, 4, 4, true) // outside the rect
}

fn test_rect_intersect() {
	a := ScreenRect{0, 0, 100, 100}
	assert a.intersect(ScreenRect{50, 50, 100, 100}) == ScreenRect{50, 50, 50, 50}
	assert a.intersect(ScreenRect{-20, -20, 30, 30}) == ScreenRect{0, 0, 10, 10}
	assert a.intersect(ScreenRect{200, 200, 10, 10}).width == 0
}

fn test_scale_source_stretch_maps_corners_and_middle() {
	r := ScreenRect{10, 20, 100, 40}
	no := [0, 0, 0, 0]!
	x0, y0 := scale_source(10, 20, r, 10, 4, .stretch, no)?
	assert x0 == 0 && y0 == 0
	x1, y1 := scale_source(109, 59, r, 10, 4, .stretch, no)?
	assert x1 == 9 && y1 == 3
	x2, _ := scale_source(60, 30, r, 10, 4, .stretch, no)?
	assert x2 == 5 // halfway across -> halfway through the image
	assert !has_scale_source(9, 20, r, 10, 4, .stretch, no) // outside the rect
	// a 1-pixel-wide stretch target never divides by zero
	x3, _ := scale_source(0, 0, ScreenRect{0, 0, 1, 1}, 8, 8, .stretch, no)?
	assert x3 == 0
}

fn test_scale_source_slice_keeps_edges_unscaled() {
	// 20x20 image with 4px edges stretched to 100x60
	r := ScreenRect{0, 0, 100, 60}
	s := [4, 4, 4, 4]!
	for dx in 0 .. 4 {
		sx, _ := scale_source(dx, 30, r, 20, 20, .slice, s)?
		assert sx == dx // left edge: 1:1
	}
	for dx in 96 .. 100 {
		sx, _ := scale_source(dx, 30, r, 20, 20, .slice, s)?
		assert sx == 20 - (100 - dx) // right edge: 1:1 from the far side
	}
	_, sy := scale_source(50, 59, r, 20, 20, .slice, s)?
	assert sy == 19
	// the middle is stretched but stays within the middle band
	mx, my := scale_source(50, 30, r, 20, 20, .slice, s)?
	assert mx >= 4 && mx < 16 && my >= 4 && my < 16
	// too small to hold both edges: falls back to a plain stretch
	tx, _ := scale_source(3, 0, ScreenRect{0, 0, 6, 6}, 20, 20, .slice, [4, 4, 4, 4]!)?
	assert tx == 10
}

fn test_scale_source_none_and_tile_match_tile_source() {
	r := ScreenRect{5, 5, 50, 50}
	no := [0, 0, 0, 0]!
	a, b := scale_source(11, 14, r, 4, 4, .tile, no)?
	assert a == 2 && b == 1
	assert !has_scale_source(20, 20, r, 4, 4, .none, no)
}

fn test_shape_mask_marks_rects_and_packs_lsb_first() {
	mut m := new_shape_mask(10, 2)
	m.mark_rect(ScreenRect{1, 0, 3, 1}) // x = 1..3 on row 0
	m.mark_rect(ScreenRect{8, 1, 50, 50}) // clipped to the mask: x = 8..9 on row 1
	bits := m.pack()
	assert bits.len == 4 // 2 bytes per row
	assert bits[0] == 0b0000_1110
	assert bits[1] == 0
	assert bits[2] == 0
	assert bits[3] == 0b0000_0011 // x=8, x=9 -> bits 0 and 1 of the second byte
}

fn test_shape_mask_image_alpha_decides_coverage() {
	// 2x1 image: one opaque pixel, one nearly transparent (below the threshold)
	data := [u8(1), 2, 3, 255, 4, 5, 6, 100]
	img := LoadedImage{
		width:  2
		height: 1
		data:   data.data
	}
	mut m := new_shape_mask(6, 1)
	m.mark_image(ScreenRect{0, 0, 6, 1}, img, .stretch, [0, 0, 0, 0]!)
	// stretched 3x: the left half (opaque) is covered, the right half is not
	assert m.cover == [u8(1), 1, 1, 0, 0, 0]
}

// helpers: asserting `== none` on an option isn't supported by older V versions
fn has_tile_source(px int, py int, rect ScreenRect, iw int, ih int, tiled bool) bool {
	_, _ := tile_source(px, py, rect, iw, ih, tiled) or { return false }
	return true
}

fn has_scale_source(px int, py int, rect ScreenRect, iw int, ih int, mode ScaleMode, slice [4]int) bool {
	_, _ := scale_source(px, py, rect, iw, ih, mode, slice) or { return false }
	return true
}

// ---- rune-safe truncation (no X server: every character is 10px wide, the ellipsis too)

struct FixedMeasure {}

fn (m FixedMeasure) width(s string) int {
	return s.runes().len * 10
}

fn test_fit_with_returns_text_that_already_fits() {
	assert fit_with(FixedMeasure{}, 'Café', 40) == 'Café'
}

fn test_fit_with_never_cuts_inside_a_multibyte_character() {
	s := 'Café — naïve 日本語 Ελληνικά ✓ ★ 🙂'
	for w in 0 .. 330 {
		out := fit_with(FixedMeasure{}, s, w)
		// valid UTF-8 whatever the width: round-trips through runes unchanged
		assert out.runes().string() == out
		assert out.bytes().len == out.len
		assert out.runes().len * 10 <= w || out == ''
	}
}

fn test_fit_with_keeps_as_many_characters_as_fit() {
	// 10px each: 7 characters fit in 70 = 6 kept + the ellipsis
	assert fit_with(FixedMeasure{}, '日本語のテキストです', 70) == '日本語のテキ…'
	assert fit_with(FixedMeasure{}, 'abcdef', 10) == '…'
	assert fit_with(FixedMeasure{}, 'abcdef', 9) == ''
}

fn test_fit_with_does_not_strand_a_combining_mark() {
	// "e" + U+0301 (combining acute): cutting between them would drop the accent
	// but keep the letter looking wrong, so the cut moves before the letter pair
	s := 'abe\u0301cdef'
	out := fit_with(FixedMeasure{}, s, 50) // 4 kept + ellipsis
	assert out == 'ab…' || out == 'abe\u0301…'
}

fn test_opaque_slice_scaling_is_cached_by_source_and_size() {
	// Opaque 9-slice artwork keeps its native pixels between frame repaints.
	// Repeating the same request must reuse the array, not rescale it.
	px := [u8(0), 0, 0, 255, 119, 119, 119, 255, 255, 255, 255, 255]
	img := LoadedImage{
		width:  3
		height: 1
		data:   px.data
		opaque: true
		source: 'frame.png'
	}
	mut d := DrawingContext{
		conn: unsafe { nil }
		tc:   x11.TrueColorInfo{
			red_shift:   16
			green_shift: 8
			blue_shift:  0
			red_bits:    8
			green_bits:  8
			blue_bits:   8
		}
	}
	slice := [1, 0, 1, 0]!
	first := d.scaled_opaque(img, ScreenRect{0, 0, 4, 2}, .slice, slice)
	assert first.pixels == [u32(0), 0x777777, 0x777777, 0xffffff, 0, 0x777777, 0x777777, 0xffffff]
	second := d.scaled_opaque(img, ScreenRect{10, 20, 4, 2}, .slice, slice)
	assert first.pixels.data == second.pixels.data
	assert d.scaled_images.len == 1
	wider := d.scaled_opaque(img, ScreenRect{0, 0, 6, 1}, .slice, slice)
	assert wider.pixels == [u32(0), 0x777777, 0x777777, 0x777777, 0x777777, 0xffffff]
	assert d.scaled_images.len == 2
}

fn test_cover_rect_keeps_aspect_and_centres() {
	// wide screen, squarer image: scaled to the width, overflow cropped top and bottom
	assert cover_rect(1000, 500, 500, 477) == ScreenRect{0, -227, 1000, 954}
	// tall screen: scaled to the height, cropped left and right
	assert cover_rect(500, 1000, 500, 477) == ScreenRect{-274, 0, 1048, 1000}
	// same aspect: exact fit
	assert cover_rect(1000, 500, 100, 50) == ScreenRect{0, 0, 1000, 500}
}

fn test_scale_bilinear_blends_neighbours_and_keeps_flat_colour() {
	// 2x1: black | white, scaled to 4x1: the middle pixels are greys
	px := [u8(0), 0, 0, 255, 255, 255, 255, 255]
	img := LoadedImage{
		width:  2
		height: 1
		data:   px.data
	}
	out := scale_bilinear(img, 4, 1)
	assert out[0] == 0 // the left edge is pure black
	assert out[12] == 255 // the right edge is pure white
	assert out[4] > 0 && out[4] < 128 // between them it ramps
	assert out[8] > 128 && out[8] < 255
	assert out[7] == 255 && out[3] == 255 // opaque stays opaque
	// a flat image stays flat at any size
	flat := [u8(10), 20, 30, 255, 10, 20, 30, 255, 10, 20, 30, 255, 10, 20, 30, 255]
	f := scale_bilinear(LoadedImage{ width: 2, height: 2, data: flat.data }, 5, 3)
	for i in 0 .. 15 {
		assert f[i * 4] == 10 && f[i * 4 + 1] == 20 && f[i * 4 + 2] == 30 && f[i * 4 + 3] == 255
	}
}

fn test_scale_bilinear_does_not_bleed_transparent_colour() {
	// opaque red next to a fully transparent (black) pixel: the blend stays red
	px := [u8(255), 0, 0, 255, 0, 0, 0, 0]
	out := scale_bilinear(LoadedImage{ width: 2, height: 1, data: px.data }, 4, 1)
	assert out[4] == 255 && out[5] == 0 && out[6] == 0
	assert out[7] > 0 && out[7] < 255
}
