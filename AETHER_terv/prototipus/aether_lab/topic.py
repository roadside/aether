"""„Mi ez, és mire jó?” – egy kutatási téma érthető bemutatása laikusoknak.

Forrás: tudományos összefoglaló (review) cikkek absztraktjai az OpenAlexből, linkkel.
(A Wikipédiát szándékosan nem használjuk: nem tudományos forrás.)

Ha van AI, ezekből (és CSAK ezekből) rövid részeket ír a játékos nyelvén:
mire jó, mi a gond vele, mennyire bizonyított. AI nélkül csak a cikkek listája jelenik meg.

Használat:  python -m aether_lab tema --kereses "biochar review" --cim "Mennyi CO2-t ...?"
                --ki tema.json [--ai ollama] [--nyelv hu]
"""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Callable, Dict, List, Optional

N_REVIEWS = 4
MAX_ABSTRACT = 1500

TOPIC_SCHEMA = {
    "type": "object",
    "properties": {
        "mi_ez": {"type": "string"},
        "mire_jo": {"type": "string"},
        "hatranyok": {"type": "string"},
        "mennyire_bizonyitott": {"type": "string"},
    },
    "required": ["mi_ez", "mire_jo", "hatranyok", "mennyire_bizonyitott"],
    "additionalProperties": False,
}

TOPIC_SYSTEM = """Egy klímajáték játékosának magyarázol el egy témát. A játékos nem szakember,
lehet fiatal is. Szabályok:
- CSAK a megadott forrásszövegekből dolgozz (tudományos összefoglaló cikkek absztraktjai).
  Ne tegyél hozzá saját tudást, ne találj ki számot.
- Mind a négy mező 1-2 rövid, hétköznapi mondat a megadott nyelven, szakszavak nélkül
  (ha mégis kell egy, magyarázd meg).
- 'mi_ez': mi ez a dolog. 'mire_jo': miért segíthet a klímán vagy az embereken.
- 'hatranyok': mi a gond vele, mik a korlátai, kockázatai (a források szerint).
- 'mennyire_bizonyitott': mennyire biztos a tudomány ebben, a források alapján.
- Ha a téma nem módszer, hanem hatás (pl. mi lesz a terméssel), akkor 'mire_jo': miért fontos
  ezt tudni, és mit lehet tenni ellene; 'hatranyok': mi a legnagyobb veszély.
- Ne ismételd meg az utasításokat, és ne írd le, mit csinálsz: rögtön a magyarázatot írd.
- Ne ismételd ugyanazt a mondatot több mezőben.
- Ha a források valamiről nem szólnak, írd azt, hogy erről a források nem szólnak."""

# Ha a kis modell az utasítást „visszhangozza”, azt a mezőt eldobjuk.
_ECHO = ("klímajáték", "climate game", "magyarázatát készítjük", "egy témában", "the player",
         "a játékos", "forrásszöveg", "source text")


def clean_explanation(m: Dict, lang: str = "hu") -> Dict:
    out = {}
    for k, v in m.items():
        t = str(v).strip()
        if any(e in t.lower() for e in _ECHO):
            t = ""
        if t and not lang.startswith("en"):
            from .evidence import hungarianize
            t = hungarianize(t)
        out[k] = t
    return out


def _stem(w: str) -> str:
    import unicodedata
    w = unicodedata.normalize("NFKD", w.lower())
    w = "".join(c for c in w if c.isalnum())
    return w[:5]


def title_matches(title: str, term: str) -> bool:
    """A cikk címe tényleg a keresett témáról szól? A keresőszó minden érdemi (4+ betűs)
    szavának töve szerepeljen a címben ("drought tolerance maize" ≠ "Drought tolerance in barley")."""
    words = [w for w in term.replace("-", " ").split() if len(w) >= 4] or term.split()[:1]
    t = [_stem(x) for x in title.replace("-", " ").replace("(", " ").replace(")", " ").split()]
    return bool(words) and all(_stem(w) in t for w in words)


def build(review_query: str, fetch: Callable[..., bytes], provider=None, lang: str = "hu", log=print,
          search_reviews=None, title: str = "") -> Dict:
    en = lang.startswith("en")
    res = {"cikkek": [], "magyarazat": None, "tipus": "forras", "megjegyzes": ""}
    try:
        if search_reviews is None:
            from .literature import search_openalex
            search_reviews = lambda q: search_openalex(q, 8)  # noqa: E731
        papers = [p for p in search_reviews(review_query) if p.abstract][:N_REVIEWS]
        res["cikkek"] = [{"cim": p.title, "ev": int(p.year) if p.year else "", "folyoirat": p.venue,
                          "link": f"https://doi.org/{p.doi}" if p.doi else p.url,
                          "absztrakt": p.abstract[:MAX_ABSTRACT]} for p in papers]
    except Exception as e:
        log(f"OpenAlex: {e}")
    if provider is not None and res["cikkek"]:
        parts = [f"<cikk {i}: {c['cim']} ({c['ev']})>\n{c['absztrakt']}\n</cikk>" for i, c in enumerate(res["cikkek"], 1)]
        theme = title or review_query   # a játék kérdése érthetőbb, mint a keresőszó
        user = f"Nyelv: {'English' if en else 'magyar'}\nTéma: {theme}\n\n" + "\n\n".join(parts)
        if en:   # a rendszerprompt magyar, ezért a kis modellek hajlamosak magyarul válaszolni
            user += "\n\nIMPORTANT: write all four fields in ENGLISH."
        try:
            res["magyarazat"] = clean_explanation(provider.json_call(TOPIC_SYSTEM, user, TOPIC_SCHEMA, 1500), lang)
            res["tipus"] = "ai"
        except Exception as e:
            res["megjegyzes"] = (f"AI explanation failed: {e}" if en else f"Az AI-magyarázat nem sikerült: {e}")
    for c in res["cikkek"]:
        c.pop("absztrakt", None)   # a játéknak elég a cím és a link
    return res


def cmd_tema(args):
    from .world_state import _http
    from .llm import get_provider
    provider, note = None, ""
    if args.ai != "none":
        try:
            provider = get_provider(args.ai)
        except Exception as e:
            note = str(e)
    res = build(args.kereses, _http, provider, args.nyelv, title=args.cim)
    if note:
        res["megjegyzes"] = (res["megjegyzes"] + " " + note).strip()
    out = Path(args.ki)
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(".tmp")
    tmp.write_text(json.dumps(res, ensure_ascii=False, indent=1), encoding="utf-8")
    os.replace(tmp, out)


def add_parsers(sub):
    p = sub.add_parser("tema", help="„Mi ez, és mire jó?” – téma érthető bemutatása forrásokkal")
    p.add_argument("--kereses", required=True, help="angol keresőkifejezés összefoglaló cikkekhez")
    p.add_argument("--ki", required=True)
    p.add_argument("--cim", default="", help="a játék kérdése (az AI ezt magyarázza)")
    p.add_argument("--ai", default="none", choices=["claude", "openai", "gemini", "ollama", "none"])
    p.add_argument("--nyelv", default="hu", choices=["hu", "en"])
    p.set_defaults(fn=cmd_tema)
