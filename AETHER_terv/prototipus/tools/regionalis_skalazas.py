"""Regionális „mintázat-skálázás” az IPCC AR6 Atlasz CMIP6 adataiból (CC BY 4.0).

Minden IPCC-referenciarégióra (szárazföld) kiszámolja, hogy 1 °C globális melegedés
mekkora regionális változással jár:
  - nyári (JJA és DJF) és éves középhőmérséklet: °C / 1 °C globális,
  - nyári (JJA, DJF) és éves csapadék: % / 1 °C globális.
Módszer: modellenként a 20 éves mozgóátlagolt regionális anomáliát (1850–1900-hoz)
az origón átmenő egyenessel illesztjük a globális anomáliára (historical + SSP2-4.5 és
SSP5-8.5, 1850–2100), majd a modellek mediánját és 17–83%-os sávját vesszük.

Forrás: Iturbide et al. (2021) / IPCC-WG1 Atlas, datasets-aggregated-regionally,
https://github.com/IPCC-WG1/Atlas (CC BY 4.0).

Használat:  python regionalis_skalazas.py <Atlas/datasets-aggregated-regionally/data/CMIP6> <kimenet.json>
"""
from __future__ import annotations

import csv
import json
import statistics
import sys
from pathlib import Path

SCEN = ["ssp245", "ssp585"]
SEASONS = {"JJA": (6, 7, 8), "DJF": (12, 1, 2), "ev": tuple(range(1, 13))}


def read(path: Path):
    rows = [r for r in csv.reader(l for l in path.open(encoding="utf-8") if not l.startswith("#"))]
    head = [h.strip('"') for h in rows[0]]
    data = {}
    for r in rows[1:]:
        y, m = int(r[0][:4]), int(r[0][5:7])
        data[(y, m)] = [float(x) if x not in ("", "NA") else float("nan") for x in r[1:]]
    return head[1:], data


def seasonal(data, col, months):
    out = {}
    for (y, m), v in data.items():
        # DJF: a decembert a következő év teléhez számoljuk
        yy = y + 1 if (months == (12, 1, 2) and m == 12) else y
        if m in months:
            out.setdefault(yy, []).append(v[col])
    return {y: sum(v) / len(v) for y, v in out.items() if len(v) == len(months)}


def smooth(series, w=20):
    ys = sorted(series)
    out = {}
    for i in range(len(ys) - w + 1):
        win = ys[i:i + w]
        out[win[w // 2]] = sum(series[y] for y in win) / w
    return out


def slope(x, y):
    num = sum(a * b for a, b in zip(x, y))
    den = sum(a * a for a in x)
    return num / den if den else float("nan")


def main(root: str, out: str) -> None:
    root = Path(root)
    models = sorted({p.name.split("_")[1] for p in (root / "CMIP6_tas_land").glob("CMIP6_*_historical_*.csv")})
    res = {}
    used = []
    for model in models:
        per_scen = []
        for sc in SCEN:
            try:
                files = {}
                for var, kind in [("tas", "landsea"), ("tas", "land"), ("pr", "land")]:
                    h = next((root / f"CMIP6_{var}_{kind}").glob(f"CMIP6_{model}_historical_*.csv"))
                    s = next((root / f"CMIP6_{var}_{kind}").glob(f"CMIP6_{model}_{sc}_*.csv"))
                    head, d1 = read(h)
                    _, d2 = read(s)
                    d1.update(d2)
                    files[(var, kind)] = (head, d1)
            except StopIteration:
                continue
            head_g, dg = files[("tas", "landsea")]
            g = seasonal(dg, head_g.index("world"), SEASONS["ev"])
            base_g = statistics.mean(g[y] for y in range(1850, 1901) if y in g)
            gs = smooth({y: v - base_g for y, v in g.items()})
            regs = {}
            for (var, kind) in [("tas", "land"), ("pr", "land")]:
                head, d = files[(var, kind)]
                for ci, reg in enumerate(head):
                    for sn, months in SEASONS.items():
                        s_ = seasonal(d, ci, months)
                        base = statistics.mean(s_[y] for y in range(1851, 1901) if y in s_)
                        if var == "tas":
                            an = {y: v - base for y, v in s_.items()}
                        else:
                            if base <= 0:
                                continue
                            an = {y: (v / base - 1) * 100 for y, v in s_.items()}
                        sm = smooth(an)
                        ys = [y for y in sm if y in gs]
                        regs[(reg, var, sn)] = slope([gs[y] for y in ys], [sm[y] for y in ys])
            per_scen.append(regs)
        if not per_scen:
            continue
        used.append(model)
        for k in per_scen[0]:
            vals = [p[k] for p in per_scen if k in p]
            res.setdefault(k, []).append(sum(vals) / len(vals))
    table = {}
    for (reg, var, sn), vals in res.items():
        vals = sorted(v for v in vals if v == v)
        if len(vals) < 5:
            continue
        q = statistics.quantiles(vals, n=100)
        key = f"{'homerseklet' if var == 'tas' else 'csapadek_pct'}_{sn}"
        table.setdefault(reg, {})[key] = {"median": round(statistics.median(vals), 3),
                                         "also": round(q[16], 3), "felso": round(q[82], 3), "n": len(vals)}
    meta = {"forras": "IPCC AR6 Interaktív Atlasz, CMIP6 regionális átlagok (Iturbide et al. 2021, "
                      "https://github.com/IPCC-WG1/Atlas, CC BY 4.0)",
            "modszer": "mintázat-skálázás: 20 éves mozgóátlag, regionális anomália / globális anomália "
                       "(1850–1900-hoz), historical + SSP2-4.5 és SSP5-8.5; modellmedián, 17–83% sáv",
            "egyseg": "homerseklet: °C regionális / °C globális; csapadek_pct: % / °C globális",
            "modellek": used}
    Path(out).write_text(json.dumps({"meta": meta, "regiok": table}, ensure_ascii=False, indent=1), encoding="utf-8")
    print(len(used), "modell,", len(table), "régió ->", out)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
