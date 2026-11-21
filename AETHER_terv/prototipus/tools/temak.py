"""Az AETHER kutatási témái (küldetések): a játék tudásfája.

A témák forrása a lektorálható szövegfájlok: AETHER_godot/temak/<terület>.txt
(formátum: aether_lab/temak_txt.py). Ez a szkript csak ellenőriz:

    python tools/temak.py      ->  hibák listája, vagy összesítés

Minden téma egy valódi kutatási kérdés. A válasz (a szám) mindig a játékos kutatásából,
valódi cikkekből jön. Hogy minden témához van-e szakirodalom, azt a
tools/temak_ellenorzes.py nézi meg.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from aether_lab import temak_txt   # noqa: E402

TERULETEK = temak_txt.TERULETEK
TEMAK = temak_txt.load()


def validate(topics=None) -> list:
    """Hibák listája (üres, ha minden rendben)."""
    from aether_lab.evidence import PARAMETERS
    topics = TEMAK if topics is None else topics
    errs, ids = [], set()
    for t in topics:
        if t["id"] in ids:
            errs.append(f"dupla azonosító: {t['id']}")
        ids.add(t["id"])
        if not t["id"].isascii():
            errs.append(f"ékezetes azonosító: {t['id']}")
        for f in t["forras"]:
            if "wikipedia.org" in f.lower():
                errs.append(f"a Wikipédia nem tudományos forrás: {t['id']}")
        if t["korszak"] not in (1, 2, 3, 4):
            errs.append(f"rossz korszak: {t['id']}")
        for p in t["parameterek"].split(","):
            if p.strip() not in PARAMETERS:
                errs.append(f"ismeretlen paraméter {p}: {t['id']}")
        for k in ("cim", "cim_en", "magyarazat", "magyarazat_en", "kereses", "attekintes"):
            if not str(t[k]).strip():
                errs.append(f"üres mező ({k}): {t['id']}")
        if not t["cim"].endswith("?") or not t["cim_en"].endswith("?"):
            errs.append(f"a kérdés nem kérdőjellel végződik: {t['id']}")
    return errs


def main() -> int:
    errs = validate()
    if errs:
        print("\n".join(errs))
        return 1
    per = {e: sum(1 for t in TEMAK if t["korszak"] == e) for e in (1, 2, 3, 4)}
    expl = sum(1 for t in TEMAK if t["mire_jo"])
    rev = sum(1 for t in TEMAK if t["lektoralva"])
    print(f"{len(TEMAK)} téma, korszakonként {per}; magyarázattal: {expl}; lektorálva: {rev}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
