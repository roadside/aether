"""Ellenőrzés: van-e minden témához valódi szakirodalom, és találhat-e benne számot a kutatás?

Témánként (OpenAlex, https://openalex.org, nyílt adatbázis):
  - áttekintő cikkek száma az "attekintes" keresésre (type:review);
  - a "kereses" kifejezések első 12 találatából hány absztraktban van a téma paraméterének
    mértékegységével szám (ugyanaz a szűrő, amit a játék kutatása használ).

Gyenge a téma, ha 3-nál kevesebb az áttekintő cikk, vagy 2-nél kevesebb cikkben van megfelelő szám.

Használat:  python tools/temak_ellenorzes.py [--csak id1,id2] [--ki tools/temak_ellenorzes.json]
Környezet:  AETHER_MAILTO, OPENALEX_API_KEY (nem kötelező; a "polite pool"-hoz ajánlott).
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.parse
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE))

from aether_lab import literature as lit   # noqa: E402
from aether_lab import research            # noqa: E402
import temak                               # noqa: E402

MIN_REVIEWS = 3
MIN_NUMBER_PAPERS = 2


def _url(params: dict) -> str:
    if os.environ.get("AETHER_MAILTO"):
        params["mailto"] = os.environ["AETHER_MAILTO"]
    if os.environ.get("OPENALEX_API_KEY"):
        params["api_key"] = os.environ["OPENALEX_API_KEY"]
    return "https://api.openalex.org/works?" + urllib.parse.urlencode(params)


def review_count(query: str) -> int:
    data = json.loads(lit._get(_url({"search": query, "per-page": "1",
                                     "filter": "type:review,from_publication_date:2000-01-01"})))
    return int(data.get("meta", {}).get("count", 0))


def number_papers(queries: list, params: list) -> tuple:
    """(cikkek száma összesen, ebből hányban van megfelelő mértékegységű szám)."""
    seen, hits = set(), set()
    for q in queries:
        for p in lit.search_openalex(q, n=12, mailto=os.environ.get("AETHER_MAILTO", ""),
                                     api_key=os.environ.get("OPENALEX_API_KEY", "")):
            key = p.doi or p.source_id
            seen.add(key)
            if research.candidate_sentences(p.abstract, params):
                hits.add(key)
        time.sleep(0.2)
    return len(seen), len(hits)


def check(t: dict) -> dict:
    params = [p for p in t["parameterek"].split(",") if p]
    out = {"id": t["id"], "korszak": t["korszak"], "terulet": t["terulet"], "cim": t["cim"]}
    try:
        out["attekintok"] = review_count(t["attekintes"])
        time.sleep(0.2)
        out["cikkek"], out["szammal"] = number_papers(t["kereses"].split("|"), params)
        out["gyenge"] = out["attekintok"] < MIN_REVIEWS or out["szammal"] < MIN_NUMBER_PAPERS
    except Exception as e:   # hálózati hiba: jelezzük, ne álljon le az egész
        out["hiba"] = str(e)[:200]
        out["gyenge"] = None
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--csak", default="", help="csak ezek a témák (vesszővel)")
    ap.add_argument("--ki", default=str(HERE / "temak_ellenorzes.json"))
    a = ap.parse_args()
    only = {x for x in a.csak.split(",") if x}
    rows = []
    for t in temak.TEMAK:
        if only and t["id"] not in only:
            continue
        r = check(t)
        rows.append(r)
        flag = "HIBA" if r.get("hiba") else ("GYENGE" if r["gyenge"] else "ok")
        print(f"{flag:6} {t['id']:22} áttekintő: {r.get('attekintok', '-'):>6}  "
              f"számmal: {r.get('szammal', '-')}/{r.get('cikkek', '-')}", flush=True)
    Path(a.ki).write_text(json.dumps({"datum": time.strftime("%Y-%m-%d"), "temak": rows},
                                     ensure_ascii=False, indent=1), encoding="utf-8")
    weak = [r["id"] for r in rows if r.get("gyenge")]
    err = [r["id"] for r in rows if r.get("hiba")]
    print(f"\n{len(rows)} téma, gyenge: {len(weak)} {weak}, hiba: {len(err)} {err}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
