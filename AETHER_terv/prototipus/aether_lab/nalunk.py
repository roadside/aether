"""„Mit jelent ez nálunk?” – a globális melegedés helyi jelentése, valódi adatokból.

Mért adatok (valódi):
  - napi legmagasabb hőmérséklet és csapadék 1961-től: ERA5 újraelemzés (Copernicus / ECMWF)
    az Open-Meteo archívumán keresztül (https://open-meteo.com, CC BY 4.0), a játékos helyén.
  - globális melegedés évente (1850–1900-hoz): Forster et al. 2025 (CC BY 4.0).

Becslés a jövőre (egyszerű, átlátható módszer, a játékban így is jelölve):
  - a régió (IPCC AR6 referenciarégió) nyári melegedése 1 °C globális melegedésre és a nyári
    csapadék %-os változása: 34 CMIP6 klímamodell mediánja és 17–83%-os sávja (IPCC AR6
    Interaktív Atlasz adataiból számolva, lásd tools/regionalis_skalazas.py);
  - a 2006–2025 közötti mért napokat ennyivel „eltoljuk” (delta-módszer), és megszámoljuk,
    hány nap lenne 30 °C fölött. Ez nem helyi klímamodell, csak tájékoztató becslés.

Használat:  python -m aether_lab nalunk --lat 47.5 --lon 19.0 --orszag HU --hely Budapest --ki nalunk.json
"""
from __future__ import annotations

import json
import os
import urllib.parse
from pathlib import Path
from typing import Callable, Dict, List, Optional

HOT = 30.0                 # °C: „30 °C feletti nap” (a napi legmagasabb hőmérséklet alapján)
REF = (2006, 2025)         # a mai állapot: az utolsó 20 teljes év
OLD = (1961, 1990)         # a régi éghajlat (WMO-referencia)
WARMING_LEVELS = [round(1.0 + 0.1 * i, 1) for i in range(31)]   # 1,0 … 4,0 °C

_SCALING: Optional[Dict] = None


def scaling() -> Dict:
    global _SCALING
    if _SCALING is None:
        _SCALING = json.loads((Path(__file__).with_name("regionalis_skalazas.json")).read_text(encoding="utf-8"))
    return _SCALING


def era5_url(lat: float, lon: float, start: int = OLD[0], end: int = REF[1]) -> str:
    return "https://archive-api.open-meteo.com/v1/archive?" + urllib.parse.urlencode({
        "latitude": lat, "longitude": lon, "start_date": f"{start}-01-01", "end_date": f"{end}-12-31",
        "daily": "temperature_2m_max,precipitation_sum", "timezone": "UTC"})


def yearly(daily: Dict) -> Dict[int, Dict]:
    """Évente: 30 °C feletti napok száma és a nyári (jún–aug) csapadék összege (mm)."""
    out: Dict[int, Dict] = {}
    for d, tx, pr in zip(daily["time"], daily["temperature_2m_max"], daily["precipitation_sum"]):
        y, m = int(d[:4]), int(d[5:7])
        e = out.setdefault(y, {"napok": 0, "nyari_csapadek": 0.0, "hianyzik": 0})
        if tx is None:
            e["hianyzik"] += 1
            continue
        if tx > HOT:
            e["napok"] += 1
        if m in (6, 7, 8) and pr is not None:
            e["nyari_csapadek"] += pr
    return {y: e for y, e in out.items() if e["hianyzik"] < 10}


def _mean(xs: List[float]) -> float:
    return sum(xs) / len(xs) if xs else float("nan")


def gmst_mean(y0: int, y1: int) -> float:
    g = scaling()["gmst_megfigyelt"]["evek"]
    return _mean([g[str(y)] for y in range(y0, y1 + 1) if str(y) in g])


def hot_days_at(daily: Dict, delta: float) -> float:
    """A referencia-évek napjai +delta °C-kal eltolva: átlagosan hány nap lenne 30 °C fölött évente."""
    n, years = 0, set()
    for d, tx in zip(daily["time"], daily["temperature_2m_max"]):
        y = int(d[:4])
        if REF[0] <= y <= REF[1] and tx is not None:
            years.add(y)
            if tx + delta > HOT:
                n += 1
    return n / len(years) if years else float("nan")


def build(lat: float, lon: float, country: str, place: str, fetch: Callable[..., bytes], lang: str = "hu") -> Dict:
    sc = scaling()
    region = sc["orszag_regio"].get(country.upper(), "")
    k = sc["regiok"].get(region, {})
    if not k:
        raise ValueError(f"Nincs regionális adat ehhez az országhoz: {country}")
    south = lat < 0
    season = "DJF" if south else "JJA"
    kt = k[f"homerseklet_{season}"]
    kp = k[f"csapadek_pct_{season}"]
    daily = json.loads(fetch(era5_url(lat, lon)))["daily"]
    yr = yearly(daily)
    ref_years = [y for y in range(REF[0], REF[1] + 1) if y in yr]
    old_years = [y for y in range(OLD[0], OLD[1] + 1) if y in yr]
    t_ref = gmst_mean(*REF)
    ref_days = _mean([yr[y]["napok"] for y in ref_years])
    ref_rain = _mean([yr[y]["nyari_csapadek"] for y in ref_years])
    table = []
    for t in WARMING_LEVELS:
        dt = t - t_ref
        table.append({
            "globalis": t,
            "napok": round(hot_days_at(daily, kt["median"] * dt), 1),
            "napok_also": round(hot_days_at(daily, kt["also"] * dt), 1),
            "napok_felso": round(hot_days_at(daily, kt["felso"] * dt), 1),
            "nyari_csapadek": round(ref_rain * (1 + kp["median"] * dt / 100), 1),
            "csapadek_also": round(ref_rain * (1 + kp["also"] * dt / 100), 1),
            "csapadek_felso": round(ref_rain * (1 + kp["felso"] * dt / 100), 1),
        })
    return {
        "hely": place, "lat": lat, "lon": lon, "orszag": country.upper(), "regio": region,
        "regio_nev": sc["regio_nevek"].get(region, region), "evszak": season,
        "kuszob": HOT,
        "evek": [{"ev": y, "napok": yr[y]["napok"], "nyari_csapadek": round(yr[y]["nyari_csapadek"], 1)}
                 for y in sorted(yr)],
        "regi": {"idoszak": list(OLD), "napok": round(_mean([yr[y]["napok"] for y in old_years]), 1),
                 "nyari_csapadek": round(_mean([yr[y]["nyari_csapadek"] for y in old_years]), 1)},
        "mai": {"idoszak": list(REF), "napok": round(ref_days, 1), "nyari_csapadek": round(ref_rain, 1),
                "globalis": round(t_ref, 2)},
        "skala": {"homerseklet": kt, "csapadek_pct": kp},
        "tablazat": table,
        "forrasok": [
            {"nev": "ERA5 (Copernicus/ECMWF) az Open-Meteón keresztül", "link": "https://open-meteo.com/en/docs/historical-weather-api"},
            {"nev": "IPCC AR6 Interaktív Atlasz, CMIP6 (Iturbide et al. 2021)", "link": "https://github.com/IPCC-WG1/Atlas"},
            {"nev": "Forster et al. 2025, globális melegedés", "link": "https://doi.org/10.5194/essd-17-2641-2025"},
        ],
    }


def cmd_nalunk(args):
    from .world_state import _http
    out = Path(args.ki)
    out.parent.mkdir(parents=True, exist_ok=True)
    try:
        res = build(args.lat, args.lon, args.orszag, args.hely, lambda u: _http(u, timeout=60), args.nyelv)
    except Exception as e:
        res = {"hiba": str(e)}
    tmp = out.with_suffix(".tmp")
    tmp.write_text(json.dumps(res, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, out)


def add_parsers(sub):
    p = sub.add_parser("nalunk", help="„Mit jelent ez nálunk?” – helyi hőségnapok és nyári csapadék")
    p.add_argument("--lat", type=float, required=True)
    p.add_argument("--lon", type=float, required=True)
    p.add_argument("--orszag", required=True, help="ISO országkód, pl. HU")
    p.add_argument("--hely", default="", help="a hely neve a kijelzéshez")
    p.add_argument("--ki", required=True)
    p.add_argument("--nyelv", default="hu", choices=["hu", "en"])
    p.set_defaults(fn=cmd_nalunk)
