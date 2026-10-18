"""Generates every Calmpost logo file from one geometry definition.

The mark is the Home screen's health bezel drawn as a "C": a white gauge ending
in the pink marker, around the Bin World's two soil layers and a sprout.

    python brand/make_logo.py

Writes brand/*.svg, brand/png/*.png, the Android launcher icons and the web
icons. Colours are the tokens from app/lib/ui/tokens.dart. Needs Pillow and
fontTools (no SVG renderer: shapes are rasterised here directly).
"""

import math
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
BRAND = ROOT / 'brand'
FONT = ROOT / 'app/assets/fonts/Fraunces-500.ttf'

BRAND_GREEN = '#40C274'
BRAND_DEEP = '#31AE63'
FOREST = '#1F3A2E'
INK = '#11251A'
PINK = '#FF66C4'
WHITE = '#FFFFFF'
PAPER = '#E1EBD8'

# Design space: 512 x 512, centre (256, 256).
C = 256
RING_R = 150
RING_W = 28
GAP = 40  # degrees either side of 3 o'clock, which opens the "C"
WINDOW_R = 118  # the soil is clipped to this circle inside the bezel
WINDOW = (C, C, WINDOW_R)


def mark(mono=None, halo=BRAND_GREEN):
    """Shapes of the mark in design units. `mono` draws it in one colour."""
    fg = mono or WHITE
    back_hill = [('M', 100, 298), ('Q', 190, 266, 270, 290), ('Q', 340, 310, 420, 278), ('L', 420, 420), ('L', 100, 420), ('Z',)]
    front_hill = [('M', 100, 322), ('Q', 200, 294, 300, 314), ('Q', 370, 328, 420, 310), ('L', 420, 420), ('L', 100, 420), ('Z',)]
    left_leaf = [('M', 255, 262), ('Q', 208, 260, 186, 216), ('Q', 236, 216, 255, 262), ('Z',)]
    right_leaf = [('M', 256, 250), ('Q', 314, 246, 334, 184), ('Q', 274, 190, 256, 250), ('Z',)]
    end = math.radians(360 - GAP)
    mx, my = C + RING_R * math.cos(end), C + RING_R * math.sin(end)
    shapes = [('arc', C, C, RING_R, GAP, 360 - GAP, RING_W, fg)]
    if mono:
        shapes += [
            ('line', 256, 330, 256, 252, 14, fg),
            ('path', left_leaf, fg, None),
            ('path', right_leaf, fg, None),
            ('path', front_hill, fg, WINDOW),
            ('circle', mx, my, 21, fg),
        ]
    else:
        shapes += [
            ('line', 256, 330, 256, 252, 14, fg),
            ('path', left_leaf, fg, None),
            ('path', right_leaf, fg, None),
            ('path', back_hill, BRAND_DEEP, WINDOW),
            ('path', front_hill, FOREST, WINDOW),
        ]
        if halo:
            shapes.append(('circle', mx, my, 31, halo))
        shapes.append(('circle', mx, my, 21, PINK))
    return shapes


# ---------------------------------------------------------------- SVG

def _f(v):
    return f'{v:.1f}'.rstrip('0').rstrip('.')


def _d(cmds):
    out = []
    for c in cmds:
        out.append(c[0] + ' '.join(_f(v) for v in c[1:]))
    return ' '.join(out)


def svg_shapes(shapes, tx=0.0, ty=0.0, s=1.0):
    body, defs = [], {}
    for sh in shapes:
        kind = sh[0]
        if kind == 'circle':
            _, cx, cy, r, col = sh
            body.append(f'<circle cx="{_f(cx)}" cy="{_f(cy)}" r="{_f(r)}" fill="{col}"/>')
        elif kind == 'arc':
            _, cx, cy, r, a0, a1, w, col = sh
            p0 = (cx + r * math.cos(math.radians(a0)), cy + r * math.sin(math.radians(a0)))
            p1 = (cx + r * math.cos(math.radians(a1)), cy + r * math.sin(math.radians(a1)))
            large = 1 if a1 - a0 > 180 else 0
            body.append(
                f'<path d="M{_f(p0[0])} {_f(p0[1])}A{_f(r)} {_f(r)} 0 {large} 1 {_f(p1[0])} {_f(p1[1])}" '
                f'fill="none" stroke="{col}" stroke-width="{_f(w)}" stroke-linecap="round"/>'
            )
        elif kind == 'line':
            _, x1, y1, x2, y2, w, col = sh
            body.append(f'<path d="M{_f(x1)} {_f(y1)}L{_f(x2)} {_f(y2)}" stroke="{col}" stroke-width="{_f(w)}" stroke-linecap="round"/>')
        elif kind == 'path':
            _, cmds, col, clip = sh
            attr = ''
            if clip:
                cid = 'w'
                defs[cid] = f'<clipPath id="{cid}"><circle cx="{_f(clip[0])}" cy="{_f(clip[1])}" r="{_f(clip[2])}"/></clipPath>'
                attr = f' clip-path="url(#{cid})"'
            body.append(f'<path d="{_d(cmds)}" fill="{col}"{attr}/>')
    g = f'<g transform="translate({_f(tx)} {_f(ty)}) scale({s:g})">' + ''.join(body) + '</g>'
    return g, ''.join(defs.values())


def write_svg(path, w, h, layers):
    body = ''.join(l[0] for l in layers)
    defs = ''.join(dict.fromkeys(l[1] for l in layers if l[1]))
    path.write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {_f(w)} {_f(h)}" width="{_f(w)}" height="{_f(h)}">'
        + (f'<defs>{defs}</defs>' if defs else '') + body + '</svg>\n',
        encoding='utf-8',
    )


def wordmark_svg(text, size, x, baseline, colour):
    font = TTFont(FONT)
    gs = font.getGlyphSet()
    cmap = font.getBestCmap()
    upm = font['head'].unitsPerEm
    k = size / upm
    pen = SVGPathPen(gs)
    cursor = 0
    for ch in text:
        name = cmap[ord(ch)]
        gs[name].draw(TransformPen(pen, (k, 0, 0, -k, x + cursor * k, baseline)))
        cursor += font['hmtx'][name][0]
    return f'<path d="{pen.getCommands()}" fill="{colour}"/>', cursor * k


# ---------------------------------------------------------------- raster

SS = 4  # supersampling


def _bezier(cmds, tf):
    pts, cur = [], (0, 0)
    for c in cmds:
        if c[0] in 'ML':
            cur = (c[1], c[2])
            pts.append(tf(*cur))
        elif c[0] == 'Q':
            (x0, y0), (cx, cy), (x1, y1) = cur, (c[1], c[2]), (c[3], c[4])
            for i in range(1, 33):
                t = i / 32
                pts.append(tf((1 - t) ** 2 * x0 + 2 * (1 - t) * t * cx + t * t * x1, (1 - t) ** 2 * y0 + 2 * (1 - t) * t * cy + t * t * y1))
            cur = (x1, y1)
    return pts


def draw_shapes(img, shapes, tx, ty, s):
    """Draws design-unit shapes onto an RGBA image already at SS resolution."""
    tf = lambda x, y: (tx + x * s, ty + y * s)  # noqa: E731
    d = ImageDraw.Draw(img)

    def dot(x, y, r, col):
        px, py = tf(x, y)
        d.ellipse([px - r * s, py - r * s, px + r * s, py + r * s], fill=col)

    for sh in shapes:
        kind = sh[0]
        if kind == 'circle':
            _, cx, cy, r, col = sh
            dot(cx, cy, r, col)
        elif kind == 'arc':
            _, cx, cy, r, a0, a1, w, col = sh
            n = 240
            angs = [math.radians(a0 + (a1 - a0) * i / n) for i in range(n + 1)]
            outer = [tf(cx + (r + w / 2) * math.cos(a), cy + (r + w / 2) * math.sin(a)) for a in angs]
            inner = [tf(cx + (r - w / 2) * math.cos(a), cy + (r - w / 2) * math.sin(a)) for a in reversed(angs)]
            d.polygon(outer + inner, fill=col)
            for a in (angs[0], angs[-1]):
                dot(cx + r * math.cos(a), cy + r * math.sin(a), w / 2, col)
        elif kind == 'line':
            _, x1, y1, x2, y2, w, col = sh
            d.line([tf(x1, y1), tf(x2, y2)], fill=col, width=round(w * s))
            dot(x1, y1, w / 2, col)
            dot(x2, y2, w / 2, col)
        elif kind == 'path':
            _, cmds, col, clip = sh
            mask = Image.new('L', img.size, 0)
            ImageDraw.Draw(mask).polygon(_bezier(cmds, tf), fill=255)
            if clip:
                cm = Image.new('L', img.size, 0)
                px, py = tf(clip[0], clip[1])
                r = clip[2] * s
                ImageDraw.Draw(cm).ellipse([px - r, py - r, px + r, py + r], fill=255)
                mask = Image.composite(mask, Image.new('L', img.size, 0), cm)
            img.paste(Image.new('RGBA', img.size, col), (0, 0), mask)


def render(size, bg=None, radius=0.0, content=0.82, shapes=None, mode='RGBA'):
    """A square icon: optional background (radius as a fraction of size) and the mark scaled to `content`."""
    big = size * SS
    img = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    if bg:
        ImageDraw.Draw(img).rounded_rectangle([0, 0, big - 1, big - 1], radius=radius * big, fill=bg)
    s = big * content / 512
    draw_shapes(img, shapes or mark(), big / 2 - 256 * s, big / 2 - 256 * s, s)
    img = img.resize((size, size), Image.LANCZOS)
    return img.convert(mode) if mode != 'RGBA' else img


# ---------------------------------------------------------------- outputs

ICON_RADIUS = 0.225  # rounded-square share of the icon width


def main():
    png = BRAND / 'png'
    png.mkdir(parents=True, exist_ok=True)

    # 1. App icon: brand green rounded square with the full-colour mark.
    rr = 512 * ICON_RADIUS
    icon_bg = (f'<rect width="512" height="512" rx="{_f(rr)}" fill="{BRAND_GREEN}"/>', '')
    write_svg(BRAND / 'calmpost-icon.svg', 512, 512, [icon_bg, svg_shapes(mark(), 256 - 256 * 0.82, 256 - 256 * 0.82, 0.82)])
    # 2. Mark alone, transparent, for use on brand green (the band).
    write_svg(BRAND / 'calmpost-mark.svg', 512, 512, [svg_shapes(mark())])
    # 3. One-colour marks: white for the band / forest, ink for paper and print.
    write_svg(BRAND / 'calmpost-mark-white.svg', 512, 512, [svg_shapes(mark(mono=WHITE))])
    write_svg(BRAND / 'calmpost-mark-ink.svg', 512, 512, [svg_shapes(mark(mono=INK))])

    # 4. Lockups: icon + Fraunces wordmark. Ink on paper; white on brand green.
    font = TTFont(FONT)
    cap = font['OS/2'].sCapHeight / font['head'].unitsPerEm
    size = 300
    baseline = 256 + cap * size / 2
    for name, text_col, page in (('calmpost-lockup', INK, None), ('calmpost-lockup-reverse', WHITE, BRAND_GREEN)):
        word, width = wordmark_svg('Calmpost', size, 512 + 110, baseline, text_col)
        w = 512 + 110 + width + 40
        layers = []
        if page:
            layers.append((f'<rect x="-40" y="-40" width="{_f(w + 80)}" height="592" fill="{page}"/>', ''))
            layers.append(svg_shapes(mark()))
        else:
            layers += [icon_bg, svg_shapes(mark(), 256 - 256 * 0.82, 256 - 256 * 0.82, 0.82)]
        layers.append((word, ''))
        vb = (w + 80, 592) if page else (w, 512)
        write_svg(BRAND / f'{name}.svg', *vb, layers)
        if page:  # shift the viewBox so the page margin is visible
            p = BRAND / f'{name}.svg'
            p.write_text(p.read_text(encoding='utf-8').replace(f'viewBox="0 0 {_f(w + 80)} 592"', f'viewBox="-40 -40 {_f(w + 80)} 592"'), encoding='utf-8')

        # Raster lockup preview at 2x.
        H = 512
        k = 2 * SS
        img = Image.new('RGBA', (round((w + 80) * k / SS * SS), round(592 * k)), page or (0, 0, 0, 0))
        off = 40 * k
        if not page:
            ImageDraw.Draw(img).rounded_rectangle([off, off, off + H * k, off + H * k], radius=rr * k, fill=BRAND_GREEN)
            s = 0.82 * k
            draw_shapes(img, mark(), off + 256 * k - 256 * s, off + 256 * k - 256 * s, s)
        else:
            draw_shapes(img, mark(), off, off, k)
        ImageDraw.Draw(img).text((off + (512 + 110) * k, off + baseline * k), 'Calmpost', font=ImageFont.truetype(str(FONT), round(size * k)), fill=text_col, anchor='ls')
        img = img.resize((img.width // SS, img.height // SS), Image.LANCZOS)
        if not page:
            flat = Image.new('RGBA', img.size, PAPER)
            flat.alpha_composite(img)
            img = flat
        img.convert('RGB').save(png / f'{name}.png')

    render(1024, BRAND_GREEN, ICON_RADIUS).save(png / 'calmpost-icon-1024.png')
    render(1024, None, 0, 1.0, mark(mono=INK)).save(png / 'calmpost-mark-ink-1024.png')
    render(1024, None, 0, 1.0, mark(mono=WHITE)).save(png / 'calmpost-mark-white-1024.png')

    # Android: adaptive foreground (108dp canvas, 66dp safe zone) + legacy rounded square.
    res = ROOT / 'app/android/app/src/main/res'
    for dpi, legacy in (('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)):
        render(legacy, BRAND_GREEN, ICON_RADIUS).save(res / f'mipmap-{dpi}/ic_launcher.png')
        render(round(legacy * 108 / 48), None, 0, 0.56).save(res / f'mipmap-{dpi}/ic_launcher_foreground.png')

    # Web: plain icons, maskable (content inside the 80% safe circle), favicon.
    web = ROOT / 'app/web'
    for n in (192, 512):
        render(n, BRAND_GREEN, 0, 0.82, mode='RGB').save(web / f'icons/Icon-{n}.png')
        render(n, BRAND_GREEN, 0, 0.66, mode='RGB').save(web / f'icons/Icon-maskable-{n}.png')
    render(64, BRAND_GREEN, ICON_RADIUS, 0.9).save(web / 'favicon.png')


if __name__ == '__main__':
    main()
