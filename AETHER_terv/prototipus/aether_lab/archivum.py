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
