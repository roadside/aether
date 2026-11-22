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


@lru_cache(maxsize=1)
def _hu_names() -> Dict[str, str]:
    """Angol országnév -> magyar név (kisbetűs, normalizált kulccsal)."""
    d = json.loads(_DATA.read_text(encoding="utf-8"))
    out = {}
    for cc, en in d["nevek"].items():
        out[_norm(en)] = d.get("nevek_hu", {}).get(cc, en)
    for alias, cc in ALIASES.items():
        out[_norm(alias)] = d.get("nevek_hu", {}).get(cc, alias)
    return out


# A források (GDACS, ReliefWeb) néhol másként írják az országneveket.
ALIASES = {"Russia": "RU", "Czech Republic": "CZ", "Turkey": "TR", "Türkiye": "TR", "Vietnam": "VN", "Viet Nam": "VN",
           "Iran (Islamic Republic of)": "IR", "Syrian Arab Republic": "SY", "Republic of Korea": "KR",
           "Democratic Republic of the Congo": "CD", "Congo, The Democratic Republic of the": "CD", "Macedonia": "MK",
           "Moldova, Republic of": "MD", "Republic of Moldova": "MD", "Tanzania, United Republic of": "TZ",
           "United Republic of Tanzania": "TZ", "Bolivia (Plurinational State of)": "BO", "Lao PDR": "LA",
           "Venezuela (Bolivarian Republic of)": "VE", "United States of America": "US", "USA": "US", "UK": "GB",
           "Ivory Coast": "CI", "Cote d'Ivoire": "CI", "Kosovo": "XK", "Palestine, State of": "PS"}


def _norm(name: str) -> str:
    return " ".join(name.lower().replace("&", "and").split())


def hu_country(name: str) -> str:
    """Az ország magyar neve; ha nem ismerjük, az eredeti név marad."""
    return _hu_names().get(_norm(name), name.strip())


def country_name(cc: str, hungarian: bool = False) -> str:
    """ISO-kódból országnév (angolul vagy magyarul); ismeretlen kódnál ''."""
    d = json.loads(_DATA.read_text(encoding="utf-8"))
    return (d.get("nevek_hu", {}) if hungarian else d["nevek"]).get(cc.upper(), "")


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
