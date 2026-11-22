"""Közös archívum: előre elvégzett, ellenőrzött kutatások megosztása.

Két rész:
  - index_keszites(mappa): az archívum mappájából index.json-t ír (témánként, nyelvenként:
    fájlnév, SHA-256, dátum, AI, ellenőrzött számok száma). Ezt a fejlesztő futtatja és tölti fel.
  - frissites(forras_url, cel_mappa): letölti az indexet egy közös helyről (pl. a GitHub-tárolóból),
    és csak az új vagy megváltozott fájlokat tölti le. Minden fájlt ellenőriz: a SHA-256 egyezzen
    az indexszel, a tartalom érvényes kutatási eredmény legyen (publikacio, javaslatok, osszefoglalo,
    archivum mezők), és legyen benne legalább egy ellenőrzött szám. Ami nem felel meg, nem kerül be.

A játékba bekötés (mikor és honnan frissít) külön lépés; ez a modul csak a Python-oldalt adja.
Parancsok:
  python -m aether_lab archivum-index <mappa>
  python -m aether_lab archivum-frissites <cel_mappa> [--forras URL]
"""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Callable, Dict, List, Optional

from .biztos_iras import write_text

# A közös archívum alapértelmezett helye (a tároló nyers fájljai). Privát tárolónál ez
# bejelentkezés nélkül nem érhető el: akkor egy nyilvános tükör vagy szerver URL-je kell.
DEFAULT_SOURCE = "https://raw.githubusercontent.com/roadside/aether/claude/aether-m1/AETHER_godot/archivum/"
NAME_RE = re.compile(r"^([a-z0-9_]+)_(hu|en)\.json$")
MAX_FILE_BYTES = 2_000_000


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def valid_result(d: object) -> str:
    """"" ha a tartalom használható archívum-eredmény, különben az ok."""
    if not isinstance(d, dict):
        return "nem JSON-objektum"
    for k in ("publikacio", "javaslatok", "osszefoglalo", "archivum"):
        if k not in d:
            return f"hiányzik: {k}"
    try:
        ok = int(d["osszefoglalo"].get("ellenorizve", 0))
    except Exception:
        return "hibás összefoglaló"
    if ok < 1:
        return "nincs ellenőrzött szám"
    # a javaslatok értéke csak ellenőrzött állításból jöhet: legalább egy ellenőrzött állítás kell
    claims = d["publikacio"].get("allitasok", [])
    if not any(str(c.get("statusz", "")).startswith("ellenorizve") for c in claims):
        return "nincs ellenőrzött állítás"
    return ""


def index_keszites(folder: Path) -> Dict:
    folder = Path(folder)
    items: List[Dict] = []
    for p in sorted(folder.glob("*.json")):
        m = NAME_RE.match(p.name)
        if not m:
            continue
        data = p.read_bytes()
        d = json.loads(data.decode("utf-8"))
        why = valid_result(d)
        if why:
            print(f"{p.name}: kihagyva ({why})")
            continue
        items.append({"fajl": p.name, "tema": m.group(1), "nyelv": m.group(2), "sha256": _sha(data),
                      "meret": len(data), "datum": str(d["archivum"].get("datum", "")),
                      "ai": str(d["archivum"].get("ai", "")),
                      "ellenorizve": int(d["osszefoglalo"].get("ellenorizve", 0))})
    idx = {"verzio": 1, "fajlok": items}
    write_text(folder / "index.json", json.dumps(idx, ensure_ascii=False, indent=1))
    return idx


def frissites(dest: Path, fetch: Callable[[str], bytes], source: str = DEFAULT_SOURCE,
              log=print) -> Dict:
    """Az új vagy megváltozott archívumfájlok letöltése ellenőrzéssel. Visszaad: {uj, frissitett, hibas}."""
    dest = Path(dest)
    dest.mkdir(parents=True, exist_ok=True)
    base = source if source.endswith("/") else source + "/"
    idx = json.loads(fetch(base + "index.json").decode("utf-8"))
    out = {"uj": [], "frissitett": [], "hibas": []}
    for it in idx.get("fajlok", []):
        name = str(it.get("fajl", ""))
        if not NAME_RE.match(name):   # csak egyszerű fájlnév: nincs útvonal, nincs ../
            out["hibas"].append([name, "hibás fájlnév"])
            continue
        local = dest / name
        if local.exists() and _sha(local.read_bytes()) == it.get("sha256"):
            continue
        try:
            data = fetch(base + name)
        except Exception as e:
            out["hibas"].append([name, f"letöltés: {e}"])
            continue
        if len(data) > MAX_FILE_BYTES or _sha(data) != it.get("sha256"):
            out["hibas"].append([name, "az ujjlenyomat nem egyezik"])
            continue
        try:
            why = valid_result(json.loads(data.decode("utf-8")))
        except Exception:
            why = "nem olvasható JSON"
        if why:
            out["hibas"].append([name, why])
            continue
        (out["frissitett"] if local.exists() else out["uj"]).append(name)
        write_text(local, data.decode("utf-8"))
    log(f"Archívum: {len(out['uj'])} új, {len(out['frissitett'])} frissített, {len(out['hibas'])} hibás.")
    return out


# ---------------------------------------------------------------------------
# Kutatáscsere: egy másik játékostól kapott kutatás átvétele ÚJRAELLENŐRZÉSSEL
# ---------------------------------------------------------------------------
def fetch_openalex_paper(old: Dict):
    """A cikk friss példánya az OpenAlexről (azonosító vagy DOI alapján). None, ha nem érhető el.
    Az átvett fájlban lévő absztraktban nem bízunk: bárki átírhatta."""
    import os
    import urllib.parse
    from . import literature as lit
    wid = str(old.get("source_id", ""))
    doi = str(old.get("doi") or "")
    if str(old.get("source", "")) == "openalex" and re.match(r"^https://openalex\.org/W\d+$", wid):
        ref = wid.rsplit("/", 1)[1]
    elif re.match(r"^10\.\d{4,9}/\S+$", doi):
        ref = "doi:" + doi
    else:
        return None
    params = {}
    if os.environ.get("AETHER_MAILTO"):
        params["mailto"] = os.environ["AETHER_MAILTO"]
    if os.environ.get("OPENALEX_API_KEY"):
        params["api_key"] = os.environ["OPENALEX_API_KEY"]
    url = "https://api.openalex.org/works/" + urllib.parse.quote(ref, safe=":/") + (
        "?" + urllib.parse.urlencode(params) if params else "")
    try:
        ps = lit.parse_openalex({"results": [json.loads(lit._get(url))]})
    except Exception:
        return None
    return ps[0] if ps else None


def _clean_name(meta: object) -> str:
    """A megosztó beceneve: csak betű, szám, szóköz, kötőjel; legfeljebb 20 jel (idegen szöveg!)."""
    raw = str(meta.get("nev", "")) if isinstance(meta, dict) else ""
    return "".join(ch for ch in raw if ch.isalnum() or ch in " -")[:20].strip()


def atvetel(path: Path, dest: Path, lang: str = "hu", fetch_paper: Callable = fetch_openalex_paper,
            log=print) -> Dict:
    """Egy megosztott kutatásfájl átvétele. A fájlból CSAK ennyit hiszünk el: melyik témáról szól,
    mely cikkekre hivatkozik, és mit állít róluk (szám + szó szerinti idézet). Minden mást a kód
    újra előállít: a cikkeket frissen letölti, az idézetet a friss absztraktban keresi meg, az
    összesítést és a tervbe tehető javaslatokat újraszámolja. Szabad szöveg (AI-összefoglaló) nem
    jön át. Visszaad: {"ok": bool, "ok_szoveg"/"hiba": str, "fajl": str, "ellenorizve": n, "kiesett": n}."""
    from dataclasses import asdict, fields
    from . import evidence as ev
    from . import godot_bridge as gb
    from . import temak_txt
    path, dest = Path(path), Path(dest)
    en = str(lang).lower().startswith("en")

    def fail(hu: str, en_text: str) -> Dict:
        return {"ok": False, "hiba": en_text if en else hu}

    m = NAME_RE.match(path.name)
    if not m:
        return fail("A fájl neve nem kutatásfájl (téma_hu.json vagy téma_en.json kell).",
                    "The file name is not a research file (topic_hu.json or topic_en.json).")
    topic_id, file_lang = m.group(1), m.group(2)
    topic = next((t for t in temak_txt.load() if t["id"] == topic_id), None)
    if topic is None:
        return fail("Ilyen téma nincs a játékban.", "There is no such topic in the game.")
    try:
        raw = path.read_bytes()
        if len(raw) > MAX_FILE_BYTES:
            raise ValueError("too big")
        d = json.loads(raw.decode("utf-8"))
    except Exception:
        return fail("A fájl nem olvasható.", "The file cannot be read.")
    why = valid_result(d)
    if why:
        return fail("Ez nem ellenőrzött kutatás: " + why, "This is not a verified research file: " + why)
    old_pub = d["publikacio"]
    names = {f.name for f in fields(ev.Claim)}
    claims, papers = [], {}
    for c in old_pub.get("allitasok", []):
        if not isinstance(c, dict) or not str(c.get("statusz", "")).startswith("ellenorizve"):
            continue
        try:
            cl = ev.Claim(**{k: v for k, v in c.items() if k in names})
        except Exception:
            continue
        pid = cl.cikk_azonosito
        if pid not in papers:
            old = old_pub.get("cikkek", {}).get(pid)
            fresh = fetch_paper(old) if isinstance(old, dict) else None
            if fresh is None:
                continue          # a cikk most nem érhető el: az állítás nem jön át
            papers[pid] = fresh
        claims.append(cl)
    sent = len(claims)
    claims = ev.verify(claims, papers) if claims else []
    good = [c for c in claims if c.statusz.startswith("ellenorizve")]
    if not good:
        return fail("Egyik szám sem igazolódott a cikkekből (vagy most nincs internet). Nem vettem át.",
                    "None of the numbers could be confirmed from the papers (or there is no internet). Not imported.")
    question = topic.get("cim_en") if file_lang == "en" and topic.get("cim_en") else topic.get("cim", "")
    used = {c.cikk_azonosito for c in good}
    pub = {"aether_publikacio_verzio": 1, "kerdes": question, "terv": {}, "ai": "atvett",
           "cikkek": {pid: asdict(p) for pid, p in papers.items() if pid in used},
           "ai_nyers_kivonat": {}, "allitasok": [asdict(c) for c in good],
           "osszesitett_parameterek": ev.aggregate(good), "ai_osszegzes": "", "ellentmondasok": "",
           "figyelmeztetes": ""}
    canonical = json.dumps(pub, sort_keys=True, ensure_ascii=False).encode()
    pub["azonosito"] = "AETHER-" + hashlib.sha256(canonical).hexdigest()[:16]
    import datetime as _dt
    today = _dt.date.today().isoformat()
    result = {"publikacio": pub, "javaslatok": gb.javaslatok(pub, file_lang),
              "osszefoglalo": {"cikkek": len(pub["cikkek"]), "allitasok": len(good), "ellenorizve": len(good),
                               "elutasitva": 0, "orszag": "", "hazai": 0},
              "archivum": {"datum": today, "ai": "", "atvett": True, "nev": _clean_name(d["archivum"])}}
    dest.mkdir(parents=True, exist_ok=True)
    out = dest / f"{topic_id}_{file_lang}.json"
    write_text(out, json.dumps(result, ensure_ascii=False, indent=1))
    log(f"Átvétel: {topic_id} {file_lang}: {len(good)}/{sent} szám igazolódott.")
    return {"ok": True, "fajl": str(out), "tema": topic_id, "nyelv": file_lang,
            "ellenorizve": len(good), "kiesett": sent - len(good)}


def add_parsers(sub) -> None:
    a = sub.add_parser("archivum-index", help="index.json az archívum mappájához")
    a.add_argument("mappa")
    a.set_defaults(fn=lambda args: (index_keszites(Path(args.mappa)), 0)[1])
    b = sub.add_parser("archivum-frissites", help="a közös archívum letöltése ellenőrzéssel")
    b.add_argument("cel")
    b.add_argument("--forras", default=DEFAULT_SOURCE)

    def _run(args):
        from .world_state import _http
        frissites(Path(args.cel), lambda u: _http(u, timeout=60), args.forras)
        return 0
    b.set_defaults(fn=_run)
    c = sub.add_parser("archivum-atvetel", help="megosztott kutatásfájl átvétele újraellenőrzéssel")
    c.add_argument("fajl")
    c.add_argument("cel")
    c.add_argument("--nyelv", default="hu")
    c.add_argument("--ki", default="", help="ide írja az eredményt JSON-ként (a játéknak)")

    def _take(args):
        res = atvetel(Path(args.fajl), Path(args.cel), args.nyelv)
        if args.ki:
            write_text(Path(args.ki), json.dumps(res, ensure_ascii=False))
        else:
            print(json.dumps(res, ensure_ascii=False))
        return 0
    c.set_defaults(fn=_take)
