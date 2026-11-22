"""A felület (panelek, gombok) festett pixeles keretei, 9-szeletes (nine-patch) képek.

Saját rajz programmal: domború keret (fent-balra fény, lent-jobbra árnyék),
arany sarokszegecsek, a belső rész finom, rendezett (Bayer) ditherrel.
A Godot StyleBoxTexture-ként használja, csempézve, így éles marad minden méretben.

Használat:  python festett_felulet.py <kimeneti assets/ui mappa>
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def hexc(h: str):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


def frame(size: int, m: int, bg: str, bg2: str, light: str, dark: str, edge: str, rivet: str | None) -> Image.Image:
    im = Image.new("RGBA", (size, size))
    px = im.load()
    a, b = hexc(bg), hexc(bg2)
    for y in range(size):
        for x in range(size):
            # belső rész: két szín Bayer-ditherrel keverve (a 4x4 minta csempézve folytonos)
            px[x, y] = b if BAYER[y % 4][x % 4] < 4 else a
    L, D, E = hexc(light), hexc(dark), hexc(edge)
    for i in range(size):
        for t in range(2):                      # 2 px vastag külső él
            px[i, t] = E; px[i, size - 1 - t] = E; px[t, i] = E; px[size - 1 - t, i] = E
        px[i, 2] = L; px[2, i] = L              # fény fent-balra
        px[i, size - 3] = D; px[size - 3, i] = D  # árnyék lent-jobbra
    if rivet:
        R, Rd = hexc(rivet), hexc(dark)
        for cx, cy in ((m // 2, m // 2), (size - 1 - m // 2, m // 2), (m // 2, size - 1 - m // 2),
                       (size - 1 - m // 2, size - 1 - m // 2)):
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    if abs(dx) + abs(dy) < 2:
                        px[cx + dx, cy + dy] = R
            px[cx + 1, cy + 1] = Rd
    return im


def main(out: str) -> None:
    o = Path(out)
    o.mkdir(parents=True, exist_ok=True)
    # panel: 32 px, a sarokban 12 px-es margó (9-szelet)
    frame(32, 12, "#0b101d", "#0e1626", "#3e5680", "#05080f", "#22314f", "#f4c85a").save(o / "panel.png")
    frame(24, 8, "#1c2944", "#213152", "#5d7db3", "#0c1322", "#33476b", None).save(o / "gomb.png")
    frame(24, 8, "#26385c", "#2c4269", "#7d9fd6", "#0c1322", "#4a6391", None).save(o / "gomb_folotte.png")
    frame(24, 8, "#152039", "#18243f", "#0c1322", "#5d7db3", "#33476b", None).save(o / "gomb_lenyomva.png")
    print("kész:", o)


if __name__ == "__main__":
    main(sys.argv[1])
