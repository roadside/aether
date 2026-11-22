"""„Hazai forrás” beküldésének gépi ellenőrzése.

A játékos megad egy hivatalos, nyilvános forrást a saját országából (egy hivatal mérési oldalát
vagy egy tudományos cikket DOI-val), egy szó szerinti idézetet belőle és a benne szereplő számot.
A gép ellenőrzi, mielőtt ember (a lektor) jóváhagyná:

  1. a forrás hivatalos-e: DOI (tudományos cikk), vagy az ország hivatalos/tudományos domainje
     (az engedélyezett lista bővíthető, de csak ellenőrzés után);
  2. a forrás letölthető-e, és az idézet SZÓ SZERINT benne van-e (ugyanazzal a szabállyal, mint a
     kutatásnál: evidence.quote_in);
  3. a megadott szám benne van-e az idézetben;
  4. ha DOI: nincs-e visszavonva (Crossref).

Az eredmény egy rövid jelentés: {"elfogadhato": bool, "okok": [...], "forras": {...}}. Elfogadás
esetén is csak „gépileg ellenőrzött”: a közös archívumba a lektor jóváhagyása után kerül.

Parancs:
  python -m aether_lab hazai-ellenorzes --forras URL_vagy_DOI --idezet "..." --szam 12.5 [--orszag HU] [--ki eredmeny.json]
"""
from __future__ import annotations

import json
import re
import urllib.parse
from html import unescape
from pathlib import Path
from typing import Callable, Dict, List

from . import evidence as ev
from .biztos_iras import write_text

# Hivatalos és tudományos domainek országonként (bővíthető, de csak ellenőrzés után).
OFFICIAL = {
    "HU": ["met.hu", "levegominoseg.hu", "ksh.hu", "vizugy.hu", "ovf.hu", "nebih.gov.hu", "kormany.hu",
           "mtmt.hu", "real.mtak.hu", "elte.hu", "bme.hu", "u-szeged.hu", "unideb.hu", "uni-mate.hu",
           "ecolres.hu", "hun-ren.hu", "nnk.gov.hu", "katasztrofavedelem.hu"],
    "EU": ["eea.europa.eu", "copernicus.eu", "ec.europa.eu", "europa.eu", "ecmwf.int"],
}
DOI_RE = re.compile(r"^(?:https?://(?:dx\.)?doi\.org/|doi:)?(10\.\d{4,9}/\S+)$", re.I)


def _host(url: str) -> str:
    return (urllib.parse.urlparse(url).hostname or "").lower()


def official_domain(url: str, country: str = "HU") -> bool:
    h = _host(url)
    allowed = OFFICIAL.get(country.upper(), []) + OFFICIAL["EU"]
    return any(h == d or h.endswith("." + d) for d in allowed)


def _text_of_html(raw: str) -> str:
    raw = re.sub(r"(?is)<(script|style).*?</\1>", " ", raw)
    return " ".join(unescape(re.sub(r"(?s)<[^>]+>", " ", raw)).split())


def _retracted(meta: Dict) -> bool:
    """Crossref-metaadat: visszavonás jelzése (update-to: retraction, vagy is-retracted-by kapcsolat)."""
    for u in meta.get("update-to") or []:
        if "retract" in str(u.get("type", "")).lower():
            return True
    rel = meta.get("relation") or {}
    return bool(rel.get("is-retracted-by"))


def check(source: str, quote: str, number: float, fetch: Callable[[str], bytes], country: str = "HU",
          mailto: str = "") -> Dict:
    reasons: List[str] = []
    src: Dict = {"megadott": source}
    text = ""
    m = DOI_RE.match(source.strip())
    if m:
        doi = m.group(1).rstrip(".")
        src.update(tipus="doi", doi=doi)
        try:
            meta = json.loads(fetch("https://api.crossref.org/works/" + urllib.parse.quote(doi)).decode("utf-8"))["message"]
        except Exception as e:
            return {"elfogadhato": False, "okok": [f"A DOI nem található: {e}"], "forras": src}
        src["cim"] = (meta.get("title") or [""])[0]
        if _retracted(meta):
            reasons.append("A cikket visszavonták.")
        text = _text_of_html(str(meta.get("abstract", "")))
        if not text:
            # a Crossref nem mindig ad absztraktot: az OpenAlexben is megnézzük
            try:
                oa = json.loads(fetch("https://api.openalex.org/works/doi:" + urllib.parse.quote(doi)).decode("utf-8"))
                inv = oa.get("abstract_inverted_index") or {}
                words = sorted(((p, w) for w, ps in inv.items() for p in ps))
                text = " ".join(w for _, w in words)
            except Exception:
                pass
    elif source.startswith(("http://", "https://")):
        src.update(tipus="weboldal", domain=_host(source))
        if not official_domain(source, country):
            reasons.append(f"A „{_host(source)}” nem szerepel a hivatalos források listáján. "
                           "Ha hivatalos, kérd a felvételét.")
        try:
            text = _text_of_html(fetch(source).decode("utf-8", "replace"))
        except Exception as e:
            return {"elfogadhato": False, "okok": reasons + [f"Az oldal nem tölthető le: {e}"], "forras": src}
    else:
        return {"elfogadhato": False, "okok": ["Adj meg egy DOI-t vagy egy hivatalos weboldal címét."], "forras": src}
    if not text:
        reasons.append("A forrásban nincs ellenőrizhető szöveg (például csak PDF): ezt a lektor nézi meg.")
    elif not ev.quote_in(quote, text):
        reasons.append("Az idézet nem található szó szerint a forrásban.")
    if not any(abs(n - float(number)) < 1e-9 for n in ev.numbers_in(quote)):
        reasons.append("A megadott szám nincs benne az idézetben.")
    return {"elfogadhato": not reasons, "okok": reasons, "forras": src,
            "idezet": quote, "szam": float(number), "orszag": country.upper()}


def add_parsers(sub) -> None:
    p = sub.add_parser("hazai-ellenorzes", help="egy hazai forrás gépi ellenőrzése")
    p.add_argument("--forras", required=True)
    p.add_argument("--idezet", required=True)
    p.add_argument("--szam", type=float, required=True)
    p.add_argument("--orszag", default="HU")
    p.add_argument("--ki", default="")

    def _run(a):
        from .world_state import _http
        res = check(a.forras, a.idezet, a.szam, lambda u: _http(u, timeout=40), a.orszag)
        txt = json.dumps(res, ensure_ascii=False, indent=1)
        if a.ki:
            write_text(Path(a.ki), txt)
        else:
            print(txt)
        return 0
    p.set_defaults(fn=_run)
