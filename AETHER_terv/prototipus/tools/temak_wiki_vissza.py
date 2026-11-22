"""A Wikipédia-mezők visszaírása a témafájlokba (tools/temak_wiki.json alapján).

Csak az üres "Wikipédia" / "Wikipédia angolul" mezőket tölti ki, mást nem módosít.
    python tools/temak_wiki_vissza.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from aether_lab import temak_txt   # noqa: E402


def main() -> int:
    m = json.loads((HERE / "temak_wiki.json").read_text(encoding="utf-8"))
    topics = temak_txt.load()
    n = 0
    for t in topics:
        w = m.get(t["id"])
        if not w:
            continue
        for k in ("wiki", "wiki_en"):
            if not t[k].strip() and w.get(k):
                t[k] = w[k]
                n += 1
    temak_txt.save(topics)
    print(f"{n} mező visszaírva, {len(topics)} téma")
    return 0


if __name__ == "__main__":
    sys.exit(main())
