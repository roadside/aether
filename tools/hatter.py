"""AETHER – a játék háttere (assets/nebula_bg.png), teljesen kódból: saját, programmal generált kép.

Nyugodt, természetes éjszakai ég: mély kék alap, nagyon halvány, festett csillagköd-sáv (mint a Tejút
szabad szemmel), kevés, különböző fényességű csillag. Nem valós felvétel és nem csillagtérkép.

Futtatás:  python tools/hatter.py   (kell hozzá: numpy, Pillow)
"""
from pathlib import Path

import numpy as np
from PIL import Image

W, H = 800, 450
rng = np.random.default_rng(2026)


def noise(scale: int) -> np.ndarray:
    """Lágy zaj: kis véletlen rács, simán felnagyítva."""
    small = rng.random((H // scale + 2, W // scale + 2)).astype(np.float32)
    img = Image.fromarray((small * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)
    return np.asarray(img, dtype=np.float32) / 255.0


def fbm() -> np.ndarray:
    out = np.zeros((H, W), np.float32)
    amp, tot = 1.0, 0.0
    for scale in (160, 80, 40, 20, 10):
        out += noise(scale) * amp
        tot += amp
        amp *= 0.55
    return out / tot


yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
u, v = xx / W, yy / H
# alap: mély éjkék, középen egy árnyalattal világosabb (a Föld mögött), a széleken sötétebb
r2 = ((u - 0.5) * 1.15) ** 2 + ((v - 0.5) * 1.0) ** 2
base = np.stack([0.022 + 0.030 * np.exp(-r2 * 3.0), 0.036 + 0.046 * np.exp(-r2 * 3.0), 0.082 + 0.078 * np.exp(-r2 * 3.0)], -1)

# halvány, ferde köd-sáv: két zajréteg adja a foltjait, a színe kékeslila, helyenként meleg porszínnel
band_pos = (v - 0.5) * 0.93 + (u - 0.5) * 0.42
band = np.exp(-(band_pos / 0.20) ** 2)
n1, n2, n3 = fbm(), fbm(), fbm()
cloud = np.clip((n1 - 0.38) * 2.2, 0.0, 1.0) * band
dust = np.clip((n2 - 0.50) * 2.6, 0.0, 1.0) * band
cool = np.array([0.10, 0.17, 0.33], np.float32)
violet = np.array([0.17, 0.13, 0.28], np.float32)
warm = np.array([0.26, 0.17, 0.14], np.float32)
tint = cool[None, None, :] * (1.0 - n3[..., None]) + violet[None, None, :] * n3[..., None]
img = base + tint * cloud[..., None] * 0.62 + warm[None, None, :] * dust[..., None] * 0.30
# sötét porsávok a ködben: ettől lesz mélysége
img *= (1.0 - 0.35 * np.clip((fbm() - 0.52) * 3.0, 0.0, 1.0) * band)[..., None]

# csillagok: sok halvány, kevés fényes; a köd-sávban sűrűbben
count = 520
sx = rng.integers(0, W, count * 3)
sy = rng.integers(0, H, count * 3)
keep = rng.random(count * 3) < (0.25 + 0.75 * band[sy, sx])
sx, sy = sx[keep][:count], sy[keep][:count]
mag = rng.random(len(sx)) ** 3.2                      # a legtöbb halvány
hue = rng.random(len(sx))
for x, y, m, h in zip(sx, sy, mag, hue):
    col = np.array([1.0, 0.86, 0.70]) if h < 0.18 else (np.array([0.74, 0.84, 1.0]) if h > 0.55 else np.array([0.95, 0.96, 1.0]))
    b = 0.16 + 0.84 * m
    img[y, x] = np.maximum(img[y, x], col * b)
    if m > 0.86:                                      # a néhány legfényesebb: kis, lágy kereszt
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            x2, y2 = x + dx, y + dy
            if 0 <= x2 < W and 0 <= y2 < H:
                img[y2, x2] = np.maximum(img[y2, x2], col * b * 0.42)

# enyhe, rendezett szemcse és színlépcső: festett pixelgrafika hatás
bayer = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], np.float32) / 16.0
d = np.tile(bayer, (H // 4 + 1, W // 4 + 1))[:H, :W, None]
levels = 48.0
img = np.floor(np.clip(img, 0.0, 1.0) * levels + d) / levels
out = Path(__file__).resolve().parents[1] / "assets" / "nebula_bg.png"
rgba = np.dstack([np.clip(img, 0.0, 1.0), np.ones((H, W, 1), np.float32)])
Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").save(out)
print(out, img.mean())
