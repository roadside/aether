"""A kutatóállomás festett pixeles képei (saját rajz, programból).

Egy háttér (éjszakai ég, domb, alapzat) és modulonként 4 szint (0 = üres telek,
1-3 = egyre nagyobb, részletesebb épület). A Godot a hátteret és a modulokat
egymásra teszi, és 4-szeresre nagyítja (éles, pixeles).

Használat:  python allomas_grafika.py <kimeneti assets/allomas mappa>
"""
from __future__ import annotations

import math
import random
import sys
from pathlib import Path

from PIL import Image

W, H = 200, 110          # háttér
MW, MH = 56, 56          # egy modul
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def hexc(h: str, a: int = 255):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (a,)


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3)) + (255,)


def dith(x, y, t, a, b):
    """Két szín rendezett ditherrel: t = 0..1 a b aránya."""
    return b if BAYER[y % 4][x % 4] < t * 16 else a


class Canvas:
    def __init__(self, w, h):
        self.im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.px = self.im.load()
        self.w, self.h = w, h

    def put(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[x, y] = c

    def rect(self, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.put(x, y, c)

    def shaded_box(self, x0, y0, x1, y1, base, light, dark, outline):
        """Doboz: fent-balra fény, lent-jobbra árnyék, sötét körvonal."""
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                t = (x - x0) / max(1, x1 - x0)
                self.put(x, y, dith(x, y, (t - 0.7) * 1.6, base, dark) if t > 0.7 else base)
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
                    if glass and (x + y) % 6 == 0:
                        c = light
                    self.put(x, y, c)
                elif d <= r + 1:
                    self.put(x, y, outline)


def background(o: Path) -> None:
    rnd = random.Random(3)
    c = Canvas(W, H)
    top, mid = hexc("#070b18"), hexc("#14213d")
    for y in range(H):
        for x in range(W):
            c.put(x, y, dith(x, y, y / H * 1.1, top, mid))
    for _ in range(70):   # csillagok
        x, y = rnd.randrange(W), rnd.randrange(int(H * 0.6))
        c.put(x, y, hexc("#e8eefc") if rnd.random() < 0.3 else hexc("#7d8bb0"))
    # hold
    for y in range(8, 22):
        for x in range(160, 176):
            d = math.hypot(x - 167.5, y - 14.5)
            if d <= 6.5:
                shade = math.hypot(x - 165, y - 12) / 9.0
                c.put(x, y, dith(x, y, shade, hexc("#f3ecd2"), hexc("#b9b39c")))
    # távoli hegyek
    far, far2 = hexc("#1d2b4a"), hexc("#243656")
    for x in range(W):
        h = int(62 + 8 * math.sin(x / 17.0) + 5 * math.sin(x / 7.3 + 1))
        for y in range(h, H):
            c.put(x, y, dith(x, y, 0.3, far, far2))
    # domb
    g1, g2, g3 = hexc("#1f4a3a"), hexc("#2c6447"), hexc("#163528")
    for x in range(W):
        h = int(80 - 10 * math.exp(-((x - W / 2) / 70.0) ** 2) + 2 * math.sin(x / 5.0))
        for y in range(h, H):
            t = (y - h) / max(1, H - h)
            c.put(x, y, dith(x, y, t, g2 if y < h + 2 else g1, g3))
        c.put(x, h, hexc("#4c8a5c"))
    # alapzat (beton platform)
    c.shaded_box(16, 84, 184, 90, hexc("#3a4258"), hexc("#5d6784"), hexc("#262c3d"), hexc("#11141e"))
    for x in range(20, 182, 6):   # jelzőfények
        c.put(x, 87, hexc("#f4c85a") if x % 12 == 2 else hexc("#3a4258"))
    c.im.save(o / "hatter.png")


def site(c: Canvas) -> None:
    """0. szint: kijelölt telek, állványzat."""
    line = hexc("#6f7da0")
    for x in range(8, 48, 2):
        c.put(x, 53, line)
    for x in (8, 47):
        for y in range(36, 54, 2):
            c.put(x, y, line)
    for y in range(36, 54, 2):
        c.put(27, y, hexc("#4a5675"))
    for x in range(8, 48, 2):
        c.put(x, 36, line)


def ai_core(o: Path) -> None:
    for lvl in range(4):
        c = Canvas(MW, MH)
        if lvl == 0:
            site(c)
        else:
            body, light, dark, ol = hexc("#2b4f7a"), hexc("#5d8fcb"), hexc("#18304d"), hexc("#0a1220")
            w = 12 + 4 * lvl
            x0, x1 = 28 - w, 27 + w
            top = 54 - (8 + 5 * lvl)
            c.shaded_box(x0, top, x1, 53, body, light, dark, ol)
            # szerverfények sorokban
            for row in range(top + 2, 52, 3):
                for x in range(x0 + 2, x1 - 1, 3):
                    c.put(x, row, hexc("#56e0ff") if (x + row) % 7 else hexc("#f4c85a"))
            # kupola
            c.dome(28, top - 1, 6 + 2 * lvl, hexc("#3b6aa3"), hexc("#a6d4ff"), hexc("#1d3a60"), ol, glass=True)
            # antennák
            for k in range(lvl):
                ax = 28 + (k - (lvl - 1) / 2) * 9
                ay = top - 8 - 2 * lvl
                for y in range(ay, top - 3):
                    c.put(int(ax), y, hexc("#9aa7c4"))
                c.put(int(ax), ay - 1, hexc("#ff6b5a"))
        c.im.save(o / f"ai_mag_{lvl}.png")


def archive(o: Path) -> None:
    for lvl in range(4):
        c = Canvas(MW, MH)
        if lvl == 0:
            site(c)
        else:
            body, light, dark, ol = hexc("#6b4d34"), hexc("#a9805a"), hexc("#43301f"), hexc("#1a120b")
            floors = lvl
            w = 14 + 2 * lvl
            x0, x1 = 28 - w, 27 + w
            top = 53 - 10 * floors
            c.shaded_box(x0, top, x1, 53, body, light, dark, ol)
            for f in range(floors):   # ablaksorok (meleg fény: könyvtár)
                y = top + 3 + 10 * f
                for x in range(x0 + 3, x1 - 2, 5):
                    c.rect(x, y, x + 2, y + 4, hexc("#f4c85a"))
                    c.put(x + 1, y + 2, hexc("#c08a2e"))
            # tető
            for i in range(5):
                for x in range(x0 - 2 + i, x1 + 3 - i):
                    c.put(x, top - 2 - i, hexc("#8a3b32") if i < 4 else ol)
            c.rect(26, 47, 29, 53, hexc("#2a1d12"))   # ajtó
        c.im.save(o / f"archivum_{lvl}.png")


def greenhouse(o: Path) -> None:
    rnd = random.Random(5)
    for lvl in range(4):
        c = Canvas(MW, MH)
        if lvl == 0:
            site(c)
        else:
            frame, ol = hexc("#c9d6e8"), hexc("#0b1a14")
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
                        c.put(x, y, dith(x, y, t, hexc("#2f6f73", 255), hexc("#1d4d52")))
                # növények
                for _ in range(8 + 3 * lvl):
                    px, py = x0 + 1 + rnd.randrange(width - 2), 53 - rnd.randrange(h // 2 + 2)
                    c.put(px, py, hexc("#6fd36a") if rnd.random() < 0.6 else hexc("#f4c85a"))
                # íves tető és bordák
                for x in range(x0, x0 + width):
                    rr = abs(x - (x0 + width / 2 - 0.5)) / (width / 2)
                    ry = 53 - h - int(4 * (1 - rr * rr))
                    for y in range(ry, 53 - h):
                        c.put(x, y, dith(x, y, 0.5, hexc("#3f8f92"), hexc("#a6e3e0")))
                    c.put(x, ry - 1, ol)
                for x in range(x0, x0 + width, 4):
                    for y in range(53 - h, 54):
                        c.put(x, y, frame)
                for y in range(53 - h, 54):
                    c.put(x0 - 1, y, ol)
                    c.put(x0 + width, y, ol)
        c.im.save(o / f"uveghaz_{lvl}.png")


def main(out: str) -> None:
    o = Path(out)
    o.mkdir(parents=True, exist_ok=True)
    background(o)
    ai_core(o)
    archive(o)
    greenhouse(o)
    print("kész:", o)


if __name__ == "__main__":
    main(sys.argv[1])
