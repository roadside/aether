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


HOME_SLOTS = 2   # ennyi hely jut legalább a hazai cikkeknek az elemzettek között (ha vannak)


def select_papers(ranked: List[Paper], n: int, country: str = "") -> List[Paper]:
    """A legjobb n cikk, de ha van a játékos országából származó, abból legalább HOME_SLOTS
    bekerül (a sorrend egyébként változatlan, a hazai cikk nem kap más előnyt)."""
    chosen = ranked[:n]
    if not country:
        return chosen
    c = country.upper()
    have = sum(c in p.orszagok for p in chosen)
    extra = [p for p in ranked[n:] if c in p.orszagok][:max(0, HOME_SLOTS - have)]
    if extra:
        keep = [p for p in chosen if c in p.orszagok]
        others = [p for p in chosen if c not in p.orszagok][:n - len(keep) - len(extra)]
        chosen = [p for p in ranked if p in keep or p in others or p in extra]
    return chosen


def plan_queries(provider: Optional[Provider], question: str) -> Dict:
    if provider is None:
        # AI nélküli mód: a kérdést változatlanul használjuk keresőkifejezésként
        return {"kutatasi_kerdes_pontositva": question, "angol_keresokifejezesek": [question],
                "keresett_parameterek": [], "megjegyzes": "AI nélküli mód: nincs kérdéspontosítás."}
    return provider.json_call(ev.PLANNER_SYSTEM, f"Kutatási kérdés: {question}", ev.QUERY_PLAN_SCHEMA, 2000)


import re as _re

_SENT_SPLIT = _re.compile(r"(?<=[.!?])\s+(?=[A-Z(\[])")
INTRO_CHARS = 300   # az absztrakt eleje, hogy az AI lássa, miről szól a cikk


def candidate_sentences(abstract: str, params: List[str]) -> List[str]:
    """Az absztrakt azon mondatai, amelyekben szám ÉS a keresett paraméter mértékegysége is szerepel.
    Csak ezekből lehet ellenőrizhető állítás (az ellenőrző is ezt nézi), ezért az AI csak ezeket kapja:
    rövidebb a feladat, gyorsabb a helyi modell, és nem vész el egy felsorolás közepén lévő szám."""
    out = []
    for s in _SENT_SPLIT.split(" ".join((abstract or "").split())):
        if ev.numbers_in(s) and any(ev.unit_in_quote(k, s) for k in params if k in ev.UNIT_PATTERNS):
            out.append(s.strip())
    return out


EXAMPLE = """Példa. Mondat: "Potentials are 0.5–2 GtCO2 yr−1 for biochar and up to 5 GtCO2 yr−1 for soil carbon
sequestration." Ha a bioszén a téma: parameter=cdr_potencial_gtco2_ev, alkategoria=bioszén, also=0.5,
felso=2, ertek=2 (az 'ertek' mindig egy szám az idézetből), idézet: "0.5–2 GtCO2 yr−1 for biochar".
Az 5-ös szám egy másik módszeré (talaj szénmegkötés): azt külön állításként, a saját alkategóriájával add meg."""


def extract(provider: Provider, question: str, papers: Dict[str, Paper], params: List[str],
            lang: str = "hu", log=None) -> Dict:
    wanted_list = [k for k in (params or [k for k in ev.PARAMETERS if k != "egyeb"]) if k in ev.PARAMETERS]
    intro = min(INTRO_CHARS, getattr(provider, "max_abstract_chars", INTRO_CHARS))
    blocks = []
    for pid, p in papers.items():
        cands = candidate_sentences(p.abstract, wanted_list)
        if not cands:
            continue   # nincs benne szám a keresett mértékegységgel: ellenőrizhető állítás sem lehet
        flag = " [PREPRINT, nem lektorált]" if p.peer_reviewed is False else ""
        lines = "\n".join(f"  - {s}" for s in cands)
        blocks.append(f"<cikk azonosito=\"{pid}\">\nCím: {p.title}{flag}\nÉv: {p.year}\n"
                      f"Az absztrakt eleje: {p.abstract[:intro]}…\n"
                      f"Számot és mértékegységet tartalmazó mondatok (CSAK ezekből idézz, szó szerint):\n{lines}\n</cikk>")
    if log is not None:
        log((f"    {len(blocks)}/{len(papers)} papers contain a number with the right unit." if lang.startswith("en")
             else f"    {len(blocks)}/{len(papers)} cikkben van megfelelő mértékegységű szám."))
    if not blocks:
        return {"allitasok": [], "ellentmondasok": "",
                "osszegzes": ("The papers found contain no number with the unit we need." if lang.startswith("en")
                              else "A talált cikkekben nincs a keresett mértékegységű szám.")}
    wanted = "\n".join(f"- {k}: {ev.PARAMETERS[k]['leiras']} (egység: {ev.PARAMETERS[k]['unit']})"
                       for k in wanted_list)
    user = (f"Kutatási kérdés: {question}\nKeresett paraméterek (csak ezekhez emelj ki számot, "
            f"a megadott egységben):\n{wanted}\n"
            "Ha egy cikk nem erről szól (pl. a kérdés a talajba juttatott bioszénről szól, a cikk pedig "
            "laboratóriumi gázmegkötő anyagról), abból NE emelj ki számot.\n\n" + EXAMPLE + "\n\n"
            + "\n\n".join(blocks))
    if lang.startswith("en"):
        user += ("\n\nA játékos angolul játszik: az 'osszegzes' és az 'ellentmondasok' mezőt "
                 "ANGOLUL írd (write these two fields in plain English). A többi mező marad.")
    return provider.json_call(ev.EXTRACTOR_SYSTEM, user, ev.EXTRACTION_SCHEMA, 16000)


def run_research(question: str, provider: Optional[Provider], n_papers: int = 12,
                 per_source: int = 6, mailto: str = "", openalex_key: str = "",
                 s2_key: str = "", use_arxiv: bool = True, log=print, lang: str = "hu",
                 queries: Optional[List[str]] = None, params: Optional[List[str]] = None,
                 country: str = "") -> Dict:
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
    ranked = search_all(queries, per_source, mailto, openalex_key, s2_key, use_arxiv, log, country=country)
    chosen = select_papers(ranked, min(n_papers, getattr(provider, "max_papers", n_papers)), country)
    papers = {f"P{i+1}": p for i, p in enumerate(chosen)}
    log(m(f"    {len(ranked)} egyedi, nem visszavont cikk; a legjobb {len(papers)} kerül elemzésre.",
          f"    {len(ranked)} unique, non-retracted papers; the best {len(papers)} are analysed."))
    if country:
        home = sum(country.upper() in p.orszagok for p in papers.values())
        log(m(f"    Hazai ({country.upper()}) cikk az elemzettek között: {home}.",
              f"    Home-country ({country.upper()}) papers among those analysed: {home}."))

    claims: List[ev.Claim] = []
    summary, contradictions = "", ""
    raw_extraction = None
    if provider is not None and papers:
        log(m("3/4 AI-kivonatolás (szó szerinti idézetekkel)...", "3/4 AI extraction (with verbatim quotes)..."))
        raw = extract(provider, plan["kutatasi_kerdes_pontositva"], papers, plan["keresett_parameterek"], lang, log)
        raw_extraction = raw   # hibakereséshez: az AI nyers válasza a publikációba kerül
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
        "ai_nyers_kivonat": raw_extraction,
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
