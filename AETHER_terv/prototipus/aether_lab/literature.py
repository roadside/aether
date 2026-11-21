"""Valódi, publikált tudományos irodalom keresése nyílt API-kon keresztül.

Csak a Python standard könyvtárát használja (nincs külső függőség).

Források:
  - OpenAlex      https://api.openalex.org      (nyílt, ~250M mű; ingyenes API-kulcs ajánlott)
  - Semantic Scholar https://api.semanticscholar.org (ingyenes, kulcs opcionális)
  - arXiv         https://export.arxiv.org/api   (preprintek: NEM lektorált!)
  - Crossref      https://api.crossref.org       (DOI-metaadatok, visszavonások)

Minden találat egységes `Paper` objektummá alakul. A visszavont (retracted)
cikkeket megjelöljük, és a kutatási motor kizárja őket.
"""
from __future__ import annotations

import json
import os
import re
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field, asdict
from typing import Dict, List, Optional

USER_AGENT = "AETHER-research-prototype/0.1 (educational game prototype)"


@dataclass
class Paper:
    source: str                 # openalex | semanticscholar | arxiv | crossref
    source_id: str
    title: str
    year: Optional[int]
    doi: Optional[str] = None
    abstract: str = ""
    venue: str = ""
    authors: List[str] = field(default_factory=list)
    cited_by: int = 0
    url: str = ""
    peer_reviewed: Optional[bool] = None   # arXiv = False
    is_retracted: bool = False
    work_type: str = ""                    # article, review, preprint, ...
    orszagok: List[str] = field(default_factory=list)  # a szerzők intézményeinek országai (ISO-kód, OpenAlex)
    intezmenyek: Dict[str, List[str]] = field(default_factory=dict)  # országkód -> intézménynevek (OpenAlex)

    def key(self) -> str:
        if self.doi:
            return "doi:" + self.doi.lower()
        return "title:" + re.sub(r"[^a-z0-9]", "", self.title.lower())[:120]

    def citation(self) -> str:
        a = self.authors[0].split()[-1] if self.authors else "Ismeretlen"
        etal = " et al." if len(self.authors) > 1 else ""
        doi = f" https://doi.org/{self.doi}" if self.doi else (f" {self.url}" if self.url else "")
        return f"{a}{etal} ({self.year}). {self.title}. {self.venue}.{doi}"


def _get(url: str, headers: Optional[Dict[str, str]] = None, timeout: int = 30, retries: int = 3) -> bytes:
    h = {"User-Agent": USER_AGENT}
    if headers:
        h.update(headers)
    last = None
    for i in range(retries):
        try:
            req = urllib.request.Request(url, headers=h)
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read()
        except Exception as e:  # hálózati hiba, 429, 5xx
            last = e
            time.sleep(1.5 * (2 ** i))
    raise ConnectionError(f"Nem sikerült lekérni: {url} ({last})")


def _norm_doi(doi: Optional[str]) -> Optional[str]:
    if not doi:
        return None
    doi = doi.strip()
    doi = re.sub(r"^https?://(dx\.)?doi\.org/", "", doi, flags=re.I)
    return doi.lower() or None


# ---------------------------------------------------------------------------
# OpenAlex
# ---------------------------------------------------------------------------
def reconstruct_abstract(inverted: Optional[Dict[str, List[int]]]) -> str:
    """OpenAlex az absztraktot 'inverted index' formában adja vissza."""
    if not inverted:
        return ""
    pos = {}
    for word, idxs in inverted.items():
        for i in idxs:
            pos[i] = word
    return " ".join(pos[i] for i in sorted(pos))


def parse_openalex(data: Dict) -> List[Paper]:
    out = []
    for w in data.get("results", []):
        src = ((w.get("primary_location") or {}).get("source") or {})
        out.append(Paper(
            source="openalex",
            source_id=w.get("id", ""),
            title=w.get("display_name") or w.get("title") or "",
            year=w.get("publication_year"),
            doi=_norm_doi(w.get("doi")),
            abstract=reconstruct_abstract(w.get("abstract_inverted_index")),
            venue=src.get("display_name") or "",
            authors=[(a.get("author") or {}).get("display_name", "") for a in w.get("authorships", [])],
            cited_by=w.get("cited_by_count") or 0,
            url=(w.get("open_access") or {}).get("oa_url") or w.get("id", ""),
            peer_reviewed=None if w.get("type") == "preprint" else True,
            is_retracted=bool(w.get("is_retracted")),
            work_type=w.get("type") or "",
            orszagok=sorted({c for a in w.get("authorships", []) for c in (a.get("countries") or []) if c}),
            intezmenyek=_institutions(w),
        ))
    return out


def _institutions(w: Dict) -> Dict[str, List[str]]:
    """Országonként a szerzők intézményei, az első előfordulás sorrendjében."""
    out: Dict[str, List[str]] = {}
    for a in w.get("authorships", []) or []:
        for inst in a.get("institutions") or []:
            c, name = inst.get("country_code") or "", inst.get("display_name") or ""
            if c and name and name not in out.setdefault(c, []):
                out[c].append(name)
    return out


def search_openalex(query: str, n: int = 10, mailto: str = "", api_key: str = "",
                    from_year: int = 2000, country: str = "") -> List[Paper]:
    """country: ISO-kód (pl. HU) – csak azok a cikkek, amelyeknek van ilyen országbeli intézményű szerzője."""
    flt = f"has_abstract:true,from_publication_date:{from_year}-01-01"
    if country:
        flt += f",authorships.countries:{country.upper()}"
    params = {
        "search": query,
        "per-page": str(n),
        "filter": flt,
        "sort": "relevance_score:desc",
    }
    mailto = mailto or os.environ.get("AETHER_MAILTO", "")
    api_key = api_key or os.environ.get("OPENALEX_API_KEY", "")   # saját kulcs: nagyobb napi keret
    if mailto:
        params["mailto"] = mailto
    if api_key:
        params["api_key"] = api_key
    url = "https://api.openalex.org/works?" + urllib.parse.urlencode(params)
    return parse_openalex(json.loads(_get(url)))


# ---------------------------------------------------------------------------
# Semantic Scholar
# ---------------------------------------------------------------------------
def parse_semanticscholar(data: Dict) -> List[Paper]:
    out = []
    for p in data.get("data", []) or []:
        ext = p.get("externalIds") or {}
        types = p.get("publicationTypes") or []
        out.append(Paper(
            source="semanticscholar",
            source_id=p.get("paperId", ""),
            title=p.get("title") or "",
            year=p.get("year"),
            doi=_norm_doi(ext.get("DOI")),
            abstract=p.get("abstract") or "",
            venue=p.get("venue") or "",
            authors=[a.get("name", "") for a in p.get("authors", []) or []],
            cited_by=p.get("citationCount") or 0,
            url=(p.get("openAccessPdf") or {}).get("url") or f"https://www.semanticscholar.org/paper/{p.get('paperId','')}",
            peer_reviewed=False if (ext.get("ArXiv") and not ext.get("DOI")) else None,
            work_type=",".join(types),
        ))
    return out


def search_semanticscholar(query: str, n: int = 10, api_key: str = "") -> List[Paper]:
    params = {
        "query": query, "limit": str(n),
        "fields": "title,abstract,year,externalIds,citationCount,venue,publicationTypes,openAccessPdf,authors",
    }
    url = "https://api.semanticscholar.org/graph/v1/paper/search?" + urllib.parse.urlencode(params)
    headers = {"x-api-key": api_key} if api_key else None
    return parse_semanticscholar(json.loads(_get(url, headers=headers)))


# ---------------------------------------------------------------------------
# arXiv (Atom XML)
# ---------------------------------------------------------------------------
_ATOM = {"a": "http://www.w3.org/2005/Atom", "arxiv": "http://arxiv.org/schemas/atom"}


def parse_arxiv(xml_bytes: bytes) -> List[Paper]:
    root = ET.fromstring(xml_bytes)
    out = []
    for e in root.findall("a:entry", _ATOM):
        title = " ".join((e.findtext("a:title", "", _ATOM) or "").split())
        published = e.findtext("a:published", "", _ATOM) or ""
        doi = e.findtext("arxiv:doi", None, _ATOM)
        out.append(Paper(
            source="arxiv",
            source_id=e.findtext("a:id", "", _ATOM),
            title=title,
            year=int(published[:4]) if published[:4].isdigit() else None,
            doi=_norm_doi(doi),
            abstract=" ".join((e.findtext("a:summary", "", _ATOM) or "").split()),
            venue="arXiv (preprint)",
            authors=[a.findtext("a:name", "", _ATOM) for a in e.findall("a:author", _ATOM)],
            url=e.findtext("a:id", "", _ATOM),
            peer_reviewed=False,
            work_type="preprint",
        ))
    return out


def search_arxiv(query: str, n: int = 10) -> List[Paper]:
    terms = " AND ".join(f"all:{t}" for t in query.split() if t)
    url = ("https://export.arxiv.org/api/query?"
           + urllib.parse.urlencode({"search_query": terms, "max_results": n, "sortBy": "relevance"}))
    time.sleep(3)  # arXiv kéri: legfeljebb 1 kérés / 3 mp
    return parse_arxiv(_get(url))


# ---------------------------------------------------------------------------
# Crossref (metaadat + visszavonás-ellenőrzés)
# ---------------------------------------------------------------------------
def _strip_jats(s: str) -> str:
    return " ".join(re.sub(r"<[^>]+>", " ", s or "").split())


def parse_crossref(data: Dict) -> List[Paper]:
    out = []
    for it in (data.get("message") or {}).get("items", []):
        year = None
        dp = (it.get("issued") or {}).get("date-parts") or [[None]]
        if dp and dp[0] and dp[0][0]:
            year = int(dp[0][0])
        out.append(Paper(
            source="crossref",
            source_id=it.get("DOI", ""),
            title=(it.get("title") or [""])[0],
            year=year,
            doi=_norm_doi(it.get("DOI")),
            abstract=_strip_jats(it.get("abstract", "")),
            venue=(it.get("container-title") or [""])[0],
            authors=[f"{a.get('given','')} {a.get('family','')}".strip() for a in it.get("author", []) or []],
            cited_by=it.get("is-referenced-by-count") or 0,
            url=it.get("URL", ""),
            peer_reviewed=True if it.get("type") == "journal-article" else None,
            work_type=it.get("type", ""),
        ))
    return out


def search_crossref(query: str, n: int = 10, mailto: str = "") -> List[Paper]:
    params = {"query": query, "rows": str(n), "filter": "has-abstract:true"}
    if mailto:
        params["mailto"] = mailto
    url = "https://api.crossref.org/works?" + urllib.parse.urlencode(params)
    return parse_crossref(json.loads(_get(url)))


def crossref_is_retracted(doi: str, mailto: str = "") -> bool:
    """Van-e olyan Crossref-bejegyzés, amely visszavonja (retraction) ezt a DOI-t."""
    params = {"filter": f"updates:{doi}", "rows": "20"}
    if mailto:
        params["mailto"] = mailto
    url = "https://api.crossref.org/works?" + urllib.parse.urlencode(params)
    try:
        data = json.loads(_get(url))
    except ConnectionError:
        return False  # nem tudtuk ellenőrizni -> a riport jelzi
    for it in (data.get("message") or {}).get("items", []):
        for upd in it.get("update-to", []) or []:
            if _norm_doi(upd.get("DOI")) == _norm_doi(doi) and "retract" in (upd.get("type") or "").lower():
                return True
    return False


# ---------------------------------------------------------------------------
# Egyesítés, rangsorolás
# ---------------------------------------------------------------------------
def merge(papers: List[Paper]) -> List[Paper]:
    """DOI / cím alapján összevonja a duplikátumokat; a leghosszabb absztraktot tartja meg."""
    best: Dict[str, Paper] = {}
    for p in papers:
        k = p.key()
        cur = best.get(k)
        if cur is None:
            best[k] = p
            continue
        countries = sorted(set(p.orszagok) | set(cur.orszagok))
        insts = {c: list(dict.fromkeys(cur.intezmenyek.get(c, []) + p.intezmenyek.get(c, [])))
                 for c in set(p.intezmenyek) | set(cur.intezmenyek)}
        if len(p.abstract) > len(cur.abstract):
            p.cited_by = max(p.cited_by, cur.cited_by)
            p.is_retracted = p.is_retracted or cur.is_retracted
            p.orszagok = countries
            p.intezmenyek = insts
            best[k] = p
        else:
            cur.cited_by = max(p.cited_by, cur.cited_by)
            cur.is_retracted = p.is_retracted or cur.is_retracted
            cur.orszagok = countries
            cur.intezmenyek = insts
    return list(best.values())


def rank(papers: List[Paper]) -> List[Paper]:
    """Egyszerű, átlátható sorrend: lektorált > preprint, összefoglaló/meta-analízis előny,
    idézettség (log), frissesség. Nem 'igazság' mérő, csak olvasási sorrend."""
    import math
    def score(p: Paper) -> float:
        s = math.log10(1 + p.cited_by)
        if p.peer_reviewed is False:
            s -= 1.0
        t = (p.title + " " + p.work_type).lower()
        if "meta-analys" in t or "systematic review" in t or "review" in p.work_type:
            s += 1.0
        if p.year:
            s += max(0, (p.year - 2010)) * 0.03
        if not p.abstract:
            s -= 2.0
        return s
    return sorted([p for p in papers if not p.is_retracted], key=score, reverse=True)


def search_all(queries: List[str], per_source: int = 8, mailto: str = "",
               openalex_key: str = "", s2_key: str = "", use_arxiv: bool = True,
               log=print, country: str = "") -> List[Paper]:
    found: List[Paper] = []
    off = set()   # forrás, amely "túl sok kérés" (429) hibát adott: a többi kérdésnél kihagyjuk
    for q in queries:
        for name, fn in [
            ("OpenAlex", lambda: search_openalex(q, per_source, mailto, openalex_key)),
            ("Semantic Scholar", lambda: search_semanticscholar(q, per_source, s2_key)),
            ("Crossref", lambda: search_crossref(q, per_source, mailto)),
        ] + ([("arXiv", lambda: search_arxiv(q, per_source))] if use_arxiv else []) + (
            # hazai kutatás: külön keresés a játékos országának intézményeire (OpenAlex)
            [(f"OpenAlex, {country.upper()}", lambda: search_openalex(q, per_source, mailto, openalex_key,
                                                                      country=country))] if country else []):
            if name in off:
                continue
            try:
                res = fn()
                log(f"  [{name}] '{q}': {len(res)} találat")
                found.extend(res)
            except Exception as e:
                log(f"  [{name}] '{q}': HIBA ({e}) – kihagyva")
                if "429" in str(e):
                    off.add(name)
    merged = merge(found)
    return rank(merged)
