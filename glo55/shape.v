module glo55

// shape.v - window shapes. E16 frames are shaped: pixels no part of the border
// covers (transparent corners of trim images) are cut out of the frame window
// so the desktop shows through. A theme asks for this with `shaped = true`
// in its [[windows]] entry; the shape is the union of everything the frame's
// elements actually paint (image alpha counts) plus the client area.

// ShapeMask is a one-byte-per-pixel coverage map of a frame.
pub struct ShapeMask {
pub:
	width  int
	height int
pub mut:
	cover []u8
}

pub fn new_shape_mask(w int, h int) ShapeMask {
	return ShapeMask{
		width:  w
		height: h
		cover:  []u8{len: w * h}
	}
}

// mark_rect covers a whole rectangle (clipped to the mask).
pub fn (mut m ShapeMask) mark_rect(r ScreenRect) {
	clip := r.intersect(ScreenRect{0, 0, u32(m.width), u32(m.height)})
	for y in int(clip.y) .. int(clip.y) + int(clip.height) {
		for x in int(clip.x) .. int(clip.x) + int(clip.width) {
			m.cover[y * m.width + x] = 1
		}
	}
}

// shape_alpha_threshold: image pixels at least this opaque are part of the
// shape (the soft anti-aliased fringe below it is cut away, as E16 does).
pub const shape_alpha_threshold = 128

// mark_image covers the pixels an image (drawn into `rect` with `mode`)
// paints (alpha >= shape_alpha_threshold).
pub fn (mut m ShapeMask) mark_image(rect ScreenRect, img LoadedImage, mode ScaleMode, slice [4]int) {
	clip := rect.intersect(ScreenRect{0, 0, u32(m.width), u32(m.height)})
	for y in int(clip.y) .. int(clip.y) + int(clip.height) {
		for x in int(clip.x) .. int(clip.x) + int(clip.width) {
			sx, sy := scale_source(x, y, rect, img.width, img.height, mode, slice) or { continue }
			if unsafe { img.data[(sy * img.width + sx) * 4 + 3] } >= shape_alpha_threshold {
				m.cover[y * m.width + x] = 1
			}
		}
	}
}

// pack produces the X bitmap form: LSB-first bits, rows padded to bytes.
pub fn (m &ShapeMask) pack() []u8 {
	stride := (m.width + 7) / 8
	mut out := []u8{len: stride * m.height}
	for y in 0 .. m.height {
		for x in 0 .. m.width {
			if m.cover[y * m.width + x] != 0 {
				out[y * stride + x / 8] |= u8(1) << u8(x % 8)
			}
		}
	}
	return out
}
