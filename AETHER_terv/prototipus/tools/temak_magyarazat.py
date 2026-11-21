"""Nyers magyarázatok a témákhoz, lektorálásra (a témafájlokba írja őket).

Témánként: 4 tudományos áttekintő cikk (OpenAlex, Wikipédia nélkül) -> AI-magyarázat ("Mire jó?", "Mi a gond
vele?", "Mennyire bizonyított?") és a "Forrás" sorok. Csak az üres magyarázatú témákat tölti ki,
a lektorált ("Lektorálva: igen") témákhoz sosem nyúl. Minden téma után ment, így bármikor
megszakítható és folytatható.

Használat:
    python tools/temak_magyarazat.py --ai ollama [--nyelv hu|en] [--csak id1,id2] [--max 10]
Az Ollama-modell: AETHER_OLLAMA_MODEL (pl. qwen3:4b), különben a gépre ajánlott.
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from aether_lab import temak_txt, topic                  # noqa: E402
from aether_lab.llm import get_provider                   # noqa: E402
from aether_lab.world_state import _http                  # noqa: E402

KEYS = ("mire_jo", "hatranyok", "mennyire_bizonyitott")


def sources(res: dict) -> list:
    out = []
    for c in res.get("cikkek", []):
        ev = f" ({c['ev']})" if c.get("ev") else ""
        out.append(f"{c['cim']}{ev} – {c['link']}")
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ai", default="ollama")
    ap.add_argument("--nyelv", default="hu", choices=["hu", "en"])
    ap.add_argument("--csak", default="")
    ap.add_argument("--max", type=int, default=0, help="legfeljebb ennyi témát (0: mind)")
    a = ap.parse_args()
    provider = get_provider(a.ai)
    if provider is None:
        print("Ehhez AI kell (--ai ollama/claude/openai/gemini).")
        return 1
    suf = "_en" if a.nyelv == "en" else ""
    only = {x for x in a.csak.split(",") if x}
    todo = [t for t in temak_txt.load()
            if (not only or t["id"] in only) and not t["lektoralva"] and not t["mire_jo" + suf]]
    if a.max:
        todo = todo[:a.max]
    print(f"{len(todo)} téma, AI: {a.ai} {getattr(provider, 'model', '')}", flush=True)
    for i, t in enumerate(todo, 1):
        t0 = time.time()
        title = t["cim_en"] if suf else t["cim"]
        res = topic.build(t["attekintes"], _http, provider, a.nyelv, log=lambda m: None, title=title)
        m = res.get("magyarazat") or {}
        if not any(str(m.get(k, "")).strip() for k in KEYS):
            print(f"[{i}/{len(todo)}] {t['id']}: nem sikerült ({res.get('megjegyzes', '')[:120]})", flush=True)
            continue
        # friss beolvasás: ha közben valaki szerkesztette a fájlt, azt ne írjuk felül
        cur = next((x for x in temak_txt.load() if x["id"] == t["id"]), None)
        if cur is None or cur["lektoralva"] or cur["mire_jo" + suf]:
            continue
        for k in KEYS:
            cur[k + suf] = " ".join(str(m.get(k, "")).split())
        if not cur["forras"]:
            cur["forras"] = sources(res)
        temak_txt.save_topic(cur)
        print(f"[{i}/{len(todo)}] {t['id']}: kész ({time.time() - t0:.0f} mp)", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
