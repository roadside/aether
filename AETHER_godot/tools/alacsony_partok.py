"""Alacsony partvidékek maszkja a földgömbhöz (assets/earth_low.png).

Forrás: NOAA ETOPO1 (1 ívperces globális domborzat, „Ice Surface” változat; Amante & Eakins 2009),
a NOAA ERDDAP szerveréről 5 ívperces ritkítással letöltve, ESRI ASCII formában:
  https://coastwatch.pfeg.noaa.gov/erddap/griddap/etopo180.esriAscii?altitude[(-90):5:(90)][(-180):5:(180)]
Licenc: szabadon használható és továbbadható (NOAA, közkincs jellegű adat; nem jogi célra).

A kimenet egy 4096×2048-as, szürkeárnyalatos PNG a gömb textúráinak vetületében (egyenközű,
bal széle a 180° ny. h.). Egy pixel értéke azt mondja meg, milyen alacsonyan fekszik a hely:
  255 = legfeljebb 0 m (a tengerszint alatt / szintjén), 0 = 10 m vagy magasabb, közte arányosan.
A −50 m-nél mélyebb pontok (nyílt tenger, mély medencék, pl. a Holt-tenger vidéke) 0-t kapnak.
A shader csak a szárazföldön használja (earth_data.png R csatornája), így a sekély tenger nem számít.

Használat:  py tools/alacsony_partok.py <etopo1_5min.asc> [assets/earth_low.png]
Csak a Python standard könyvtára kell.
"""
from __future__ import annotations

import struct
import sys
import zlib
from pathlib import Path

W, H = 4096, 2048
MAX_M = 10.0      # eddig a magasságig „alacsony part”
MIN_M = -50.0     # ennél mélyebb pont nem part


def read_asc(path: Path):
    with open(path, "r", encoding="ascii") as f:
        head = {}
        for _ in range(6):
            k, v = f.readline().split()
            head[k.lower()] = float(v)
        ncols, nrows = int(head["ncols"]), int(head["nrows"])
        rows = []
        for _ in range(nrows):
            rows.append([float(x) for x in f.readline().split()])
    return head, rows


def write_png(path: Path, w: int, h: int, rows) -> None:
    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    path.write_bytes(png)


def main():
    src = Path(sys.argv[1])
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).resolve().parent.parent / "assets" / "earth_low.png"
    head, grid = read_asc(src)
    ncols, nrows, cell = int(head["ncols"]), int(head["nrows"]), head["cellsize"]
    x0 = head.get("xllcenter", -180.0)
    y_top = head.get("yllcenter", -90.0) + (nrows - 1) * cell   # az ESRI ASCII első sora a legészakibb
    nodata = head.get("nodata_value", -9999999)
    rows = []
    n_low = 0
    for y in range(H):
        lat = 90.0 - (y + 0.5) * 180.0 / H
        gr = min(nrows - 1, max(0, int(round((y_top - lat) / cell))))
        src_row = grid[gr]
        line = bytearray(W)
        for x in range(W):
            lon = -180.0 + (x + 0.5) * 360.0 / W
            gc = min(ncols - 1, max(0, int(round((lon - x0) / cell))))
            e = src_row[gc]
            if e == nodata or e < MIN_M or e > MAX_M:
                continue
            v = 1.0 if e <= 0.0 else (MAX_M - e) / MAX_M
            line[x] = int(round(v * 255))
            n_low += 1
        rows.append(line)
    write_png(out, W, H, rows)
    print(f"kész: {out} ({n_low} alacsony pixel a {W * H}-ból, a sekély tengert is beleértve)")


if __name__ == "__main__":
    main()
