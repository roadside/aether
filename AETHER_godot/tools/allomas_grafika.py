"""A kutatóállomás festett pixeles képei (saját rajz, programból, külső csomag nélkül).

Egy háttér (éjszakai ég sarki fénnyel, réteges hegyek, fenyőerdő, domb, alapzat
napelemekkel és lámpákkal), modulonként 4 szint (0 = üres telek, 1-3 = egyre
nagyobb, részletesebb épület), és egy állvány-kép az épülő modulhoz.
A Godot a hátteret és a modulokat egymásra teszi, és nagyítja (éles, pixeles);
a pislákoló fényeket és a növények mozgását a station_panel.gd rajzolja rá.

Használat:  python allomas_grafika.py <kimeneti assets/allomas mappa>
"""
from __future__ import annotations

import math
import random
import struct
import sys
import zlib
from pathlib import Path

W, H = 200, 110          # háttér
MW, MH = 56, 56          # egy modul
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def hexc(h: str, a: int = 255):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (a,)


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3)) + (255,)


def dith(x, y, t, a, b):
    """Két szín rendezett ditherrel: t = 0..1 a b aránya."""
    return b if BAYER[y % 4][x % 4] < t * 16 else a


def save_png(path: Path, w: int, h: int, px: list) -> None:
    """Egyszerű RGBA PNG-író (a Pillow nem kell hozzá)."""
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            raw.extend(px[y * w + x])
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    path.write_bytes(png)


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [(0, 0, 0, 0)] * (w * h)

    def put(self, x, y, c):
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y * self.w + x] = c

    def get(self, x, y):
        return self.px[y * self.w + x]

    def rect(self, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.put(x, y, c)

    def save(self, path: Path) -> None:
        save_png(path, self.w, self.h, self.px)

    def shaded_box(self, x0, y0, x1, y1, base, light, dark, outline):
        """Doboz: fent-balra fény, lent-jobbra árnyék (ditherrel), sötét körvonal."""
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                t = (x - x0) / max(1, x1 - x0)
                v = (y - y0) / max(1, y1 - y0)
                c = dith(x, y, (t - 0.65) * 1.8, base, dark) if t > 0.65 else base
                if v > 0.85:
                    c = dith(x, y, 0.5, c, dark)
                self.put(x, y, c)
        for x in range(x0, x1 + 1):
            self.put(x, y0, light)
        for y in range(y0, y1 + 1):
            self.put(x0, y, light)
        for x in range(x0 - 1, x1 + 2):
            self.put(x, y0 - 1, outline)
            self.put(x, y1 + 1, outline)
        for y in range(y0 - 1, y1 + 2):
            self.put(x0 - 1, y, outline)
            self.put(x1 + 1, y, outline)

    def dome(self, cx, cy, r, base, light, dark, outline, glass=False):
        """Félgömb kupola (cy = alapvonal)."""
        for y in range(cy - r, cy + 1):
            for x in range(cx - r, cx + r + 1):
                d = math.hypot(x - cx, (y - cy) * 1.15)
                if d <= r:
                    lx = (x - cx + r * 0.5) ** 2 + (y - cy + r * 0.7) ** 2
                    t = min(1.0, math.sqrt(lx) / (r * 1.6))
                    c = dith(x, y, t, light if t < 0.35 else base, dark if t > 0.7 else base)
                    if glass and (x - y) % 5 == 0:
                        c = mix(c, light, 0.6)
                    self.put(x, y, c)
                elif d <= r + 1:
                    self.put(x, y, outline)


def background(o: Path) -> None:
    rnd = random.Random(3)
    c = Canvas(W, H)
    top, mid, low = hexc("#050816"), hexc("#101a36"), hexc("#1d2a4c")
    for y in range(H):
        for x in range(W):
            t = y / H
            c.put(x, y, dith(x, y, t * 1.6, top, mid) if t < 0.6 else dith(x, y, (t - 0.6) * 2.5, mid, low))
    # sarki fény (zöldes-türkiz függöny), ditherrel elhalványulva
    for x in range(W):
        base = 18 + 7 * math.sin(x / 13.0) + 4 * math.sin(x / 5.3 + 2)
        for y in range(int(base) - 12, int(base) + 10):
            if y < 0:
                continue
            d = abs(y - base) / 11.0
            fade = (1 - d) * (0.55 + 0.45 * math.sin(x / 9.0 + 1.3))
            if fade > 0:
                col = mix(c.get(x, y), hexc("#3ddc9f") if y > base else hexc("#4aa8e0"), fade * 0.55)
                c.put(x, y, dith(x, y, fade * 0.9, c.get(x, y), col))
    for _ in range(95):   # csillagok
        x, y = rnd.randrange(W), rnd.randrange(int(H * 0.55))
        c.put(x, y, hexc("#eef3ff") if rnd.random() < 0.25 else hexc("#7d8bb0"))
    # hold, kráterekkel
    for y in range(6, 24):
        for x in range(158, 178):
            d = math.hypot(x - 167.5, y - 14.5)
            if d <= 7.0:
                shade = math.hypot(x - 165, y - 12) / 9.5
                col = dith(x, y, shade, hexc("#f5eed6"), hexc("#b4ae96"))
                if (x, y) in [(165, 12), (166, 12), (169, 16), (170, 16), (167, 18)]:
                    col = hexc("#cfc8ad")
                c.put(x, y, col)
            elif d <= 9.0:   # halvány udvar
                c.put(x, y, dith(x, y, 0.25, c.get(x, y), hexc("#2c3a63")))
    # távoli és közeli hegyek (két réteg), hófödte csúcsokkal
    for layer, (h0, a1, a2, col1, col2) in enumerate([(56, 9, 5, "#1a2746", "#22335a"), (64, 7, 4, "#16233d", "#1e2e4e")]):
        for x in range(W):
            h = int(h0 + a1 * math.sin(x / (17.0 - 4 * layer) + layer) + a2 * math.sin(x / 7.3 + 1 + layer))
            for y in range(h, H):
                c.put(x, y, dith(x, y, 0.35, hexc(col1), hexc(col2)))
            if layer == 0 and h < h0 - 6:
                for y in range(h, h + 2):
                    c.put(x, y, hexc("#9fb0d4"))
    # fenyőerdő a domb mögött
    for x0 in range(2, W, 5):
        th = 6 + rnd.randrange(6)
        base = 78 - int(6 * math.exp(-((x0 - W / 2) / 70.0) ** 2))
        for i in range(th):
            half = max(0, (i * 3) // th + (i % 2))
            for dx in range(-half, half + 1):
                c.put(x0 + dx, base - th + i, hexc("#0f2a22") if dx < 1 else hexc("#0b2019"))
    # domb
    g1, g2, g3 = hexc("#1f4a3a"), hexc("#2c6447"), hexc("#163528")
    for x in range(W):
        h = int(80 - 10 * math.exp(-((x - W / 2) / 70.0) ** 2) + 2 * math.sin(x / 5.0))
        for y in range(h, H):
            t = (y - h) / max(1, H - h)
            c.put(x, y, dith(x, y, t, g2 if y < h + 2 else g1, g3))
        c.put(x, h, hexc("#4c8a5c"))
        if rnd.random() < 0.12:   # fűcsomók
            c.put(x, h - 1, hexc("#5fa86e"))
    # ösvény az alapzathoz
    for y in range(91, H):
        w = 3 + (y - 91) // 3
        for x in range(100 - w, 100 + w):
            c.put(x, y, dith(x, y, 0.4, hexc("#5a5446"), hexc("#3e392f")))
    # alapzat (beton platform) jelzőfényekkel
    c.shaded_box(16, 84, 184, 90, hexc("#3a4258"), hexc("#5d6784"), hexc("#262c3d"), hexc("#11141e"))
    for x in range(20, 182, 6):
        c.put(x, 87, hexc("#3a4258"))
    # napelemek az alapzat két szélén
    for px0 in (4, 186):
        for i in range(3):
            x0 = px0 + i * 3
            for y in range(76, 83):
                for x in range(x0, x0 + 3):
                    c.put(x, y + (x - x0) // 2, dith(x, y, 0.3, hexc("#1d3f7a"), hexc("#3a6fc0")))
            c.put(x0 + 1, 83, hexc("#8a93a8"))
    # lámpaoszlopok
    for lx in (12, 188):
        for y in range(70, 84):
            c.put(lx, y, hexc("#6d7690"))
        c.put(lx - 1, 69, hexc("#6d7690"))
        c.put(lx, 69, hexc("#ffd97a"))
    # parabolaantenna
    cx, cy = 194, 64
    for y in range(cy, cy + 14):
        c.put(cx, y, hexc("#8a93a8"))
    for a in range(-6, 7):
        c.put(cx - 4 + abs(a) // 3, cy - 3 + a // 2, hexc("#c9d2e6"))
    c.save(o / "hatter.png")


def site(c: Canvas) -> None:
    """0. szint: kijelölt telek, cövekek, szalag."""
    line = hexc("#6f7da0")
    for x in range(8, 48, 2):
        c.put(x, 53, line)
        c.put(x, 36, line)
    for x in (8, 47):
        for y in range(36, 54, 2):
            c.put(x, y, line)
    for x in range(9, 47, 4):   # piros-fehér szalag
        c.put(x, 44, hexc("#e05a4a"))
        c.put(x + 1, 44, hexc("#eeeeee"))


def scaffold(o: Path) -> None:
    """Állvány a modul elé, amíg épül (a Godot a modul fölé teszi)."""
    c = Canvas(MW, MH)
    pole, plank, ol = hexc("#d9a441"), hexc("#8a6a3a"), hexc("#3a2a12")
    for x in (6, 18, 30, 42, 50):
        for y in range(14, 54):
            c.put(x, y, pole)
    for y in (22, 34, 46):
        for x in range(5, 52):
            c.put(x, y, plank)
            c.put(x, y + 1, ol)
    for k in range(4):   # ferde merevítők
        for i in range(12):
            c.put(6 + k * 12 + i, 34 - i, pole)
    # daru
    for y in range(2, 54):
        c.put(53, y, hexc("#f0c040"))
    for x in range(30, 56):
        c.put(x, 3, hexc("#f0c040"))
    for y in range(4, 14):
        c.put(36, y, hexc("#9aa7c4"))
    c.rect(34, 14, 38, 16, hexc("#6b7690"))
    c.save(o / "allvany.png")


def ai_core(o: Path) -> None:
    for lvl in range(4):
        c = Canvas(MW, MH)
        if lvl == 0:
            site(c)
        else:
            body, light, dark, ol = hexc("#2b4f7a"), hexc("#6a9fd8"), hexc("#18304d"), hexc("#0a1220")
            w = 12 + 4 * lvl
            x0, x1 = 28 - w, 27 + w
            top = 54 - (8 + 5 * lvl)
            c.shaded_box(x0, top, x1, 53, body, light, dark, ol)
            # szerverszekrények: sötét rések, fények sorokban
            for row in range(top + 2, 52, 3):
                for x in range(x0 + 2, x1 - 1):
                    c.put(x, row + 1, hexc("#13233a"))
                for x in range(x0 + 2, x1 - 1, 3):
                    c.put(x, row, hexc("#56e0ff") if (x + row) % 7 else hexc("#f4c85a"))
            # hűtőbordák oldalt
            for y in range(top + 1, 53, 2):
                c.put(x1 + 2, y, hexc("#9aa7c4"))
            # kupola
            c.dome(28, top - 1, 6 + 2 * lvl, hexc("#3b6aa3"), hexc("#c2e2ff"), hexc("#1d3a60"), ol, glass=True)
            # antennák villogó csúccsal
            for k in range(lvl):
                ax = int(28 + (k - (lvl - 1) / 2) * 9)
                ay = top - 8 - 2 * lvl
                for y in range(ay, top - 3):
                    c.put(ax, y, hexc("#9aa7c4"))
                c.put(ax, ay - 1, hexc("#ff6b5a"))
            # bejárat fénnyel
            c.rect(25, 48, 30, 53, hexc("#0e1b2e"))
            c.rect(26, 49, 29, 49, hexc("#56e0ff"))
        c.save(o / f"ai_mag_{lvl}.png")


def archive(o: Path) -> None:
    for lvl in range(4):
        c = Canvas(MW, MH)
        if lvl == 0:
            site(c)
        else:
            body, light, dark, ol = hexc("#6b4d34"), hexc("#b38a62"), hexc("#43301f"), hexc("#1a120b")
            floors = lvl
            w = 14 + 2 * lvl
            x0, x1 = 28 - w, 27 + w
            top = 53 - 10 * floors
            c.shaded_box(x0, top, x1, 53, body, light, dark, ol)
            # téglasorok
            for y in range(top + 2, 53, 3):
                for x in range(x0 + 1 + (y // 3) % 2 * 2, x1, 5):
                    c.put(x, y, dark)
            for f in range(floors):   # ablaksorok (meleg fény: könyvtár, könyvespolcok)
                y = top + 3 + 10 * f
                for x in range(x0 + 3, x1 - 2, 5):
                    c.rect(x, y, x + 2, y + 4, hexc("#f4c85a"))
                    c.put(x + 1, y + 2, hexc("#c08a2e"))
                    c.put(x, y + 4, hexc("#8a3b32"))
                    c.put(x + 2, y + 4, hexc("#3b6a8a"))
            # oszlopos előtető
            for i in range(5):
                for x in range(x0 - 2 + i, x1 + 3 - i):
                    c.put(x, top - 2 - i, hexc("#8a3b32") if i < 4 else ol)
            for x in range(x0 + 1, x1, 2):
                c.put(x, top - 3, hexc("#a8503f"))
            c.rect(25, 46, 30, 53, hexc("#2a1d12"))   # ajtó
            c.put(29, 50, hexc("#f4c85a"))
        c.save(o / f"archivum_{lvl}.png")


def greenhouse(o: Path) -> None:
    rnd = random.Random(5)
    for lvl in range(4):
        c = Canvas(MW, MH)
        if lvl == 0:
            site(c)
        else:
            frame, ol = hexc("#d4e0ef"), hexc("#0b1a14")
            n = lvl   # egymás melletti üvegházak száma
            width = 13
            gap = 1
            total = n * width + (n - 1) * gap
            start = 28 - total // 2
            for k in range(n):
                x0 = start + k * (width + gap)
                h = 12 + 3 * lvl
                for y in range(53 - h, 54):
                    for x in range(x0, x0 + width):
                        t = (y - (53 - h)) / h
                        c.put(x, y, dith(x, y, t, hexc("#3a8084"), hexc("#1d4d52")))
                # növénysorok: szár + levél + termés
                for _ in range(10 + 4 * lvl):
                    px = x0 + 1 + rnd.randrange(width - 2)
                    ph = 2 + rnd.randrange(h // 2)
                    for y in range(53 - ph, 54):
                        c.put(px, y, hexc("#3f9a4f"))
                    c.put(px, 53 - ph, hexc("#7fe07a"))
                    if rnd.random() < 0.3:
                        c.put(px, 53 - ph - 1, hexc("#f4c85a") if rnd.random() < 0.5 else hexc("#ff7a5a"))
                # íves tető és bordák, csillanással
                for x in range(x0, x0 + width):
                    rr = abs(x - (x0 + width / 2 - 0.5)) / (width / 2)
                    ry = 53 - h - int(4 * (1 - rr * rr))
                    for y in range(ry, 53 - h):
                        c.put(x, y, dith(x, y, 0.5, hexc("#4aa0a2"), hexc("#b8efe9")))
                    c.put(x, ry - 1, ol)
                for x in range(x0, x0 + width, 4):
                    for y in range(53 - h, 54):
                        c.put(x, y, frame)
                for y in range(53 - h, 54):
                    c.put(x0 - 1, y, ol)
                    c.put(x0 + width, y, ol)
                c.put(x0 + 2, 53 - h + 2, hexc("#ffffff"))   # csillanás
        c.save(o / f"uveghaz_{lvl}.png")


def main(out: str) -> None:
    o = Path(out)
    o.mkdir(parents=True, exist_ok=True)
    background(o)
    scaffold(o)
    ai_core(o)
    archive(o)
    greenhouse(o)
    print("kész:", o)


if __name__ == "__main__":
    main(sys.argv[1])
