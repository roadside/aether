"""Egy téma mezőinek javítása a témafájlban (a többi téma és a magyarázat érintetlen marad).

Használat:
    python tools/temak_javit.py atomenergia cim="Mennyi CO2-vel jár ...?" parameterek=eletciklus_gco2_kwh
A kulcsok a temak_txt.FIELDS kulcsai (cim, cim_en, magyarazat, kereses, parameterek, attekintes, ...).
Lektorált ("Lektorálva: igen") témán csak a technikai mezőket módosítja, hacsak nincs --akkor-is.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from aether_lab import temak_txt   # noqa: E402

TECH = {"kereses", "parameterek", "attekintes"}


def main(argv: list) -> int:
    force = "--akkor-is" in argv
    argv = [a for a in argv if a != "--akkor-is"]
    if len(argv) < 2:
        print(__doc__)
        return 1
    tid, pairs = argv[0], argv[1:]
    keys = {k for k, _ in temak_txt.FIELDS} - {"forras", "lektoralva", "korszak"}
    t = next((x for x in temak_txt.load() if x["id"] == tid), None)
    if t is None:
        print(f"Nincs ilyen téma: {tid}")
        return 1
    for p in pairs:
        k, _, v = p.partition("=")
        if k not in keys:
            print(f"Ismeretlen mező: {k}")
            return 1
        if t["lektoralva"] and k not in TECH and not force:
            print(f"{tid} lektorált, a(z) {k} mezőt nem írom felül (--akkor-is)")
            return 1
        t[k] = v.strip()
    temak_txt.save_topic(t)
    print(f"{tid}: frissítve ({', '.join(p.partition('=')[0] for p in pairs)})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
