module x11

// text.v - pure text helpers (no X calls, unit tested): turning window title
// bytes of any encoding into clean UTF-8, and splitting text into runs that
// are drawn with one font each.

// replacement is U+FFFD, shown for bytes that are not valid UTF-8.
const replacement = '\xef\xbf\xbd'

// utf8_seq_len returns the length of the valid UTF-8 sequence that starts at
// b[i], or 0 when the bytes there are not valid UTF-8 (stray continuation or
// lead bytes, truncated sequences, overlong forms, surrogates, > U+10FFFF).
fn utf8_seq_len(b []u8, i int) int {
	c := b[i]
	if c < 0x80 {
		return 1
	}
	mut need := 0
	mut lo := u32(0)
	if c >= 0xc2 && c <= 0xdf {
		need = 1
		lo = 0x80
	} else if c >= 0xe0 && c <= 0xef {
		need = 2
		lo = 0x800
	} else if c >= 0xf0 && c <= 0xf4 {
		need = 3
		lo = 0x10000
	} else {
		return 0
	}
	if i + need >= b.len {
		return 0
	}
	mut cp := u32(c) & (u32(0x3f) >> need)
	for k in 1 .. need + 1 {
		cc := b[i + k]
		if cc & 0xc0 != 0x80 {
			return 0
		}
		cp = (cp << 6) | u32(cc & 0x3f)
	}
	if cp < lo || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff) {
		return 0
	}
	return need + 1
}

// sanitize_title turns raw title bytes into a string that is safe to hand to
// Xft: every invalid byte becomes U+FFFD (Xft stops drawing at the first
// invalid sequence), and control characters (newline, tab, ESC ...) become
// spaces so they can't break the layout of a one-line title.
pub fn sanitize_title(b []u8) string {
	mut out := []u8{cap: b.len}
	mut i := 0
	for i < b.len {
		n := utf8_seq_len(b, i)
		if n == 0 {
			out << replacement.bytes()
			i++
			continue
		}
		if n == 1 && (b[i] < 0x20 || b[i] == 0x7f) {
			out << u8(` `)
		} else if n == 2 && b[i] == 0xc2 && b[i + 1] >= 0x80 && b[i + 1] <= 0x9f {
			out << u8(` `) // C1 control
		} else {
			for k in 0 .. n {
				out << b[i + k]
			}
		}
		i += n
	}
	return out.bytestr()
}

// latin1_to_utf8 converts ISO 8859-1 bytes (the X "STRING" property type)
// to UTF-8 and cleans the result like sanitize_title.
pub fn latin1_to_utf8(b []u8) string {
	mut out := []u8{cap: b.len * 2}
	for c in b {
		if c < 0x80 {
			out << c
		} else {
			out << u8(0xc0 | (c >> 6))
			out << u8(0x80 | (c & 0x3f))
		}
	}
	return sanitize_title(out)
}

// is_neutral reports runes that have no glyph of their own and should simply
// follow whichever font the text before them uses: joiners, variation
// selectors, zero-width marks and combining marks (they attach to a base
// letter, which may come from a fallback font).
pub fn is_neutral(r rune) bool {
	c := int(r)
	return (c >= 0x200b && c <= 0x200f) || (c >= 0x2060 && c <= 0x2064)
		|| (c >= 0xfe00 && c <= 0xfe0f) || c == 0xfeff
		|| (c >= 0xe0100 && c <= 0xe01ef) || (c >= 0x0300 && c <= 0x036f)
		|| (c >= 0x1f3fb && c <= 0x1f3ff) || (c >= 0xe0020 && c <= 0xe007f)
}

// TextRun is a stretch of text drawn with one font. `font` is 0 for the
// primary font and n for the n-th fallback font.
pub struct TextRun {
pub:
	text string
	font int
}

// group_runs merges consecutive runes that use the same font into runs.
// fonts[i] is the font chosen for runes[i]; neutral runes (see is_neutral)
// follow the previous rune's font.
pub fn group_runs(runes []rune, fonts []int) []TextRun {
	mut out := []TextRun{}
	mut cur := []rune{}
	mut cur_font := 0
	for i, r in runes {
		f := if i > 0 && is_neutral(r) { cur_font } else { fonts[i] }
		if cur.len > 0 && f != cur_font {
			out << TextRun{cur.string(), cur_font}
			cur = []rune{}
		}
		cur_font = f
		cur << r
	}
	if cur.len > 0 {
		out << TextRun{cur.string(), cur_font}
	}
	return out
}

// ----------------------------------------------------------- font names

const generic_families = ['monospace', 'mono', 'sans', 'sans-serif', 'serif', 'cursive', 'fantasy',
	'system-ui', 'emoji', 'math']
const style_words = ['regular', 'book', 'normal', 'roman', 'bold', 'italic', 'oblique', 'light',
	'medium', 'semibold', 'extrabold', 'thin', 'black', 'heavy', 'condensed']

// requested_family returns the family part of a fontconfig pattern string
// ("Noto Sans:pixelsize=12" -> "Noto Sans"; "A,B" stays "A,B").
pub fn requested_family(pattern string) string {
	i := pattern.index(':') or { return pattern.trim_space() }
	return pattern[..i].trim_space()
}

// is_generic_family reports aliases like "monospace" that fontconfig resolves
// to a different real family on purpose.
pub fn is_generic_family(family string) bool {
	for f in family.split(',') {
		if f.trim_space().to_lower() !in generic_families {
			return false
		}
	}
	return true
}

// family_matches reports whether the family fontconfig picked is one of the
// (comma separated, case-insensitive) families that were asked for.
pub fn family_matches(requested string, matched string) bool {
	m := matched.trim_space().to_lower()
	for f in requested.split(',') {
		if f.trim_space().to_lower() == m {
			return true
		}
	}
	return false
}

// split_trailing_style rewrites "Noto Sans Regular:pixelsize=12" as
// "Noto Sans:style=Regular:pixelsize=12": font pickers show "Family Style" but
// fontconfig wants the style as a separate property. Returns none when the
// family does not end in a style word (or is only a style word).
pub fn split_trailing_style(pattern string) ?string {
	fam := requested_family(pattern)
	if fam.contains(',') {
		return none
	}
	words := fam.split(' ').filter(it != '')
	mut n := words.len
	for n > 1 && words[n - 1].to_lower() in style_words {
		n--
	}
	if n == words.len {
		return none
	}
	rest := if i := pattern.index(':') { pattern[i..] } else { '' }
	return '${words[..n].join(' ')}:style=${words[n..].join(' ')}${rest}'
}
