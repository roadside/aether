"""AETHER archívum: előre elvégzett, ellenőrzött kutatások készítése.

Valódi kutatást futtat a helyi Ollamával, PONTOSAN azzal a paranccsal és paraméterekkel,
amellyel a játék kutat (aether_lab godot-kutat). Ha az eredményben van legalább egy
ELLENŐRZÖTT szám, és a szövegben nincs ismert félrefordítás, elmenti ide:
    AETHER_godot/archivum/<témaazonosító>_<hu|en>.json
egy "archivum": {"datum": "ÉÉÉÉ-HH-NN", "ai": "ollama <modell>"} mezővel kiegészítve.

Kézzel semmit nem ír és nem javít a számokban: a fájl a kutatás eredménye, változtatás nélkül.
A félrefordítást a fordító kódban kell javítani (aether_lab/evidence.py), nem itt.

Használat (a GPU-t foglalja, ezért csak akkor, amikor senki sem játszik):
    py tools/archivum_keszites.py                 # a tervbe tehető témák, magyarul és angolul
    py tools/archivum_keszites.py kukorica        # csak egy téma
    py tools/archivum_keszites.py kukorica --nyelv hu --modell qwen3:8b --probak 3
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
GODOT = HERE.parent
LAB = GODOT.parent / "AETHER_terv" / "prototipus"
ARCHIVE = GODOT / "archivum"
sys.path.insert(0, str(LAB))
from aether_lab import temak_txt  # noqa: E402

# Ismert félrefordítások: ha ezek a szavak (szóhatárral) előfordulnak a megjelenő szövegben,
# az eredményt NEM mentjük. Új esetnél a fordító kódot is javítani kell.
BAD_WORDS = ["asztal"]


def plan_topics():
    """A témák, amelyeknél a „Ha kikutatod” sor valódi tervlehetőséget nyit (… a tervedben)."""
    return [t for t in temak_txt.load() if "tervedben" in (t.get("nyit") or "")]


def shown_texts(res: dict, lang: str) -> list:
    pub = res.get("publikacio", {})
    out = [pub.get("ai_osszegzes", ""), pub.get("ellentmondasok", "")]
    for j in res.get("javaslatok", []):
        out += [j.get("alkategoria_nev", ""), j.get("nev", ""), j.get("jelentes", "")]
    return [str(x) for x in out if x]


def bad_translation(res: dict, lang: str) -> str:
    import re
    for txt in shown_texts(res, lang):
        for w in BAD_WORDS:
            if re.search(rf"(?<![\w]){w}", txt, flags=re.I):
                return f"„{w}” a szövegben: {txt[:80]}"
    return ""


def run_one(topic: dict, lang: str, model: str) -> dict:
    question = topic.get("cim_en") if lang == "en" and topic.get("cim_en") else topic["cim"]
    with tempfile.TemporaryDirectory() as d:
        env = dict(os.environ, AETHER_OLLAMA_MODEL=model) if model else dict(os.environ)
        cmd = [sys.executable, "-m", "aether_lab", "godot-kutat", question, "--ai", "ollama", "--mappa", d,
               "--nyelv", lang, "--kereses", topic.get("kereses", ""), "--parameterek", topic.get("parameterek", ""),
               "--orszag", "HU", "--cikkek", "12"]
        subprocess.run(cmd, cwd=str(LAB), env=env, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        st = json.loads(Path(d, "allapot.json").read_text(encoding="utf-8")) if Path(d, "allapot.json").exists() else {}
        res_p = Path(d, "eredmeny.json")
        if st.get("allapot") != "kesz" or not res_p.exists():
            return {"_hiba": str(st.get("uzenet") or st.get("hiba") or "nincs eredmény")}
        return json.loads(res_p.read_text(encoding="utf-8"))


def model_name(model: str) -> str:
    if model:
        return model
    try:
        sys.path.insert(0, str(LAB))
        from aether_lab.llm import get_provider
        return get_provider("ollama").model
    except Exception:
        return "ismeretlen"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("temak", nargs="*", help="témaazonosítók (alapból a tervbe tehető témák)")
    ap.add_argument("--nyelv", choices=["hu", "en", "mindketto"], default="mindketto")
    ap.add_argument("--modell", default="", help="Ollama-modell (pl. qwen3:8b); alapból a játéké")
    ap.add_argument("--probak", type=int, default=2, help="ennyiszer próbálja, ha nincs ellenőrzött szám")
    ap.add_argument("--felulir", action="store_true", help="a meglévő archívumfájlt is újra elkészíti")
    a = ap.parse_args()
    topics = plan_topics()
    if a.temak:
        allt = {t["id"]: t for t in temak_txt.load()}
        topics = [allt[i] for i in a.temak if i in allt]
    # a kukorica elsőnek: az 1. küldetés ezen múlik
    topics.sort(key=lambda t: 0 if t["id"] == "kukorica" else 1)
    langs = ["hu", "en"] if a.nyelv == "mindketto" else [a.nyelv]
    ARCHIVE.mkdir(exist_ok=True)
    ai = "ollama " + model_name(a.modell)
    for t in topics:
        for lang in langs:
            out = ARCHIVE / f"{t['id']}_{lang}.json"
            if out.exists() and not a.felulir:
                print(f"{out.name}: már megvan, kihagyva")
                continue
            for n in range(1, a.probak + 1):
                res = run_one(t, lang, a.modell)
                if "_hiba" in res:
                    print(f"{out.name} ({n}. próba): hiba: {res['_hiba'][:120]}")
                    continue
                ok = int(res.get("osszefoglalo", {}).get("ellenorizve", 0))
                bad = bad_translation(res, lang)
                if ok < 1:
                    print(f"{out.name} ({n}. próba): nincs ellenőrzött szám")
                    continue
                if bad:
                    print(f"{out.name} ({n}. próba): rossz fordítás, nem mentem ({bad})")
                    continue
                res["archivum"] = {"datum": dt.date.today().isoformat(), "ai": ai}
                out.write_text(json.dumps(res, ensure_ascii=False, indent=1), encoding="utf-8")
                print(f"{out.name}: mentve ({ok} ellenőrzött szám)")
                break


if __name__ == "__main__":
    main()
