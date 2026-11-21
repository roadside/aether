"""A kutatási folyamat: kérdés -> keresés -> kivonatolás -> ellenőrzés -> publikáció.

A "publikáció" egy JSON-fájl, amely minden bemenetet tartalmaz (lekérdezések,
cikkazonosítók, kinyert állítások, ellenőrzés eredménye, modellparaméterek).
A tartalom SHA-256 ujjlenyomata a publikáció azonosítója: így egy másik játékos
AI-ja ugyanabból a bemenetből újra tudja futtatni és ellenőrizni ("replikáció").
"""
from __future__ import annotations

import datetime as _dt
import hashlib
import json
from dataclasses import asdict
from typing import Dict, List, Optional

from . import evidence as ev
from .literature import Paper, search_all
from .llm import Provider

MAX_ABSTRACT_CHARS = 2500


def plan_queries(provider: Optional[Provider], question: str) -> Dict:
    if provider is None:
        # AI nélküli mód: a kérdést változatlanul használjuk keresőkifejezésként
        return {"kutatasi_kerdes_pontositva": question, "angol_keresokifejezesek": [question],
                "keresett_parameterek": [], "megjegyzes": "AI nélküli mód: nincs kérdéspontosítás."}
    return provider.json_call(ev.PLANNER_SYSTEM, f"Kutatási kérdés: {question}", ev.QUERY_PLAN_SCHEMA, 2000)


def extract(provider: Provider, question: str, papers: Dict[str, Paper], params: List[str],
            lang: str = "hu") -> Dict:
    cap = getattr(provider, "max_abstract_chars", MAX_ABSTRACT_CHARS)
    blocks = []
    for pid, p in papers.items():
        flag = " [PREPRINT, nem lektorált]" if p.peer_reviewed is False else ""
        blocks.append(f"<cikk azonosito=\"{pid}\">\nCím: {p.title}{flag}\nÉv: {p.year}\n"
                      f"Absztrakt: {p.abstract[:cap]}\n</cikk>")
    wanted_list = params or [k for k in ev.PARAMETERS if k != "egyeb"]
    wanted = "\n".join(f"- {k}: {ev.PARAMETERS[k]['leiras']} (egység: {ev.PARAMETERS[k]['unit']})"
                       for k in wanted_list if k in ev.PARAMETERS)
    user = (f"Kutatási kérdés: {question}\nKeresett paraméterek (csak ezekhez emelj ki számot, "
            f"a megadott egységben):\n{wanted}\n"
            "Ha egy cikk nem erről szól (pl. a kérdés a talajba juttatott bioszénről szól, a cikk pedig "
            "laboratóriumi gázmegkötő anyagról), abból NE emelj ki számot.\n\n"
            + "\n\n".join(blocks))
    if lang.startswith("en"):
        user += ("\n\nA játékos angolul játszik: az 'osszegzes' és az 'ellentmondasok' mezőt "
                 "ANGOLUL írd (write these two fields in plain English). A többi mező marad.")
    return provider.json_call(ev.EXTRACTOR_SYSTEM, user, ev.EXTRACTION_SCHEMA, 16000)


def run_research(question: str, provider: Optional[Provider], n_papers: int = 12,
                 per_source: int = 6, mailto: str = "", openalex_key: str = "",
                 s2_key: str = "", use_arxiv: bool = True, log=print, lang: str = "hu",
                 queries: Optional[List[str]] = None, params: Optional[List[str]] = None) -> Dict:
    en = lang.startswith("en")
    m = lambda hu, eng: eng if en else hu  # noqa: E731  (napló a játékos nyelvén)
    log(m("1/4 Kérdés pontosítása...", "1/4 Refining the question..."))
    if queries and params is not None:
        # előre összeállított kérdés: a keresőkifejezéseket és a paramétereket szakértő adta meg,
        # így nem kell AI-hívás a tervezéshez (gyorsabb, és nem téved paramétert)
        plan = {"kutatasi_kerdes_pontositva": question, "angol_keresokifejezesek": list(queries),
                "keresett_parameterek": [p for p in params if p in ev.PARAMETERS],
                "megjegyzes": "Előre összeállított kérdés."}
    else:
        plan = plan_queries(provider, question)
    queries = plan["angol_keresokifejezesek"][:5]
    log(m(f"    Keresőkifejezések: {queries}", f"    Search terms: {queries}"))

    log(m("2/4 Irodalomkeresés (OpenAlex, Semantic Scholar, Crossref, arXiv)...",
          "2/4 Literature search (OpenAlex, Semantic Scholar, Crossref, arXiv)..."))
    ranked = search_all(queries, per_source, mailto, openalex_key, s2_key, use_arxiv, log)
    chosen = ranked[:min(n_papers, getattr(provider, "max_papers", n_papers))]
    papers = {f"P{i+1}": p for i, p in enumerate(chosen)}
    log(m(f"    {len(ranked)} egyedi, nem visszavont cikk; a legjobb {len(papers)} kerül elemzésre.",
          f"    {len(ranked)} unique, non-retracted papers; the best {len(papers)} are analysed."))

    claims: List[ev.Claim] = []
    summary, contradictions = "", ""
    if provider is not None and papers:
        log(m("3/4 AI-kivonatolás (szó szerinti idézetekkel)...", "3/4 AI extraction (with verbatim quotes)..."))
        raw = extract(provider, plan["kutatasi_kerdes_pontositva"], papers, plan["keresett_parameterek"], lang)
        claims = [ev.Claim(**c) for c in raw.get("allitasok", [])]
        summary, contradictions = raw.get("osszegzes", ""), raw.get("ellentmondasok", "")
    else:
        log(m("3/4 AI nélküli mód: kivonatolás kihagyva.", "3/4 No-AI mode: extraction skipped."))

    log(m("4/4 Determinisztikus ellenőrzés...", "4/4 Deterministic check..."))
    claims = ev.verify(claims, papers)
    agg = ev.aggregate(claims)
    ok = sum(c.statusz.startswith("ellenorizve") for c in claims)
    log(m(f"    {ok}/{len(claims)} állítás ment át az ellenőrzésen.", f"    {ok}/{len(claims)} claims passed the check."))

    pub = {
        "aether_publikacio_verzio": 1,
        "kerdes": question,
        "terv": plan,
        "ai": getattr(provider, "name", "none") + (f":{provider.model}" if provider is not None else ""),
        "cikkek": {pid: asdict(p) for pid, p in papers.items()},
        "allitasok": [asdict(c) for c in claims],
        "osszesitett_parameterek": agg,
        "ai_osszegzes": summary,
        "ellentmondasok": contradictions,
        "figyelmeztetes": ("Ez egy játékon belüli, automatikusan összeállított irodalmi összefoglaló. "
                           "Nem helyettesíti a szakértői lektorálást; minden számot az eredeti cikkben "
                           "érdemes ellenőrizni."),
    }
    canonical = json.dumps(pub, sort_keys=True, ensure_ascii=False).encode()
    pub["azonosito"] = "AETHER-" + hashlib.sha256(canonical).hexdigest()[:16]
    pub["letrehozva"] = _dt.datetime.now(_dt.timezone.utc).isoformat(timespec="seconds")
    return pub


def to_markdown(pub: Dict) -> str:
    L = [f"# AETHER publikáció {pub['azonosito']}", "",
         f"**Kérdés:** {pub['kerdes']}  ", f"**AI:** {pub['ai']}  ", f"**Létrehozva:** {pub['letrehozva']}", "",
         f"> {pub['figyelmeztetes']}", ""]
    if pub.get("ai_osszegzes"):
        L += ["## Összegzés", pub["ai_osszegzes"], ""]
    if pub.get("ellentmondasok"):
        L += ["## Ellentmondások, korlátok", pub["ellentmondasok"], ""]
    if pub["osszesitett_parameterek"]:
        L += ["## Ellenőrzött paraméterek", "", "| Paraméter | Alkategória | Súlyozott medián | Tartomány | Források | Bizonyosság |",
              "|---|---|---|---|---|---|"]
        for a in pub["osszesitett_parameterek"].values():
            L.append(f"| {a['parameter']} | {a['alkategoria']} | {a['sulyozott_median']} {a['egyseg']} | "
                     f"{a['tartomany'][0]}–{a['tartomany'][1]} | {a['forrasok_szama']} | {a['bizonyossag']} |")
        L.append("")
    if pub["allitasok"]:
        L += ["## Állítások és ellenőrzésük", ""]
        for c in pub["allitasok"]:
            mark = "✅" if c["statusz"].startswith("ellenorizve") else "❌"
            L.append(f"- {mark} **{c['parameter']}** ({c['alkategoria']}): {c['ertek']} {c['egyseg']} "
                     f"[{c['cikk_azonosito']}, {c['vizsgalat_tipusa']}]  ")
            L.append(f"  „{c['szo_szerinti_idezet']}”  ")
            if c["indokok"]:
                L.append(f"  Elutasítás oka: {'; '.join(c['indokok'])}")
        L.append("")
    L += ["## Források", ""]
    for pid, p in pub["cikkek"].items():
        pr = " *(preprint, nem lektorált)*" if p["peer_reviewed"] is False else ""
        doi = f" https://doi.org/{p['doi']}" if p["doi"] else f" {p['url']}"
        authors = (p["authors"][0] if p["authors"] else "?") + (" et al." if len(p["authors"]) > 1 else "")
        L.append(f"- **{pid}** {authors} ({p['year']}). {p['title']}. *{p['venue']}*.{doi}{pr}")
    return "\n".join(L) + "\n"
