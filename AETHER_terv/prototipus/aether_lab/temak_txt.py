"""A kutatási témák lektorálható szövegfájljai (AETHER_godot/temak/<terület>.txt).

Ez a témák EGYETLEN forrása: a játék (knowledge.gd) és a Python-eszközök is ezt olvassák.
Formátum (UTF-8, Jegyzettömbben szerkeszthető):

    # megjegyzés
    === azonosito ===
    Korszak: I.
    Kérdés: ...
    Röviden: ...
    Mire jó?: ...
    Forrás: Cikk címe (2024) – https://doi.org/...
    Lektorálva: nem
    --- technikai ---
    Keresés: ...

Egy mező egy sor. Ha egy sor nem mezőnévvel kezdődik, az előző mező folytatása.
A terület a fájl neve (pl. fizika.txt). A "Forrás" többször is szerepelhet.
"""
from __future__ import annotations

import re
from pathlib import Path
from typing import Dict, List

ROOT = Path(__file__).resolve().parents[3]
DIR = ROOT / "AETHER_godot" / "temak"

TERULETEK = {
    "fizika": ("Fizika", "Physics"),
    "kemia": ("Kémia", "Chemistry"),
    "anyag": ("Anyagtudomány", "Materials science"),
    "ur": ("Csillagászat és űrkutatás", "Astronomy and space"),
    "fold": ("Földtudomány", "Earth science"),
    "biologia": ("Biológia", "Biology"),
    "energia": ("Energia", "Energy"),
    "mernok": ("Közlekedés és épületek", "Transport and buildings"),
    "mezogazdasag": ("Mezőgazdaság és élelem", "Farming and food"),
    "egeszseg": ("Egészség és alkalmazkodás", "Health and adaptation"),
}
ERA_NAMES = ["Felismerés", "Mérséklés", "Átalakulás", "Helyreállítás"]
ROMAN = ["I", "II", "III", "IV"]

# (kulcs, mezőnév a fájlban). A sorrend a kiírás sorrendje. A knowledge.gd ugyanezt ismeri.
FIELDS = [
    ("korszak", "Korszak"),
    ("cim", "Kérdés"),
    ("magyarazat", "Röviden"),
    ("nyit", "Ad a játékban"),
    ("mire_jo", "Mire jó?"),
    ("hatranyok", "Mi a gond vele?"),
    ("mennyire_bizonyitott", "Mennyire bizonyított?"),
    ("cim_en", "Kérdés angolul"),
    ("magyarazat_en", "Röviden angolul"),
    ("nyit_en", "Ad a játékban angolul"),
    ("mire_jo_en", "Mire jó? angolul"),
    ("hatranyok_en", "Mi a gond vele? angolul"),
    ("mennyire_bizonyitott_en", "Mennyire bizonyított? angolul"),
    ("forras", "Forrás"),
    ("lektoralva", "Lektorálva"),
    ("kereses", "Keresés"),
    ("parameterek", "Paraméter"),
    ("attekintes", "Áttekintő cikkek keresése"),
]
TECH_FROM = "kereses"          # innentől technikai mezők
_LABELS = sorted(FIELDS, key=lambda f: -len(f[1]))   # a hosszabb név előbb ("Kérdés angolul" vs "Kérdés")

HEADER = """# AETHER kutatási témák · {nev}
#
# Lektorálás: a "Kérdés", "Röviden", "Ad a játékban", "Mire jó?", "Mi a gond vele?" és
# "Mennyire bizonyított?" sorokat javítsd. Ha egy témát átnéztél, írd át: "Lektorálva: igen".
# Egy mező egy sor. A hosszú sort nem kell eltörni; ha mégis, a folytatás az előző mezőhöz tartozik.
# A "Forrás" sorok mutatják, honnan jön a magyarázat (több is lehet). Csak tudományos forrás
# (lektorált cikk, IPCC-jelentés, nemzetközi adatgyűjtemény) legyen, Wikipédia ne.
# A "technikai" vonal alatti sorokkal keres a kutatás: csak akkor módosítsd, ha biztos vagy benne.
# Új téma: másolj le egy blokkot, és adj neki új, ékezet nélküli azonosítót (=== uj_tema ===).
# A játék induláskor olvassa ezt a fájlt: mentés után indítsd újra a játékot.
"""


def _era(v: str) -> int:
    t = v.strip().split(" ")[0].strip(".").upper() if v.strip() else ""
    if t in ROMAN:
        return ROMAN.index(t) + 1
    return int(t) if t.isdigit() else 0


def parse(text: str, terulet: str) -> List[Dict]:
    out: List[Dict] = []
    cur, last = None, None
    for raw in text.lstrip("﻿").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^===\s*([A-Za-z0-9_]+)\s*===$", line)
        if m:
            cur = {"id": m.group(1), "terulet": terulet, "forras": []}
            out.append(cur)
            last = None
            continue
        if cur is None or line.startswith("---"):
            continue
        for key, label in _LABELS:
            if line.startswith(label + ":"):
                val = line[len(label) + 1:].strip()
                if key == "forras":
                    if val:
                        cur["forras"].append(val)
                else:
                    cur[key] = val
                last = key
                break
        else:   # folytatósor
            if last == "forras" and cur["forras"]:
                cur["forras"][-1] += " " + line
            elif last is not None:
                cur[last] = (cur.get(last, "") + " " + line).strip()
    for t in out:
        t["korszak"] = _era(str(t.get("korszak", "")))
        for key, _ in FIELDS:
            if key not in ("korszak", "forras"):
                t.setdefault(key, "")
        t["lektoralva"] = t["lektoralva"].strip().lower() in ("igen", "i", "yes", "x")
    return out


def source_link(s: str) -> Dict:
    """ "Cím (2024) – https://..." -> {"cim": "Cím (2024)", "link": "https://..."} """
    m = re.search(r"https?://\S+", s)
    link = m.group(0) if m else ""
    title = s[:m.start()].rstrip(" –-|") if m else s
    return {"cim": title.strip(), "link": link}


def format_topic(t: Dict) -> str:
    lines = [f"=== {t['id']} ==="]
    for key, label in FIELDS:
        if key == TECH_FROM:
            lines.append("--- technikai ---")
        if key == "korszak":
            e = int(t["korszak"])
            lines.append(f"{label}: {ROMAN[e - 1]}. ({ERA_NAMES[e - 1]})")
        elif key == "forras":
            for s in t.get("forras", []) or [""]:
                lines.append(f"{label}: {s}".rstrip())
        elif key == "lektoralva":
            lines.append(f"{label}: {'igen' if t.get('lektoralva') else 'nem'}")
        else:
            lines.append(f"{label}: {t.get(key, '')}".rstrip())
    return "\n".join(lines)


def format_file(terulet: str, topics: List[Dict]) -> str:
    body = []
    for e in range(1, 5):
        ts = [t for t in topics if int(t["korszak"]) == e]
        if not ts:
            continue
        body.append(f"# ----- {ROMAN[e - 1]}. korszak: {ERA_NAMES[e - 1]} -----\n")
        body += [format_topic(t) + "\n" for t in ts]
    return HEADER.format(nev=TERULETEK[terulet][0]) + "\n" + "\n".join(body)


def load(directory: Path = DIR) -> List[Dict]:
    out = []
    for code in TERULETEK:
        p = directory / f"{code}.txt"
        if p.exists():
            out += parse(p.read_text(encoding="utf-8"), code)
    return out


def save(topics: List[Dict], directory: Path = DIR) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    for code in TERULETEK:
        ts = [t for t in topics if t["terulet"] == code]
        (directory / f"{code}.txt").write_text(format_file(code, ts), encoding="utf-8", newline="\r\n")


def save_topic(t: Dict, directory: Path = DIR) -> None:
    """Egy téma frissítése a saját fájljában (a többi téma változatlan marad)."""
    all_ = load(directory)
    all_ = [t if x["id"] == t["id"] else x for x in all_]
    save(all_, directory)
