#!/usr/bin/env python3
"""Fresh Breath: cut the theme art out of J's layered mockup SVGs.

    python3 make-art.py MOCKUP_DIR

MOCKUP_DIR holds fresh-breath-{sedona,painted-desert,chillwave,office-print}.svg.
Every layer in those files is a PNG at twice the mockup's size. This script
places each layer on the mockup's own 1x pixel grid, crops the plate it needs,
halves it with a box filter and writes it to <palette>/art/. Needs Pillow and
numpy.

What it does to the art, and why:
  * Plate edges get a hard alpha (0 or 255). Glo55 cuts frames with the 1-bit
    X SHAPE extension, so a half-transparent edge would only blend into black.
    Drop shadows go for the same reason (nothing to blend them against).
  * Plates that carry text in the mockup (title plates, clock, rail, workspace
    plates) lose the text: each row of the text span is refilled from the
    clean paint on the same row, in short chunks, so the brushed grain and the
    gloss run on unchanged. Glo55 draws the real text on top.
  * Title plates become 9-slice images: the slanted caps stay as drawn, and the
    middle is rebuilt wide enough that stretching it does not show.
  * The close button's pressed face is the hover face recoloured from the
    title paint to the register-slip paint (the parts sheet's "Pressed").
"""
import base64
import os
import re
import sys

import numpy as np
from PIL import Image

PALETTES = ['sedona', 'painted-desert', 'chillwave', 'office-print']
HERE = os.path.dirname(os.path.abspath(__file__))
RNG = np.random.default_rng(55)


# ------------------------------------------------------------------ loading

def load_layers(path):
    """{layer id: (RGBA float array at 2x, x, y at 1x)} from a mockup SVG."""
    data = open(path).read()
    out = {}
    for m in re.finditer(r'<image ([^>]*)/?>', data):
        a = m.group(1)
        iid = re.search(r'\bid="([^"]*)"', a).group(1)
        b64 = re.search(r'base64,([A-Za-z0-9+/=]+)', a).group(1)
        x = float(re.search(r'\bx="([^"]*)"', a).group(1))
        y = float(re.search(r'\by="([^"]*)"', a).group(1))
        w = float(re.search(r'\bwidth="([^"]*)"', a).group(1))
        h = float(re.search(r'\bheight="([^"]*)"', a).group(1))
        tmp = '/tmp/fresh-breath-layer.png'
        open(tmp, 'wb').write(base64.b64decode(b64))
        im = Image.open(tmp).convert('RGBA')
        size = (round(w * 2), round(h * 2))
        if im.size != size:
            im = im.resize(size, Image.LANCZOS)
        if iid in out:
            iid += '-2'
        out[iid] = (np.asarray(im).astype(np.float64), x, y)
    return out


def region(layers, iid, x0, y0, x1, y1):
    """The 2x pixels of one layer inside the 1x box (x0, y0)-(x1, y1)."""
    img, x, y = layers[iid]
    w, h = (x1 - x0) * 2, (y1 - y0) * 2
    out = np.zeros((h, w, 4))
    ox, oy = round(x * 2) - x0 * 2, round(y * 2) - y0 * 2
    sx0, sy0 = max(0, -ox), max(0, -oy)
    dx0, dy0 = max(0, ox), max(0, oy)
    cw = min(img.shape[1] - sx0, w - dx0)
    ch = min(img.shape[0] - sy0, h - dy0)
    if cw > 0 and ch > 0:
        out[dy0:dy0 + ch, dx0:dx0 + cw] = img[sy0:sy0 + ch, sx0:sx0 + cw]
    return out


def over(dst, src):
    """src over dst, both straight-alpha float arrays."""
    sa, da = src[..., 3:] / 255, dst[..., 3:] / 255
    oa = sa + da * (1 - sa)
    rgb = (src[..., :3] * sa + dst[..., :3] * da * (1 - sa)) / np.maximum(oa, 1e-6)
    return np.concatenate([rgb, oa * 255], axis=2)


def opaque_box(layers, iid, thresh=200):
    """The 1x box around the layer's solid pixels."""
    img, x, y = layers[iid]
    ys, xs = np.where(img[..., 3] > thresh)
    ox, oy = round(x * 2), round(y * 2)
    return ((ox + xs.min()) // 2, (oy + ys.min()) // 2,
            (ox + xs.max() + 2) // 2, (oy + ys.max() + 2) // 2)


def halve(a2):
    """2x -> 1x with a premultiplied box filter, then a hard alpha edge."""
    h, w = a2.shape[0] // 2, a2.shape[1] // 2
    a2 = a2[:h * 2, :w * 2]
    al = a2[..., 3:] / 255
    pre = np.concatenate([a2[..., :3] * al, al], axis=2)
    pre = pre.reshape(h, 2, w, 2, 4).mean(axis=(1, 3))
    alpha = pre[..., 3:]
    rgb = pre[..., :3] / np.maximum(alpha, 1e-6)
    solid = (alpha >= 0.5).astype(np.float64)
    return np.concatenate([rgb, solid * 255], axis=2)


def save(a, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(np.clip(a + 0.5, 0, 255).astype(np.uint8), 'RGBA').save(path, optimize=True)


def solid_mask(a2, thresh=128):
    return a2[..., 3] >= thresh


# ------------------------------------------------------------ text removal

def text_columns(a2, light, margin=12, gap=60):
    """Columns of a 2x plate where its baked-in text is. `light` = the text is
    lighter than the paint (else darker). Glyph stems are tall runs of
    off-colour pixels; grain lines are short, so a column needs several hits,
    and the text is the biggest cluster of such columns."""
    m = solid_mask(a2, 250)
    lum = a2[..., :3] @ [0.299, 0.587, 0.114]
    count = np.zeros(a2.shape[1], int)
    for y in range(a2.shape[0]):
        row = m[y]
        if row.sum() < 20:
            continue
        med = np.median(lum[y][row])
        dev = (lum[y] - med) if light else (med - lum[y])
        count += row & (dev > 50)
    cols = np.where(count >= max(3, a2.shape[0] // 8))[0]
    groups, cur = [], [cols[0]]
    for c in cols[1:]:
        if c - cur[-1] <= gap:
            cur.append(c)
        else:
            groups.append(cur)
            cur = [c]
    groups.append(cur)
    best = max(groups, key=lambda g: count[g].sum())
    return best[0] - margin, best[-1] + margin


def refill(a2, c0, c1, rows=None, chunk=(10, 26), edge=10):
    """Paint over columns c0..c1 of a 2x plate with chunks of the clean paint
    of the same rows (both sides of the span), cross-faded so no seam shows.
    The same chunk choice is used on every row, so vertical gloss stays."""
    a2 = a2.copy()
    h = a2.shape[0]
    rows = range(h) if rows is None else rows
    m = solid_mask(a2, 250)
    # clean columns: solid on (nearly) every row of the plate's core, outside the text
    core = [y for y in rows if m[y].sum() > 10]
    # clean columns: well inside the plate on every row (clear of the bevelled
    # slanted ends) and outside the text
    for e in range(edge, 1, -1):
        lo = max(np.where(m[y])[0].min() for y in core) + e
        hi = min(np.where(m[y])[0].max() for y in core) - e
        clean = np.array([x for x in range(lo, hi + 1) if x < c0 - 2 or x > c1 + 2])
        if len(clean) >= 8:
            break
    if len(clean) < 8:
        raise ValueError(f'refill: not enough clean paint to rebuild from ({len(clean)} columns, span {c0}..{c1})')
    # Large-scale light (the gloss, the reflection) changes along the plate,
    # so copied chunks would show as blocks. Copy only the fine grain (the
    # clean paint minus its horizontal blur) onto the row's average colour,
    # and fade that into the original paint at both ends of the span.
    src = a2[:, clean, :3]
    k = 31
    pad = np.pad(src, ((0, 0), (k // 2, k // 2), (0, 0)), mode='edge')
    cs = np.cumsum(pad, axis=1)
    cs = np.concatenate([np.zeros_like(cs[:, :1]), cs], axis=1)
    blur = (cs[:, k:] - cs[:, :-k]) / k
    detail = src - blur
    # a column that is brighter all the way down reads as a vertical line once
    # chunks are shuffled: keep only the along-the-row grain
    core_rows = np.array(core)
    detail[core_rows] -= detail[core_rows].mean(axis=0, keepdims=True)
    base = src.mean(axis=1)
    fill = np.zeros((a2.shape[0], c1 - c0 + 1, 3))
    x = 0
    while x < fill.shape[1]:
        n = int(RNG.integers(*chunk))
        start = int(RNG.integers(0, max(1, len(clean) - n)))
        seg = detail[:, start:start + n]
        n = min(seg.shape[1], fill.shape[1] - x)
        fill[:, x:x + n] = base[:, None] + seg[:, :n]
        x += n
    fade = min(10, fill.shape[1] // 4)
    for i in range(fade):
        t = (i + 1) / (fade + 1)
        fill[:, i] = a2[:, c0 + i, :3] * (1 - t) + fill[:, i] * t
        j = fill.shape[1] - 1 - i
        fill[:, j] = a2[:, c0 + j, :3] * (1 - t) + fill[:, j] * t
    for y in core:
        a2[y, c0:c1 + 1, :3] = fill[y]
    return a2


def widen(a2, c0, c1, extra):
    """Insert `extra` 2x columns of rebuilt paint after column c1 (the middle of
    a plate) so the 9-slice middle is wide."""
    h, w = a2.shape[:2]
    mid = np.zeros((h, extra, 4))
    left, right = a2[:, :c1], a2[:, c1:]
    # fill the inserted block: copy any solid middle column, then refill it
    for i in range(extra):
        mid[:, i] = a2[:, (c0 + c1) // 2]
    out = np.concatenate([left, mid, right], axis=1)
    return refill(out, c1, c1 + extra - 1)


# --------------------------------------------------------------- recolour

def recolor(a2, mask, src_rgb, dst_rgb):
    """Move pixels under `mask` from one paint to another, keeping their
    shading (ratio to the source paint's mean)."""
    a2 = a2.copy()
    w = np.array([0.299, 0.587, 0.114])
    ratio = (a2[..., :3] @ w) / max(np.array(src_rgb) @ w, 1)
    new = np.clip(ratio[..., None] * np.array(dst_rgb), 0, 255)
    a2[mask, :3] = new[mask]
    return a2


def mean_rgb(a2, mask):
    return a2[mask, :3].mean(axis=0)


def hexc(rgb):
    return '#%02x%02x%02x' % tuple(int(round(v)) for v in rgb)


# -------------------------------------------------------------- wallpaper

def overlay_blend(base, top, alpha):
    b, s = base / 255, top / 255
    o = np.where(b < 0.5, 2 * b * s, 1 - 2 * (1 - b) * (1 - s))
    return (b * (1 - alpha) + o * alpha) * 255


def wallpaper(L):
    sky = L['sky'][0]
    canvas = sky.copy()
    for iid in ['moon', 'sea', 'palm']:
        img, x, y = L[iid]
        layer = np.zeros_like(canvas)
        ox, oy = round(x * 2), round(y * 2)
        layer[oy:oy + img.shape[0], ox:ox + img.shape[1]] = img[:canvas.shape[0] - oy, :canvas.shape[1] - ox]
        canvas = over(canvas, layer)
    g = L['grain'][0]
    rgb = overlay_blend(canvas[..., :3], g[..., :3], g[..., 3:] / 255)
    return np.concatenate([rgb, np.full(canvas.shape[:2] + (1,), 255.0)], axis=2)


# ------------------------------------------------------------------ build

def build(pal, svg):
    L = load_layers(svg)
    art = os.path.join(HERE, pal, 'art')
    vars_ = {}

    # the wallpaper (2880x1800, sky, moon, sea, palm + grain) is only cut for the
    # toolbar's sky tile; the desktop itself is a flat desktop_color
    wp = wallpaper(L)
    sky1 = halve(wp)
    save(sky1[0:30, 0:480], os.path.join(art, 'sky.png'))
    vars_['desktop_color'] = hexc(L['sky'][0][4, 4, :3])

    # ---- title bar, focused (the settings window) and unfocused (terminal)
    # stone: the square plate left of the title
    for state, iid in [('focused', 'set-stone'), ('unfocused', 'term-stone')]:
        b = opaque_box(L, iid)
        save(halve(region(L, iid, *b)), os.path.join(art, state, 'stone.png'))

    # slashes: four (focused, warm to cool) or two (unfocused)
    for state, iid in [('focused', 'set-slashes'), ('unfocused', 'term-slashes')]:
        b = opaque_box(L, iid)
        save(halve(region(L, iid, *b)), os.path.join(art, state, 'slashes.png'))

    # title plates: text out, middle widened, 9-slice caps recorded
    slices = {}
    for state, iid, light in [('focused', 'set-title', False), ('unfocused', 'term-title', True)]:
        b = opaque_box(L, iid)
        a2 = region(L, iid, *b)
        # the plate's own rows (the focused one has the slip 3px above and 4px right)
        c0, c1 = text_columns(a2[6:] if state == 'focused' else a2, light, gap=120)
        rows = range(6, a2.shape[0]) if state == 'focused' else None
        a2 = refill(a2, c0, c1, rows)
        mid = (c0 + c1) // 2 // 2 * 2
        a2 = widen(a2, mid - 40, mid, 600)
        if state == 'focused':
            # the slip shows above the plate along its whole length: rebuild its
            # widened stretch from the slip row on either side
            a2 = refill_band(a2, 0, 6, mid, mid + 600)
        one = halve(a2)
        save(one, os.path.join(art, state, 'title.png'))
        slices[state] = one.shape[1]
        if state == 'focused':
            vars_['paint'] = hexc(mean_rgb(a2, solid_mask(a2, 250) & (np.arange(a2.shape[0])[:, None] > 10)))

    # buttons: the normal plate is the unfocused window's (both are the same
    # metal); the focused window in the mockup shows close hovered.
    nb = opaque_box(L, 'term-buttons')
    normal = region(L, 'term-buttons', *nb)
    hb = opaque_box(L, 'set-buttons')
    hover = region(L, 'set-buttons', *hb)
    sb = opaque_box(L, 'shaded-buttons')
    shaded = region(L, 'shaded-buttons', *sb)
    h, w = min(normal.shape[0], hover.shape[0], shaded.shape[0]), min(normal.shape[1], hover.shape[1], shaded.shape[1])
    normal, hover, shaded = normal[:h, :w], hover[:h, :w], shaded[:h, :w]
    save(halve(normal), os.path.join(art, 'buttons.png'))
    save(halve(shaded), os.path.join(art, 'buttons-shaded.png'))
    # The close cell: where the hovered plate turns to title paint. The three
    # icons sit 24px apart (1x) in every palette: _ at 28, the box at 52, x at 76.
    diff = np.abs(hover[..., :3] - normal[..., :3]).sum(axis=2) > 90
    cell = np.zeros((h, w), bool)
    for y in range(h):
        xs = [x for x in np.where(diff[y])[0] if 120 <= x < 180]
        if xs:
            cell[y, min(xs):max(xs) + 1] = True
    slip = slip_color(L)
    sat = hover[..., :3].max(axis=2) - hover[..., :3].min(axis=2)
    lum = hover[..., :3] @ [0.299, 0.587, 0.114]
    paint = cell & (lum > np.median(lum[cell]) - 40)
    hov = normal.copy()
    hov[cell] = hover[cell]
    pre = hov.copy()
    pre = recolor(pre, paint, mean_rgb(hover, paint), slip)
    one_n, one_h, one_p = halve(normal), halve(hov), halve(pre)
    cells = {'collapse': (16, 40), 'fullscreen': (40, 64), 'close': (64, 88)}
    for name, (x0, x1) in cells.items():
        if name == 'close':
            hv, pr = one_h, one_p
        else:
            # the parts sheet only shows close; the other two lift a little on
            # hover and sink on press, in the close cell's slanted shape
            shift = (64 - x0) * 2
            m2 = np.zeros((h, w), bool)
            m2[:, :w - shift] = cell[:, shift:]
            m1 = halve(np.dstack([np.zeros((h, w, 3)), m2 * 255.0]))[..., 3] > 0
            hv, pr = one_n.copy(), one_n.copy()
            hv[m1, :3] = np.clip(hv[m1, :3] * 1.3 + 14, 0, 255)
            pr[m1, :3] = pr[m1, :3] * 0.65
        save(hv[:, x0:x1], os.path.join(art, f'btn-{name}-hover.png'))
        save(pr[:, x0:x1], os.path.join(art, f'btn-{name}-pressed.png'))

    # ---- frames: 9-slice of the frame chrome (the client covers the middle)
    for state, iid, wedge in [('focused', 'set-frame', 'set-wedge'), ('unfocused', 'term-frame', 'term-wedge')]:
        b = opaque_box(L, iid)
        save(halve(region(L, iid, *b)), os.path.join(art, state, 'frame.png'))
        wb = opaque_box(L, wedge)
        save(halve(region(L, wedge, *wb)), os.path.join(art, state, 'wedge.png'))
    b = opaque_box(L, 'shaded-frame')
    save(halve(region(L, 'shaded-frame', *b)), os.path.join(art, 'shaded-bar.png'))

    # ---- toolbar
    # rail: a thin plate the width of the screen; its title text goes
    b = opaque_box(L, 'tb-rail')
    a2 = region(L, 'tb-rail', *b)
    c0, c1 = text_columns(a2, True)
    a2 = refill(a2, c0, c1)
    one = halve(a2)
    save(one, os.path.join(art, 'rail.png'))

    # clock plate (with its slip): the time and date go
    b = opaque_box(L, 'tb-clock')
    a2 = region(L, 'tb-clock', *b)
    c0, c1 = text_columns(a2[6:], False)
    a2 = refill(a2, c0, c1, range(6, a2.shape[0]))
    save(halve(a2), os.path.join(art, 'clock.png'))

    b = opaque_box(L, 'tb-slashes')
    save(halve(region(L, 'tb-slashes', *b)), os.path.join(art, 'tb-slashes.png'))

    # workspace plates: the first (active, cream) and the second (metal)
    b = opaque_box(L, 'tb-desks')
    a2 = region(L, 'tb-desks', *b)
    plates = split_plates(a2)
    act, idle = plates[0], plates[1]
    clean = {}
    for name, p, light in [('ws-active', act, False), ('ws-idle', idle, True)]:
        c0, c1 = text_columns(p, light, margin=7, gap=12)
        clean[name] = refill(p, c0, c1, chunk=(4, 8), edge=5)
        save(halve(clean[name]), os.path.join(art, name + '.png'))
    idle1 = halve(clean['ws-idle'])
    hv = idle1.copy(); hv[..., :3] = np.clip(hv[..., :3] * 1.25 + 12, 0, 255)
    pr = idle1.copy(); pr[..., :3] = pr[..., :3] * 0.7
    save(hv, os.path.join(art, 'ws-hover.png'))
    save(pr, os.path.join(art, 'ws-pressed.png'))

    # text colours, read off the mockup's own text
    vars_['title_on'] = text_color(L, 'set-title', False)
    vars_['title_idle'] = text_color(L, 'term-title', True)
    vars_['slip'] = hexc(slip)
    vars_['rail_title'] = text_color(L, 'tb-rail', True, 40)
    return vars_, slices


def refill_band(a2, y0, y1, c0, c1):
    """refill() for a horizontal band of rows (the slip above the title)."""
    band = a2[y0:y1].copy()
    m = band[..., 3] >= 128
    a2 = a2.copy()
    for y in range(y0, y1):
        row = a2[y]
        clean = [x for x in np.where(row[:, 3] >= 250)[0] if x < c0 - 4 or x > c1 + 4]
        clean = clean[3:-3]
        if len(clean) < 4:
            continue
        for x in range(c0, c1):
            sx = clean[int(RNG.integers(0, len(clean)))]
            a2[y, x] = row[sx]
    return a2


def slip_color(L):
    """The register slip's paint: the band of the focused title above its plate."""
    b = opaque_box(L, 'set-title')
    a2 = region(L, 'set-title', *b)
    band = a2[14:44, -7:-2]
    m = band[..., 3] >= 250
    return band[m, :3].mean(axis=0)


def text_color(L, iid, light, contrast=90):
    b = opaque_box(L, iid)
    a2 = region(L, iid, *b)
    m = solid_mask(a2, 250)
    lum = a2[..., :3] @ [0.299, 0.587, 0.114]
    med = np.median(lum[m])
    pick = m & ((lum > med + contrast) if light else (lum < med - contrast))
    return hexc(a2[pick, :3].mean(axis=0))


def split_plates(a2):
    """The separate plates of the workspace strip (2x), left to right, each a
    copy of the strip with everything but that plate cleared. The plates touch
    along slanted seams; the seams show as notches in the top and bottom solid
    rows, and a seam runs straight from its top notch to its bottom notch."""
    solid = a2[..., 3] >= 250
    rows = np.where(solid.sum(axis=1) > solid.shape[1] // 2)[0]
    yt, yb = rows.min(), rows.max()

    def notches(y):
        xs = np.where(solid[y])[0]
        gaps, x = [], xs.min()
        while x < xs.max():
            if not solid[y, x]:
                s = x
                while not solid[y, x]:
                    x += 1
                gaps.append((s + x - 1) / 2)
            x += 1
        return gaps

    tops, bots = notches(yt), notches(yb)
    seams = list(zip(tops, bots))
    plates = []
    ys = np.arange(a2.shape[0])[:, None]
    xs = np.arange(a2.shape[1])[None, :]
    edges = [None] + seams + [None]
    for left, right in zip(edges[:-1], edges[1:]):
        keep = np.ones(a2.shape[:2], bool)
        for seam, side in ((left, 1), (right, -1)):
            if seam is None:
                continue
            xt, xb = seam
            sx = xb + (xt - xb) * (yb - ys) / (yb - yt)
            keep &= (xs - sx) * side > 0
        p = a2.copy()
        p[~keep] = 0
        cols = np.where((p[..., 3] > 0).any(axis=0))[0]
        plates.append(p[:, cols.min():cols.max() + 1])
    return plates


NAMES = {'sedona': 'Sedona', 'painted-desert': 'Painted Desert', 'chillwave': 'Chillwave',
         'office-print': 'Office Print'}


def write_theme(pal, v):
    open(os.path.join(HERE, pal, 'theme.toml'), 'w').write(f"""\
# Fresh Breath - {NAMES[pal]}. The layout is shared (../layout.toml); the art in
# art/ and these colours come from the {NAMES[pal]} mockup (make-art.py).
extends = "../layout.toml"

[vars]
desktop_color = "{v['desktop_color']}"   # the sky
title_on      = "{v['title_on']}"   # text on the title paint (and the cream plate)
title_idle    = "{v['title_idle']}"   # text on the unfocused metal
rail_title    = "{v['rail_title']}"   # the spaced-out title on the toolbar rail
""")


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    for pal in PALETTES:
        svg = os.path.join(sys.argv[1], f'fresh-breath-{pal}.svg')
        vars_, _ = build(pal, svg)
        write_theme(pal, vars_)
        print(pal, vars_)


if __name__ == '__main__':
    main()
