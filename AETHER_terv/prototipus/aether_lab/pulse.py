"""A Föld napi hőmérséklete 1940 óta (Copernicus Climate Pulse, ERA5), a játék görbéjéhez.

Forrás: Copernicus Climate Change Service (C3S) / ECMWF, Climate Pulse, https://pulse.climate.copernicus.eu/
(nyílt adat, a forrás megjelölésével használható). Kulcs nem kell.

Kimenet (JSON), a „Föld hőmérséklete” ablaknak:
  ma:        az utolsó nap értéke, eltérése az 1991–2020-as átlagtól (és az iparosodás előttitől, ha van)
  rang:      hányadik legmelegebb ez a naptári nap az összes év közül
  ev_gorbe:  az idei év napi értékei (január 1-jétől)
  atlag:     az 1991–2020-as átlag naponként (366 nap)
  sav_min / sav_max: a korábbi évek legkisebb és legnagyobb értéke naponként (szürke sáv)
  elozo_ev:  a tavalyi év napi értékei
  nap_evente: [[év, eltérés], ...] ugyanerre a naptári napra minden évben (színes csík)
  evente:    [[év, éves átlagos eltérés 1991–2020-tól, ugyanez az iparosodás előttitől vagy null], ...]
             (teljes évek, a végén az idei év eddigi napjaiból; a kezdőanimáció évszámlálója ezt használja)

Használat:  python -m aether_lab pulse --ki pulse.json [--fajta levego|tenger]
"""
from __future__ import annotations

import csv
import datetime as _dt
import io
import json
from pathlib import Path
from typing import Callable, Dict, List, Optional

from .world_state import PULSE_URLS, _http

FORRAS = "Copernicus Climate Pulse (C3S/ECMWF, ERA5)"
LINK = "https://pulse.climate.copernicus.eu/"


def _rows(text: str) -> List[tuple]:
    """(dátum, érték, eltérés_1991_2020 vagy None, eltérés_ipar_előtt vagy None) soronként."""
    rows = [r for r in csv.reader(io.StringIO(text)) if r and not r[0].lstrip().startswith("#")]
    if not rows:
        raise ValueError("Üres Climate Pulse-adatsor")
    head = [h.strip().lower() for h in rows[0]]

    def idx(*names):
        for i, h in enumerate(head):
            if any(h.startswith(n) for n in names):
                return i
        return None
    i_ano, i_pi = idx("ano_91-20", "ano_1991"), idx("ano_pi", "ano_1850")
    out = []
    for r in rows[1:]:
        try:
            d = _dt.date.fromisoformat(r[0].strip()[:10])
            v = float(r[1])
        except (ValueError, IndexError):
            continue

        def num(i):
            try:
                return float(r[i]) if i is not None and r[i].strip() != "" else None
            except (ValueError, IndexError):
                return None
        out.append((d, v, num(i_ano), num(i_pi)))
    if not out:
        raise ValueError("Üres Climate Pulse-adatsor")
    return out


def _doy(d: _dt.date) -> int:
    """Nap sorszáma 0–365 egy szökőéves naptárban (február 29. a 59.), hogy az évek egymás alá kerüljenek."""
    return (_dt.date(2000, d.month, d.day) - _dt.date(2000, 1, 1)).days


def summarize(text: str, kind: str = "levego") -> Dict:
    rows = _rows(text)
    last_d, last_v, last_ano, last_pi = rows[-1]
    year = last_d.year
    by_year: Dict[int, List[Optional[float]]] = {}
    for d, v, _a, _p in rows:
        by_year.setdefault(d.year, [None] * 366)[_doy(d)] = v
    # 1991–2020-as átlag naponként
    atlag = []
    for i in range(366):
        vals = [by_year[y][i] for y in range(1991, 2021) if y in by_year and by_year[y][i] is not None]
        atlag.append(round(sum(vals) / len(vals), 3) if vals else None)
    # a korábbi évek sávja
    lo, hi = [], []
    for i in range(366):
        vals = [by_year[y][i] for y in by_year if y < year and by_year[y][i] is not None]
        lo.append(round(min(vals), 3) if vals else None)
        hi.append(round(max(vals), 3) if vals else None)
    # ugyanez a naptári nap minden évben: eltérés az 1991–2020-as átlagtól, és a rang
    k = _doy(last_d)
    same = [(y, by_year[y][k]) for y in sorted(by_year) if by_year[y][k] is not None]
    base = atlag[k]
    nap_evente = [[y, round(v - base, 2)] for y, v in same] if base is not None else []
    rang = 1 + sum(1 for _y, v in same if v > last_v)
    ano = last_ano if last_ano is not None else (round(last_v - base, 2) if base is not None else None)
    ev = by_year[year][:k + 1]
    # éves átlagos eltérés: a napi eltérések átlaga (az idei évnél az eddigi napoké)
    acc: Dict[int, List] = {}
    for d, v, a, p_ in rows:
        b = atlag[_doy(d)]
        a = a if a is not None else (v - b if b is not None else None)
        if a is None:
            continue
        e = acc.setdefault(d.year, [0, 0.0, 0, 0.0])
        e[0] += 1
        e[1] += a
        if p_ is not None:
            e[2] += 1
            e[3] += p_
    evente = [[y, round(e[1] / e[0], 2), round(e[3] / e[2], 2) if e[2] == e[0] else None]
              for y, e in sorted(acc.items()) if e[0] >= 360 or y == year]
    nev = ("A Föld felszín közeli levegőjének átlaghőmérséklete" if kind == "levego"
           else "Az óceánok felszíni hőmérséklete (é. sz. 60° és d. sz. 60° között)")
    nev_en = ("Global surface air temperature" if kind == "levego"
              else "Sea surface temperature (60°S–60°N)")
    return {"fajta": kind, "nev": nev, "nev_en": nev_en, "egyseg": "°C",
            "ma": {"datum": last_d.isoformat(), "ertek": round(last_v, 2),
                   "elteres_1991_2020": None if ano is None else round(ano, 2),
                   "elteres_ipar_elott": None if last_pi is None else round(last_pi, 2)},
            "rang": rang, "evek_szama": len(same), "elso_ev": min(by_year), "ev": year,
            "ev_gorbe": ev, "elozo_ev": by_year.get(year - 1, []), "atlag": atlag, "sav_min": lo, "sav_max": hi,
            "nap_evente": nap_evente, "evente": evente, "forras": FORRAS, "link": LINK}


def build(kind: str = "levego", fetch: Callable[..., bytes] = _http) -> Dict:
    return summarize(fetch(PULSE_URLS[kind], timeout=60).decode("utf-8", "replace"), kind)


def cmd_pulse(args):
    out = build(args.fajta)
    Path(args.ki).write_text(json.dumps(out, ensure_ascii=False), encoding="utf-8")
    m = out["ma"]
    print(f"{m['datum']}: {m['ertek']} °C, eltérés {m['elteres_1991_2020']}, rang {out['rang']}/{out['evek_szama']}")


def add_parsers(sub):
    p = sub.add_parser("pulse", help="A Föld napi hőmérséklete 1940 óta (Copernicus Climate Pulse)")
    p.add_argument("--ki", default="pulse.json")
    p.add_argument("--fajta", default="levego", choices=["levego", "tenger"])
    p.set_defaults(fn=cmd_pulse)
