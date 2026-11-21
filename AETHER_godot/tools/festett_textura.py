"""A földgömb „festett pixeles” textúráinak előállítása valódi műholdas adatokból.

Források (közkincs, NASA):
  - Blue Marble (nappali színek, a tenger alatti domborzat árnyalásával)
  - Black Marble / Earth at Night (városfények)
  - domborzati térkép (szürkeárnyalatos magasság) és víz-maszk
  Letöltve a three-globe projekt példaképei közül (MIT-licencű kód, a képek NASA-eredetűek):
  https://github.com/vasturiano/three-globe/tree/master/example/img

A feldolgozás saját stílus (nem másol meglévő játékot):
  - a szárazföld színei egy kis, saját palettára kerülnek (lapos, festett foltok),
  - a domborzat 4 lépcsős, festett árnyalást kap (ÉNy-i fény),
  - a tenger a mélység szerint 5 kék árnyalatból áll, hullámos határokkal, a parton tajtékkal,
  - a városfények 4 fényességszintű, meleg aranysárga pöttyök.

Használat:  python festett_textura.py <forrásmappa> <kimeneti assets mappa>
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.cluster.vq import kmeans2

W, H = 4096, 2048
SEED = 7

OCEAN = np.array([[0.05, 0.15, 0.31], [0.07, 0.21, 0.40], [0.09, 0.28, 0.50],
                  [0.13, 0.40, 0.60], [0.24, 0.58, 0.68]])
FOAM = np.array([0.62, 0.84, 0.86])
NIGHT = np.array([1.0, 0.78, 0.42])


def load(src: Path, name: str, mode: str, size=(W, H)) -> np.ndarray:
    im = Image.open(src / name).convert(mode).resize(size, Image.LANCZOS)
    return np.asarray(im, dtype=np.float32) / 255.0


def noise(shape, scale: float, rng) -> np.ndarray:
    """Alacsony frekvenciájú zaj: ettől hullámosak a festett foltok határai."""
    small = rng.standard_normal((max(2, int(shape[0] / scale)), max(2, int(shape[1] / scale))))
    big = ndimage.zoom(small, (shape[0] / small.shape[0], shape[1] / small.shape[1]), order=3)
    return big[: shape[0], : shape[1]]


def albedo_and_data(src: Path):
    rng = np.random.default_rng(SEED)
    bm = load(src, "earth-blue-marble.jpg", "RGB")
    water = load(src, "earth-water.png", "L") > 0.5
    topo = load(src, "earth-topology.png", "L")
    land = ~water

    # --- szárazföld: festett foltok egy saját palettán ---------------------
    painted = ndimage.median_filter(bm, size=(7, 7, 1))          # ecsetvonás-szerű foltok
    hsv = np.asarray(Image.fromarray((painted * 255).astype(np.uint8)).convert("HSV"), dtype=np.float32) / 255
    hsv[..., 1] = np.clip(hsv[..., 1] * 1.5, 0, 1)                # élénkebb, festményszerű színek
    hsv[..., 2] = np.clip(hsv[..., 2] ** 0.85 * 1.08, 0, 1)
    vivid = np.asarray(Image.fromarray((hsv * 255).astype(np.uint8), "HSV").convert("RGB"),
                       dtype=np.float32) / 255
    sample = vivid[land][rng.choice(land.sum(), 60000, replace=False)]
    pal, _ = kmeans2(sample, 16, minit="++", seed=SEED)
    jitter = noise((H, W), 16, rng)[..., None] * 0.05              # hullámos foltszélek
    flat = vivid + jitter
    idx = np.empty((H, W), np.int32)
    for y0 in range(0, H, 256):                                     # soronként, hogy kevés memória kelljen
        blk = flat[y0:y0 + 256]
        idx[y0:y0 + 256] = ((blk[..., None, :] - pal[None, None]) ** 2).sum(-1).argmin(-1)
    land_col = pal[idx]

    # festett domborzat: 4 lépcsős árnyalás ÉNy-i fényből
    z = ndimage.gaussian_filter(topo, 1.2)
    gy, gx = np.gradient(z)
    shade = (gx * 0.7 + gy * 0.7) * 90.0
    shade = np.clip(np.round(shade * 2) / 2, -1.0, 1.0)            # lépcsők: -1, -0,5, 0, 0,5, 1
    land_col = np.clip(land_col * (1.0 + 0.30 * shade[..., None]), 0, 1)

    # --- tenger: 5 mélységi árnyalat, hullámos határral, tajték a parton ---
    lum = bm.mean(-1)
    dist = ndimage.distance_transform_edt(water)                    # távolság a parttól (pixel)
    depth = np.clip(lum / max(1e-3, np.percentile(lum[water], 97)), 0, 1)
    depth = 0.82 * depth + 0.18 * np.exp(-dist / 10.0) + noise((H, W), 48, rng) * 0.045
    step = np.digitize(depth, [0.24, 0.40, 0.58, 0.80])            # 0 = mély … 4 = parti sekély
    sea_col = OCEAN[step]
    foam = water & (dist <= 2.0)
    sea_col[foam] = FOAM

    col = np.where(land[..., None], land_col, sea_col)
    albedo = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8), "RGB")

    data = np.zeros((H, W, 4), np.uint8)
    data[..., 0] = land * 255
    data[..., 1] = (water & (step >= 3)) * 198                      # sekély víz
    data[..., 3] = 255
    return albedo, Image.fromarray(data, "RGBA")


def night(src: Path) -> Image.Image:
    n = load(src, "earth-night.jpg", "L")
    v = np.clip((n - 0.21) / 0.17, 0, 1)   # a holdfényes, halvány földfelszín ne világítson
    # a földgömb egy képpontja kb. 2-3 textúrapont: a fényeket kicsit „megnöveljük”,
    # hogy a mintavételezés ne hagyja ki őket (a fényerő marad, csak a pötty nagyobb)
    v = ndimage.grey_dilation(v, size=(3, 3))
    v = np.round(v * 4) / 4                                         # 4 fényességszint
    col = (NIGHT[None, None] * v[..., None] * 255).astype(np.uint8)
    return Image.fromarray(col, "RGB")


def main(src: str, out: str) -> None:
    s, o = Path(src), Path(out)
    a, d = albedo_and_data(s)
    a.save(o / "earth_albedo.png", optimize=True)
    d.save(o / "earth_data.png", optimize=True)
    night(s).save(o / "earth_night.png", optimize=True)
    print("kész:", o)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
