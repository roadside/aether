"""Koordinátából ország, internet nélkül.

Adat: GeoNames cities1000 (CC BY 4.0, https://www.geonames.org) 0,5 fokos rácsra
ritkítva, országnevek az ISO 3166-1 szabványból (orszagok.json). Ha a pont
messze van minden lakott helytől (pl. nyílt óceán, Antarktisz), nem találunk ki
országot, hanem üres értéket adunk.
"""
from __future__ import annotations

import json
import math
from functools import lru_cache
from pathlib import Path
from typing import Dict, List, Optional, Tuple

_DATA = Path(__file__).with_name("orszagok.json")


@lru_cache(maxsize=1)
def _index() -> Tuple[Dict[Tuple[int, int], List[Tuple[float, float, str]]], Dict[str, str]]:
    d = json.loads(_DATA.read_text(encoding="utf-8"))
    buckets: Dict[Tuple[int, int], List[Tuple[float, float, str]]] = {}
    for lat, lon, cc in d["pontok"]:
        buckets.setdefault((math.floor(lat), math.floor(lon)), []).append((lat, lon, cc))
    return buckets, d["nevek"]


def _km(lat1, lon1, lat2, lon2) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 6371.0 * 2 * math.asin(min(1.0, math.sqrt(a)))


def country_at(lat: Optional[float], lon: Optional[float], max_km: float = 300.0) -> str:
    """A legközelebbi lakott hely országa, ha max_km-en belül van; különben ''."""
    if lat is None or lon is None:
        return ""
    buckets, names = _index()
    best, best_d = "", max_km
    reach = 3  # ±3 fok ~ 330 km az Egyenlítőn
    bi, bj = math.floor(lat), math.floor(lon)
    for i in range(bi - reach, bi + reach + 1):
        for j in range(bj - reach, bj + reach + 1):
            jj = (j + 180) % 360 - 180
            for plat, plon, cc in buckets.get((i, jj), ()):
                d = _km(lat, lon, plat, plon)
                if d < best_d:
                    best, best_d = cc, d
    return names.get(best, best) if best else ""
