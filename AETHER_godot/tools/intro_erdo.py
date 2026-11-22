"""A kezdőanimáció nyitányának festett pixeles képei: mohos erdő, ülő handpan-játékos, handpan.

Saját, kódból festett képek (nem fénykép vagy videókocka feldolgozása): a kompozíció egy
erdőben, mohos sziklák és páfrányok között ülő, ujjatlan vászoninges játékost mutat közelről,
ölében a hangszerrel. A karokat és a kezeket a játék rajzolja és mozgatja (scripts/intro.gd).

Kimenet (640×360, a játék 2,5-szeresre nagyítja):
  assets/intro/erdo.png      a háttér
  assets/intro/jatekos.png   a törzs, a fej és a térdek (átlátszó háttérrel)
  assets/intro/handpan.png   a hangszer (átlátszó háttérrel)

Kell hozzá: Pillow és numpy.   Használat:  python tools/intro_erdo.py
"""
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W, H = 640, 360
OUT = Path(__file__).resolve().parent.parent / "assets" / "intro"
rnd = random.Random(7)


def noise(shape, scale, seed):
    """Sima zaj 0..1 között (kis véletlen kép felnagyítva)."""
    r = np.random.default_rng(seed)
    small = r.random((max(2, shape[0] // scale), max(2, shape[1] // scale)))
    img = Image.fromarray((small * 255).astype("uint8")).resize((shape[1], shape[0]), Image.BICUBIC)
    return np.asarray(img).astype("float32") / 255.0


def fern(d, x, y, length, angle, col, col2, leaf=9.0, bend=0.9):
    """Egy páfránylevél: ívelt szár, kétoldalt rövidülő levélkék."""
    px, py, a = x, y, angle
    n = int(length / 2)
    for i in range(n):
        t = i / n
        a += bend * (1 if angle > -math.pi / 2 else -1) * 0.022
        nx, ny = px + math.cos(a) * 2, py + math.sin(a) * 2
        d.line([px, py, nx, ny], fill=col, width=1)
        if i % 2 == 0 and i > 2:
            ll = leaf * (1 - t) ** 0.8 * (0.5 + min(1.0, t * 5) * 0.5)
            for side in (-1, 1):
                la = a + side * 1.25
                d.line([nx, ny, nx + math.cos(la) * ll, ny + math.sin(la) * ll + ll * 0.18],
                       fill=col2 if (i // 2) % 2 else col, width=1)
        px, py = nx, ny


def fern_bush(d, x, y, size, col, col2, count=7, spread=2.4):
    for k in range(count):
        a = -math.pi / 2 + (k / (count - 1) - 0.5) * spread + rnd.uniform(-0.12, 0.12)
        fern(d, x, y, size * rnd.uniform(0.75, 1.1), a, col, col2, leaf=size * 0.16)


def background():
    # 1. távoli, elmosott erdő: sötét zöld foltok, törzsek, mohos sziklák
    far = Image.new("RGB", (W, H), (9, 20, 13))
    d = ImageDraw.Draw(far)
    for _ in range(170):
        x, y = rnd.uniform(-40, W + 40), rnd.uniform(-30, H * 0.8)
        r = rnd.uniform(18, 70)
        g = rnd.uniform(0.25, 1.0) * (0.55 + 0.45 * y / H)
        d.ellipse([x - r, y - r * 0.6, x + r, y + r * 0.6], fill=(int(14 + 22 * g), int(30 + 58 * g), int(16 + 20 * g)))
    for x, w in ((38, 26), (120, 16), (232, 22), (402, 18), (548, 30), (610, 14), (300, 10)):
        d.rectangle([x, -5, x + w, rnd.uniform(110, 190)], fill=(8, 14, 10))
        d.rectangle([x + 2, -5, x + w * 0.4, 150], fill=(22, 44, 22))       # mohás oldal
    far = far.filter(ImageFilter.GaussianBlur(7))
    # 2. mohos sziklák: kevésbé elmosva
    mid = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(mid)
    rocks = [(-30, 150, 190, 150), (120, 205, 150, 90), (430, 120, 200, 120), (520, 200, 190, 130),
             (20, 250, 170, 100), (395, 235, 130, 80)]
    for x, y, w, h in rocks:
        d.ellipse([x, y, x + w, y + h], fill=(16, 30, 20, 255))
        for _ in range(int(w * h / 55)):                                    # mohapárna a tetején
            mx = x + rnd.uniform(0.05, 0.95) * w
            my = y + rnd.uniform(0.0, 0.55) * h
            if ((mx - x - w / 2) / (w / 2)) ** 2 + ((my - y - h / 2) / (h / 2)) ** 2 < 1:
                k = 1 - (my - y) / (h * 0.6)
                c = (int(26 + 34 * k + rnd.uniform(-6, 6)), int(58 + 62 * k + rnd.uniform(-10, 10)), int(26 + 16 * k))
                rr = rnd.uniform(2, 6)
                d.ellipse([mx - rr, my - rr * 0.7, mx + rr, my + rr * 0.7], fill=c + (255,))
    mid = mid.filter(ImageFilter.GaussianBlur(2.2))
    far.paste(mid, (0, 0), mid)
    # 3. távolabbi páfrányok (kissé elmosva)
    f1 = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(f1)
    for x, y, s in ((70, 150, 46), (190, 120, 40), (560, 150, 52), (610, 250, 60), (500, 70, 36), (250, 60, 30), (30, 60, 40)):
        fern_bush(d, x, y, s, (34, 84, 44, 255), (44, 104, 52, 255))
    f1 = f1.filter(ImageFilter.GaussianBlur(1.1))
    far.paste(f1, (0, 0), f1)
    # 4. közeli páfrányok a játékos mögött és a széleken (élesek)
    d = ImageDraw.Draw(far)
    fern_bush(d, 452, 262, 150, (40, 100, 50), (58, 132, 62), count=9, spread=2.0)
    fern_bush(d, 414, 300, 110, (34, 88, 44), (50, 118, 56), count=6, spread=1.7)
    fern_bush(d, 28, 330, 120, (36, 92, 46), (54, 124, 58), count=7, spread=2.2)
    fern_bush(d, 618, 180, 90, (38, 96, 48), (56, 128, 60), count=6, spread=2.0)
    fern_bush(d, 160, 300, 70, (32, 84, 42), (48, 112, 54), count=6, spread=2.3)
    for _ in range(26):                                                     # vékony fűszálak
        x, y = rnd.uniform(380, 470), rnd.uniform(60, 200)
        d.line([x, y + 60, x + rnd.uniform(-6, 6), y], fill=(46, 96, 50), width=1)
    # 5. talaj: sötét avar, borostyán- és lóherelevelek
    px = np.asarray(far).astype("float32")
    yy = np.linspace(0, 1, H)[:, None]
    ground = np.clip((yy - 0.70) / 0.2, 0, 1)[..., None]
    px = px * (1 - ground * 0.55)
    far = Image.fromarray(px.clip(0, 255).astype("uint8"))
    d = ImageDraw.Draw(far)
    for _ in range(420):
        x, y = rnd.uniform(0, W), rnd.uniform(H * 0.70, H)
        if 215 < x < 430 and y > 300:
            continue
        k = rnd.uniform(0.4, 1.0)
        c = (int(30 + 40 * k), int(72 + 76 * k), int(34 + 26 * k))
        r = rnd.choice((1, 1, 2, 2, 3))
        d.ellipse([x - r, y - r * 0.7, x + r, y + r * 0.7], fill=c)
        if r > 1:
            d.point([x, y], fill=(int(c[0] * 0.6), int(c[1] * 0.6), int(c[2] * 0.6)))
    # 6. fény fentről, finom zaj, szegélysötétítés, hűvös zöld tónus
    px = np.asarray(far).astype("float32")
    n = noise((H, W), 3, 5)[..., None]
    px *= 0.86 + 0.28 * n
    xx = np.linspace(-1, 1, W)[None, :]
    yv = np.linspace(-1, 1, H)[:, None]
    light = np.exp(-(((xx - 0.15) / 0.75) ** 2 + ((yv + 0.25) / 0.85) ** 2))[..., None]
    px *= 0.42 + 0.78 * light
    px[..., 2] *= 1.08
    px[..., 0] *= 0.94
    img = Image.fromarray(px.clip(0, 255).astype("uint8"))
    return img.quantize(colors=64, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")


def shade_fill(img, mask_draw, base, light_dir=(-0.6, -0.6), strength=0.35, seed=1, grain=0.06):
    """Alakzat kitöltése bal-felső fénnyel és finom szemcsével; mask_draw(d) rajzolja a maszkot."""
    m = Image.new("L", (W, H), 0)
    mask_draw(ImageDraw.Draw(m))
    mk = np.asarray(m).astype("float32") / 255.0
    ys, xs = np.nonzero(mk > 0)
    if len(xs) == 0:
        return
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    gx = (np.arange(W)[None, :] - (x0 + x1) / 2) / max(1, (x1 - x0) / 2)
    gy = (np.arange(H)[:, None] - (y0 + y1) / 2) / max(1, (y1 - y0) / 2)
    l = 1.0 + strength * (gx * light_dir[0] + gy * light_dir[1]) + (noise((H, W), 2, seed) - 0.5) * grain * 2
    arr = np.asarray(img).astype("float32")
    col = np.array(base, dtype="float32")[None, None, :] * l[..., None]
    a = mk[..., None]
    arr[..., :3] = arr[..., :3] * (1 - a) + col.clip(0, 255) * a
    arr[..., 3] = np.maximum(arr[..., 3], mk * 255)
    img.paste(Image.fromarray(arr.clip(0, 255).astype("uint8"), "RGBA"))


def player():
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    skin, skin_d = (178, 132, 100), (128, 90, 68)
    shirt = (190, 176, 150)
    trousers = (92, 80, 58)
    cx = 350
    # combok / nadrág: a hangszer alatt kétoldalt kifelé futnak
    shade_fill(img, lambda d: d.polygon([(214, 360), (232, 318), (286, 286), (420, 282), (470, 312), (492, 360)], fill=255),
               trousers, strength=0.35, seed=11)
    # nyak és csuklyásizom: a nyaktól a vállakig lejt
    shade_fill(img, lambda d: d.polygon([(337, 78), (365, 78), (370, 98), (402, 110), (410, 124), (290, 124), (298, 110), (332, 98)], fill=255),
               skin_d, strength=0.25, seed=13)
    # ujjatlan vászoning: széles karkivágás, enyhén bő
    shade_fill(img, lambda d: d.polygon([(318, 103), (332, 108), (350, 122), (368, 108), (382, 103), (392, 118), (398, 150),
                                         (412, 190), (410, 250), (404, 300), (296, 300), (290, 250), (288, 190), (302, 150),
                                         (308, 118)], fill=255), shirt, strength=0.34, seed=12, grain=0.05)
    d = ImageDraw.Draw(img)
    for pts in ([(308, 150), (314, 200), (310, 262)], [(332, 150), (338, 210), (334, 280)], [(376, 140), (384, 200), (380, 270)],
                [(396, 170), (400, 230), (396, 290)], [(352, 128), (356, 180)], [(320, 120), (326, 146)]):
        d.line(pts, fill=(150, 138, 116, 255), width=1)                      # redők
    d.line([(318, 103), (332, 108), (350, 122), (368, 108), (382, 103)], fill=(146, 134, 112, 255), width=2)   # nyakkivágás
    d.line([(308, 118), (302, 150), (290, 190)], fill=(150, 138, 116, 255), width=1)
    d.line([(392, 118), (398, 150), (410, 190)], fill=(128, 118, 98, 255), width=2)
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))                          # árnyék az ing jobb oldalán és az áll alatt
    sd = ImageDraw.Draw(shadow)
    sd.polygon([(372, 104), (398, 118), (412, 190), (408, 300), (376, 300)], fill=(20, 24, 18, 70))
    sd.ellipse([330, 88, 372, 112], fill=(20, 16, 12, 80))
    shadow = shadow.filter(ImageFilter.GaussianBlur(4))
    mask0 = img.split()[3].point(lambda v: 255 if v > 0 else 0)
    img.paste(Image.alpha_composite(img, shadow), (0, 0), mask0)
    # fej: koponya és állkapocs, enyhén lehajtva
    def head(dd):
        dd.ellipse([cx - 24, 18, cx + 22, 70], fill=255)
        dd.polygon([(cx - 23, 48), (cx + 21, 48), (cx + 16, 78), (cx + 6, 90), (cx - 8, 90), (cx - 18, 78)], fill=255)
    shade_fill(img, head, skin, strength=0.36, seed=14, grain=0.04)
    mask = img.split()[3].point(lambda v: 255 if v > 0 else 0)
    over = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(over)
    od.pieslice([cx - 26, 14, cx + 24, 64], 180, 360, fill=(70, 52, 40, 120))      # nagyon rövid haj a fejtetőn
    od.polygon([(cx + 8, 40), (cx + 24, 40), (cx + 18, 88), (cx + 6, 92)], fill=(30, 20, 14, 70))   # az arc árnyékos fele
    od.ellipse([cx - 20, 70, cx + 18, 94], fill=(84, 62, 48, 90))                 # borosta
    od.ellipse([cx - 16, 52, cx - 2, 62], fill=(60, 40, 30, 60))                  # szemgödrök
    od.ellipse([cx + 2, 52, cx + 16, 62], fill=(60, 40, 30, 70))
    over = over.filter(ImageFilter.GaussianBlur(1.6))
    img.paste(Image.alpha_composite(img, over), (0, 0), mask)
    d = ImageDraw.Draw(img)
    d.ellipse([cx + 19, 48, cx + 26, 64], fill=skin_d + (255,))                    # fülek
    d.ellipse([cx - 28, 50, cx - 22, 64], fill=skin + (255,))
    for ex in (cx - 14, cx + 4):                                                  # lehunyt szem, szemöldök – egyszerű, nem portré
        d.line([ex, 59, ex + 9, 60], fill=(70, 46, 36, 255), width=1)
        d.line([ex - 1, 53, ex + 10, 52], fill=(96, 70, 54, 255), width=1)
    d.line([cx - 2, 56, cx - 4, 70], fill=skin_d + (255,), width=1)                # orr
    d.line([cx - 6, 71, cx + 1, 71], fill=skin_d + (255,), width=1)
    d.line([cx - 8, 79, cx + 4, 79], fill=(112, 70, 58, 255), width=1)             # száj
    return quant(img, 48)


def handpan():
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px, py = 300, 250
    # alsó héj: bronzos, a perem alatt
    shade_fill(img, lambda d: d.chord([px - 76, py - 34, px + 76, py + 62], 0, 180, fill=255), (150, 104, 72),
               light_dir=(-0.3, -0.9), strength=0.55, seed=21)
    # felső kupola: acélszürke
    shade_fill(img, lambda d: d.ellipse([px - 76, py - 34, px + 76, py + 30], fill=255), (150, 158, 160),
               light_dir=(-0.45, -0.75), strength=0.34, seed=22, grain=0.03)
    d = ImageDraw.Draw(img)
    d.arc([px - 76, py - 34, px + 76, py + 30], 5, 175, fill=(96, 72, 54, 255), width=2)          # perem
    d.arc([px - 75, py - 33, px + 75, py + 29], 200, 330, fill=(206, 212, 212, 255), width=1)     # csillanás
    # középső „ding” és a hangmezők
    d.ellipse([px - 14, py - 14, px + 14, py - 2], fill=(128, 136, 138, 255))
    d.ellipse([px - 6, py - 11, px + 6, py - 5], fill=(176, 184, 186, 255))
    d.arc([px - 14, py - 14, px + 14, py - 2], 20, 160, fill=(92, 98, 102, 255), width=1)
    for fx, fy, rw in FIELDS[1:]:
        d.ellipse([px + fx - rw, py + fy - rw * 0.45, px + fx + rw, py + fy + rw * 0.45], fill=(118, 126, 130, 255))
        d.ellipse([px + fx - rw * 0.45, py + fy - rw * 0.2, px + fx + rw * 0.45, py + fy + rw * 0.2], fill=(96, 104, 108, 255))
        d.arc([px + fx - rw, py + fy - rw * 0.45, px + fx + rw, py + fy + rw * 0.45], 190, 340, fill=(196, 204, 206, 255), width=1)
    return quant(img, 32)


# a hangmezők helye a hangszer közepéhez képest: (x, y, félszélesség); az első a középső „ding”
FIELDS = [(0, -8, 14), (-50, -6, 11), (-32, -22, 10), (4, -27, 10), (38, -20, 10), (52, -3, 11), (28, 12, 12), (-26, 13, 12)]


def quant(img, colors):
    a = img.split()[3].point(lambda v: 255 if v > 127 else 0)
    rgb = img.convert("RGB").quantize(colors=colors, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")
    rgb.putalpha(a)
    return rgb


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    background().save(OUT / "erdo.png")
    player().save(OUT / "jatekos.png")
    handpan().save(OUT / "handpan.png")
    print("kész:", OUT)
