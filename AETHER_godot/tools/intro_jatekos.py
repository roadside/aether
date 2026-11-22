"""A nyitány handpan-játékosa: festett pixeles alak, a karok mozgásfázisaival.

Saját, kódból festett figura (nem fénykép, nem videókocka és nem valódi személy portréja).
Háromszoros méretben fest, domborított fény-árnyékkal, majd lekicsinyít és kevés színre vált:
ettől lesz „festett pixeles”. A karok külön képek három fázisban (fent, félúton, lent),
a játék ezeket váltja a zene ütéseire (scripts/intro.gd).

Kimenet (640×360, átlátszó háttérrel) az assets/intro mappába:
  jatekos.png                 test, fej, lábak, a kő
  handpan.png                 a hangszer
  kar_b_0..2.png, kar_j_0..2.png   a bal és a jobb kar (a képen bal/jobb) három fázisa

Kell hozzá: Pillow és numpy.   Használat:  python tools/intro_jatekos.py
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W, H, S = 640, 360, 3
OUT = Path(__file__).resolve().parent.parent / "assets" / "intro"
LIGHT = np.array([-0.55, -0.75])           # a fény balról-fentről jön

SKIN = (186, 138, 104)
SHIRT = (206, 192, 164)
TROUSERS = (98, 88, 62)
PAN_C = (322, 262)
# a hangmezők a hangszer közepéhez képest (x, y, félszélesség); az első a középső „ding”
FIELDS = [(0, -24, 16), (-58, -21, 11), (-21, -34, 10), (21, -34, 10), (58, -21, 11), (60, -6, 12), (22, 5, 13), (-22, 5, 13), (-60, -6, 12)]


def sc(pts):
    return [(x * S, y * S) for x, y in pts]


def new():
    return Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))


def mask_of(draw_fn):
    m = Image.new("L", (W * S, H * S), 0)
    draw_fn(ImageDraw.Draw(m))
    return m


def part(canvas, draw_fn, color, round_r=10, k=0.9, grain=0.05, seed=0, shadow=0.0, ambient=0.80):
    """Egy testrész: a maszk elmosásából domborzatot számol, és balról-fentről megvilágítja."""
    m = mask_of(draw_fn)
    if shadow > 0.0:                      # vetett árnyék az alatta lévő részekre
        sh = m.filter(ImageFilter.GaussianBlur(5 * S)).point(lambda v: int(v * shadow))
        off = Image.new("L", m.size, 0)
        off.paste(sh, (3 * S, 5 * S))
        dark = Image.new("RGBA", m.size, (10, 12, 8, 0))
        dark.putalpha(Image.fromarray(np.minimum(np.asarray(off), np.asarray(canvas.split()[3]))))
        canvas.alpha_composite(dark)
    hgt = np.asarray(m.filter(ImageFilter.GaussianBlur(round_r * S))).astype("float32") / 255.0
    gy, gx = np.gradient(hgt)
    lit = (gx * LIGHT[0] + gy * LIGHT[1]) * round_r * S * k * -1.0
    rng = np.random.default_rng(seed)
    small = rng.random((H // 2, W // 2)).astype("float32")
    noise = np.asarray(Image.fromarray((small * 255).astype("uint8")).resize((W * S, H * S), Image.BICUBIC)).astype("float32") / 255.0
    shade = np.clip(ambient + lit + (noise - 0.5) * grain * 2, 0.35, 1.35)
    col = np.array(color, dtype="float32")[None, None, :] * shade[..., None]
    # hűvös-zöld árnyék, meleg fény: az erdő visszavert fénye
    cool = np.clip(1.0 - shade, 0, 1)[..., None]
    col = col * (1 - 0.25 * cool) + np.array([20, 46, 30], dtype="float32") * 0.25 * cool
    layer = np.dstack([col.clip(0, 255), np.asarray(m).astype("float32")]).astype("uint8")
    canvas.alpha_composite(Image.fromarray(layer, "RGBA"))
    return m


def tint(canvas, draw_fn, blur=2.0, clip=None):
    """Lágy színfolt (árnyék, borosta, csillanás) a meglévő alakra."""
    lay = new()
    draw_fn(ImageDraw.Draw(lay))
    lay = lay.filter(ImageFilter.GaussianBlur(blur * S))
    a = np.minimum(np.asarray(lay.split()[3]), np.asarray(canvas.split()[3] if clip is None else clip))
    lay.putalpha(Image.fromarray(a))
    canvas.alpha_composite(lay)


def capsule(d, a, b, ra, rb):
    """Elvékonyodó végtag: két kör és az őket összekötő trapéz."""
    ax, ay, bx, by = a[0] * S, a[1] * S, b[0] * S, b[1] * S
    ra, rb = ra * S, rb * S
    d.ellipse([ax - ra, ay - ra, ax + ra, ay + ra], fill=255)
    d.ellipse([bx - rb, by - rb, bx + rb, by + rb], fill=255)
    dx, dy = bx - ax, by - ay
    ln = max(1e-6, (dx * dx + dy * dy) ** 0.5)
    nx, ny = -dy / ln, dx / ln
    d.polygon([(ax + nx * ra, ay + ny * ra), (bx + nx * rb, by + ny * rb), (bx - nx * rb, by - ny * rb), (ax - nx * ra, ay - ny * ra)], fill=255)


def finish(img, colors):
    small = img.resize((W, H), Image.BOX)
    a = small.split()[3].point(lambda v: 255 if v > 110 else 0)
    rgb = small.convert("RGB").quantize(colors=colors, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")
    rgb.putalpha(a)
    return rgb


def body():
    c = new()
    cx = 330
    # a mohos kő, amin ül
    part(c, lambda d: d.polygon(sc([(196, 360), (214, 318), (262, 300), (402, 300), (452, 320), (470, 360)]), fill=255),
         (44, 62, 44), round_r=14, k=0.8, seed=1, grain=0.10)
    tint(c, lambda d: d.polygon(sc([(214, 318), (262, 300), (402, 300), (452, 320), (440, 328), (228, 328)]), fill=(60, 120, 58, 150)), blur=3)
    # combok: a hangszer alól kétoldalt kifelé, térdek a kép szélei felé
    for a, b in (((300, 292), (226, 326)), ((352, 292), (434, 326))):
        part(c, lambda d, a=a, b=b: capsule(d, a, b, 25, 22), TROUSERS, round_r=12, k=0.9, seed=2, shadow=0.3)
    for a, b in (((226, 326), (268, 352)), ((434, 326), (392, 352))):
        part(c, lambda d, a=a, b=b: capsule(d, a, b, 20, 16), TROUSERS, round_r=10, k=0.8, seed=3, ambient=0.66)
    # nyak, vállak
    part(c, lambda d: d.polygon(sc([(316, 84), (344, 84), (350, 106), (386, 118), (398, 136), (262, 136), (274, 118), (310, 106)]), fill=255),
         SKIN, round_r=9, k=0.8, seed=4, ambient=0.74)
    for sx in (276, 384):
        part(c, lambda d, sx=sx: d.ellipse(sc([(sx - 17, 114), (sx + 17, 148)]), fill=255), SKIN, round_r=10, k=1.0, seed=5)
    # ujjatlan vászoning: laza, a mellkasnál szélesebb, lent a hangszer mögé fut
    shirt_pts = [(294, 110), (310, 116), (330, 132), (350, 116), (366, 110), (378, 126), (386, 156), (396, 196), (394, 250),
                 (388, 284), (272, 284), (266, 250), (264, 196), (274, 156), (282, 126)]
    sm = part(c, lambda d: d.polygon(sc(shirt_pts), fill=255), SHIRT, round_r=16, k=1.0, seed=6, grain=0.06, shadow=0.25, ambient=0.78)
    for pts, a in (([(286, 150), (292, 204), (288, 280)], 60), ([(312, 156), (318, 220), (314, 290)], 50), ([(356, 150), (364, 214), (360, 286)], 60),
                   ([(378, 176), (384, 236), (380, 296)], 70), ([(332, 140), (336, 196)], 45), ([(300, 124), (304, 152)], 45)):
        tint(c, lambda d, pts=pts, a=a: d.line(sc(pts), fill=(70, 62, 46, a + 60), width=2 * S), blur=1.2, clip=sm)       # redők
    tint(c, lambda d: d.line(sc([(294, 110), (310, 116), (330, 132), (350, 116), (366, 110)]), fill=(96, 84, 64, 200), width=2 * S), blur=0.6, clip=sm)
    tint(c, lambda d: d.polygon(sc([(356, 112), (380, 128), (396, 196), (392, 300), (360, 300)]), fill=(24, 34, 24, 90)), blur=6, clip=sm)   # árnyékos oldal
    tint(c, lambda d: d.ellipse(sc([(300, 96), (362, 126)]), fill=(30, 22, 16, 110)), blur=4)                               # az áll árnyéka
    # fej: koponya és állkapocs, kissé lehajtva
    def head(d):
        d.ellipse(sc([(cx - 24, 22), (cx + 24, 76)]), fill=255)
        d.polygon(sc([(cx - 23, 52), (cx + 23, 52), (cx + 18, 80), (cx + 8, 94), (cx - 8, 94), (cx - 18, 80)]), fill=255)
    hm = part(c, head, SKIN, round_r=11, k=1.0, seed=7, grain=0.03, shadow=0.0, ambient=0.80)
    for ex in (cx - 27, cx + 21):                                                                                            # fülek
        part(c, lambda d, ex=ex: d.ellipse(sc([(ex, 54), (ex + 7, 70)]), fill=255), SKIN, round_r=3, k=0.8, seed=8, ambient=0.70)
    tint(c, lambda d: d.pieslice(sc([(cx - 26, 18), (cx + 26, 66)]), 180, 360, fill=(74, 56, 44, 120)), blur=2.5, clip=hm)    # nagyon rövid haj
    tint(c, lambda d: d.polygon(sc([(cx + 6, 40), (cx + 24, 44), (cx + 18, 84), (cx + 6, 94)]), fill=(30, 26, 20, 80)), blur=4, clip=hm)
    tint(c, lambda d: d.ellipse(sc([(cx - 21, 72), (cx + 21, 98)]), fill=(92, 70, 54, 110)), blur=2.5, clip=hm)               # borosta
    for ex in (cx - 15, cx + 3):
        tint(c, lambda d, ex=ex: d.ellipse(sc([(ex, 55), (ex + 13, 66)]), fill=(70, 46, 36, 110)), blur=1.6, clip=hm)          # szemgödör
        tint(c, lambda d, ex=ex: d.line(sc([(ex + 1, 62), (ex + 11, 63)]), fill=(52, 34, 26, 255), width=int(1.4 * S)), blur=0.35, clip=hm)   # lehunyt szem
        tint(c, lambda d, ex=ex: d.line(sc([(ex, 55), (ex + 12, 54)]), fill=(84, 62, 48, 230), width=int(1.6 * S)), blur=0.5, clip=hm)        # szemöldök
    tint(c, lambda d: d.polygon(sc([(cx - 2, 58), (cx + 3, 74), (cx - 5, 75)]), fill=(120, 82, 60, 150)), blur=1.0, clip=hm)   # orr
    tint(c, lambda d: d.line(sc([(cx - 3, 60), (cx - 4, 72)]), fill=(232, 190, 152, 120), width=S), blur=0.8, clip=hm)
    tint(c, lambda d: d.line(sc([(cx - 8, 83), (cx + 6, 83)]), fill=(104, 62, 52, 230), width=int(1.4 * S)), blur=0.5, clip=hm)  # száj
    return finish(c, 56)


def pan():
    """A handpan: két lapos, lencse alakú héj a peremnél összeillesztve, enyhén felülről nézve."""
    c = new()
    px, py = PAN_C
    rx = 98
    # alsó héj: lapos, árnyékban van, csak egy keskeny ív látszik belőle a perem alatt
    part(c, lambda d: d.chord(sc([(px - rx + 3, py - 30), (px + rx - 3, py + 30)]), 0, 180, fill=255), (120, 92, 70), round_r=10, k=0.9,
         seed=11, ambient=0.50)
    # felső héj: a perem (döntött kör) és a fölé domborodó lapos kupola
    def dome_shape(d):
        d.ellipse(sc([(px - rx, py - 17), (px + rx, py + 17)]), fill=255)
        d.chord(sc([(px - rx, py - 44), (px + rx, py + 44)]), 180, 360, fill=255)
    dome = part(c, dome_shape, (150, 158, 160), round_r=18, k=1.25, seed=12, grain=0.03, ambient=0.86)
    # a perem: sötét illesztés elöl, fölötte vékony csillanás
    tint(c, lambda d: d.arc(sc([(px - rx, py - 17), (px + rx, py + 17)]), 4, 176, fill=(58, 50, 44, 255), width=int(1.6 * S)), blur=0.4)
    tint(c, lambda d: d.arc(sc([(px - rx + 1, py - 19), (px + rx - 1, py + 14)]), 12, 168, fill=(222, 228, 228, 200), width=S), blur=0.5, clip=dome)
    tint(c, lambda d: d.arc(sc([(px - rx + 2, py - 42), (px + rx - 2, py + 40)]), 200, 300, fill=(238, 242, 240, 190), width=int(1.4 * S)), blur=0.8, clip=dome)
    tint(c, lambda d: d.ellipse(sc([(px - 74, py - 36), (px - 14, py - 20)]), fill=(240, 244, 240, 55)), blur=6, clip=dome)        # fényfolt
    for i, (fx, fy, rw) in enumerate(FIELDS):
        x, y, rh = px + fx, py + fy, rw * 0.40
        tint(c, lambda d: d.ellipse(sc([(x - rw, y - rh), (x + rw, y + rh)]), fill=(70, 78, 82, 150)), blur=0.8, clip=dome)        # bemélyedés
        tint(c, lambda d: d.arc(sc([(x - rw, y - rh), (x + rw, y + rh)]), 190, 350, fill=(52, 58, 62, 255), width=int(1.3 * S)), blur=0.4, clip=dome)
        tint(c, lambda d: d.arc(sc([(x - rw, y - rh), (x + rw, y + rh)]), 20, 160, fill=(226, 232, 232, 220), width=int(1.2 * S)), blur=0.4, clip=dome)
        if i == 0:
            tint(c, lambda d: d.ellipse(sc([(x - 7, y - 4), (x + 7, y + 3)]), fill=(214, 220, 220, 230)), blur=0.8, clip=dome)      # a „ding” púpja
        else:
            tint(c, lambda d: d.ellipse(sc([(x - rw * 0.4, y - rh * 0.4), (x + rw * 0.4, y + rh * 0.4)]), fill=(56, 62, 66, 200)), blur=0.6, clip=dome)
    return finish(c, 40)


# a karok fázisai: (könyök, csukló, a kézfej iránya fokban) – 0 fent lebeg, 1 félúton, 2 a hangmezőn
ARMS = {
    "b": {"váll": (276, 132), "fázis": [((250, 208), (286, 222), 20), ((250, 210), (284, 236), 34), ((250, 212), (282, 248), 44)], "seed": 21},
    "j": {"váll": (384, 132), "fázis": [((410, 206), (366, 214), 160), ((410, 208), (364, 228), 148), ((410, 210), (360, 240), 138)], "seed": 31},
}


def arm(side, phase):
    import math
    c = new()
    a = ARMS[side]
    sh = a["váll"]
    el, wr, ang = a["fázis"][phase]
    amb = 0.84 if side == "b" else 0.70
    part(c, lambda d: capsule(d, sh, el, 15.5, 12.5), SKIN, round_r=9, k=1.1, seed=a["seed"], ambient=amb)
    part(c, lambda d: capsule(d, el, wr, 12.5, 8.5), SKIN, round_r=8, k=1.1, seed=a["seed"] + 1, ambient=amb)
    r = math.radians(ang)
    dx, dy = math.cos(r), math.sin(r)
    nx, ny = -dy, dx
    palm = (wr[0] + dx * 10, wr[1] + dy * 10)
    part(c, lambda d: capsule(d, wr, palm, 9, 10.5), SKIN, round_r=6, k=1.0, seed=a["seed"] + 2, ambient=amb)
    curl = (0.0, 0.15, 0.3)[phase]              # lecsapáskor az ujjak a hangszerre simulnak
    for f in range(4):
        off = (f - 1.5) * 5.2
        base = (palm[0] + dx * 7 + nx * off, palm[1] + dy * 7 + ny * off)
        ln = 18 - abs(f - 1.5) * 2.4
        tip = (base[0] + dx * ln, base[1] + dy * ln + 4 * curl + 2)
        part(c, lambda d, base=base, tip=tip: capsule(d, base, tip, 2.9, 2.3), SKIN, round_r=2.5, k=0.9, seed=a["seed"] + 3 + f,
             ambient=amb - 0.04 * (f % 2))
    s = 1 if side == "b" else -1
    tb = (palm[0] - nx * 9 * s, palm[1] - ny * 9 * s)
    part(c, lambda d: capsule(d, tb, (tb[0] + dx * 9 - nx * 4 * s, tb[1] + dy * 9 - ny * 4 * s), 3.4, 2.6), SKIN, round_r=3, k=0.9,
         seed=a["seed"] + 9, ambient=amb - 0.05)
    return finish(c, 24)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    body().save(OUT / "jatekos.png")
    pan().save(OUT / "handpan.png")
    for side in ("b", "j"):
        for ph in range(3):
            arm(side, ph).save(OUT / f"kar_{side}_{ph}.png")
    print("kész:", OUT)
