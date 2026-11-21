"""„Mi ez, és mire jó?” – egy kutatási téma érthető bemutatása laikusoknak.

Források (mindegyik linkkel megjelenik a játékban):
  - Wikipédia a játékos nyelvén (ha nincs ilyen cikk, az angol), CC BY-SA 4.0,
  - 3 összefoglaló (review) tudományos cikk absztraktja az OpenAlexből.

Ha van AI, az ezekből (és CSAK ezekből) négy rövid részt ír a játékos nyelvén:
mi ez, mire jó, mi a gond vele, mennyire bizonyított. AI nélkül a Wikipédia
bevezetője és a cikkek listája jelenik meg.

Használat:  python -m aether_lab tema --wiki "bioszén" --wiki-en "biochar"
                --kereses "biochar review" --ki tema.json [--ai ollama] [--nyelv hu]
"""
from __future__ import annotations

import json
import os
import urllib.parse
from pathlib import Path
from typing import Callable, Dict, List, Optional

MAX_WIKI_CHARS = 5000
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
- CSAK a megadott forrásszövegekből dolgozz (Wikipédia-részlet és tudományos összefoglaló
  cikkek absztraktjai). Ne tegyél hozzá saját tudást, ne találj ki számot.
- Mind a négy mező 2-3 rövid, hétköznapi mondat a megadott nyelven, szakszavak nélkül
  (ha mégis kell egy, magyarázd meg).
- 'mi_ez': mi ez a dolog. 'mire_jo': miért segíthet a klímán vagy az embereken.
- 'hatranyok': mi a gond vele, mik a korlátai, kockázatai (a források szerint).
- 'mennyire_bizonyitott': mennyire biztos a tudomány ebben, a források alapján.
- Ha a források valamiről nem szólnak, írd azt, hogy erről a források nem szólnak."""


def wiki_search_url(lang: str, term: str) -> str:
    return f"https://{lang}.wikipedia.org/w/api.php?" + urllib.parse.urlencode(
        {"action": "query", "list": "search", "srsearch": term, "srlimit": 1, "format": "json"})


def wiki_extract_url(lang: str, title: str) -> str:
    return f"https://{lang}.wikipedia.org/w/api.php?" + urllib.parse.urlencode(
        {"action": "query", "prop": "extracts", "explaintext": 1, "exsectionformat": "plain",
         "titles": title, "format": "json", "redirects": 1})


def _stem(w: str) -> str:
    import unicodedata
    w = unicodedata.normalize("NFKD", w.lower())
    w = "".join(c for c in w if c.isalnum())
    return w[:5]


def title_matches(title: str, term: str) -> bool:
    """A cikk címe tényleg a keresett témáról szól? (a keresőszó első szavának töve a címben)"""
    first = (term.split() or [""])[0]
    t = [_stem(x) for x in title.replace("-", " ").split()]
    return bool(first) and _stem(first) in t


def wiki_article(fetch: Callable[..., bytes], lang: str, term: str) -> Optional[Dict]:
    """Az első találat cikkének szövege (a bevezetővel kezdve)."""
    hits = json.loads(fetch(wiki_search_url(lang, term))).get("query", {}).get("search", [])
    if not hits:
        return None
    title = hits[0]["title"]
    if not title_matches(title, term):
        return None   # pl. "bioszén" keresésre a "Biogáz" jött: az nem ugyanaz, inkább az angol cikk
    pages = json.loads(fetch(wiki_extract_url(lang, title))).get("query", {}).get("pages", {})
    text = next(iter(pages.values()), {}).get("extract", "") if pages else ""
    if len(text) < 200:
        return None
    intro = text.split("\n\n")[0].strip()
    return {"nyelv": lang, "cim": title, "bevezeto": intro[:1200], "szoveg": text[:MAX_WIKI_CHARS],
            "link": f"https://{lang}.wikipedia.org/wiki/" + urllib.parse.quote(title.replace(" ", "_")),
            "licenc": "CC BY-SA 4.0"}


def build(wiki_term: str, wiki_term_en: str, review_query: str, fetch: Callable[..., bytes],
          provider=None, lang: str = "hu", log=print, search_reviews=None) -> Dict:
    en = lang.startswith("en")
    res = {"wiki": None, "cikkek": [], "magyarazat": None, "tipus": "forras", "megjegyzes": ""}
    try:
        res["wiki"] = wiki_article(fetch, "en" if en else "hu", wiki_term_en if en else wiki_term)
        if res["wiki"] is None and not en:
            res["wiki"] = wiki_article(fetch, "en", wiki_term_en)
    except Exception as e:
        log(f"Wikipédia: {e}")
    try:
        if search_reviews is None:
            from .literature import search_openalex
            search_reviews = lambda q: search_openalex(q, 6)  # noqa: E731
        papers = [p for p in search_reviews(review_query) if p.abstract][:3]
        res["cikkek"] = [{"cim": p.title, "ev": int(p.year) if p.year else "", "folyoirat": p.venue,
                          "link": f"https://doi.org/{p.doi}" if p.doi else p.url,
                          "absztrakt": p.abstract[:MAX_ABSTRACT]} for p in papers]
    except Exception as e:
        log(f"OpenAlex: {e}")
    if provider is not None and (res["wiki"] or res["cikkek"]):
        parts = []
        if res["wiki"]:
            parts.append(f"<wikipedia nyelv=\"{res['wiki']['nyelv']}\">\n{res['wiki']['szoveg']}\n</wikipedia>")
        for i, c in enumerate(res["cikkek"], 1):
            parts.append(f"<cikk {i}: {c['cim']} ({c['ev']})>\n{c['absztrakt']}\n</cikk>")
        user = f"Nyelv: {'English' if en else 'magyar'}\nTéma: {wiki_term_en if en else wiki_term}\n\n" + "\n\n".join(parts)
        try:
            res["magyarazat"] = provider.json_call(TOPIC_SYSTEM, user, TOPIC_SCHEMA, 1500)
            res["tipus"] = "ai"
        except Exception as e:
            res["megjegyzes"] = (f"AI explanation failed: {e}" if en else f"Az AI-magyarázat nem sikerült: {e}")
    for c in res["cikkek"]:
        c.pop("absztrakt", None)   # a játéknak elég a cím és a link
    if res["wiki"]:
        res["wiki"].pop("szoveg", None)
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
    res = build(args.wiki, args.wiki_en, args.kereses, _http, provider, args.nyelv)
    if note:
        res["megjegyzes"] = (res["megjegyzes"] + " " + note).strip()
    out = Path(args.ki)
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(".tmp")
    tmp.write_text(json.dumps(res, ensure_ascii=False, indent=1), encoding="utf-8")
    os.replace(tmp, out)


def add_parsers(sub):
    p = sub.add_parser("tema", help="„Mi ez, és mire jó?” – téma érthető bemutatása forrásokkal")
    p.add_argument("--wiki", required=True, help="Wikipédia-keresőszó a játékos nyelvén (magyar)")
    p.add_argument("--wiki-en", required=True, help="angol Wikipédia-keresőszó")
    p.add_argument("--kereses", required=True, help="angol keresőkifejezés összefoglaló cikkekhez")
    p.add_argument("--ki", required=True)
    p.add_argument("--ai", default="none", choices=["claude", "openai", "gemini", "ollama", "none"])
    p.add_argument("--nyelv", default="hu", choices=["hu", "en"])
    p.set_defaults(fn=cmd_tema)
