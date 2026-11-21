"""Híd a Godot-kliens és a Python kutatólabor között.

A Godot külön folyamatként indítja ezeket a parancsokat, és fájlokon keresztül
kommunikál velük (egyszerű, platformfüggetlen, nincs szükség hálózati portra):

  python -m aether_lab godot-ai --ki ai.json
      Mely AI-szolgáltatók érhetők el ezen a gépen (Claude-kulcs, Ollama).

  python -m aether_lab godot-kutat "kérdés" --ai claude --mappa <dir>
      Kutatás. Futás közben a <dir>/allapot.json fájlt folyamatosan frissíti
      (a Godot ezt olvassa a haladásjelzőhöz). A végén <dir>/eredmeny.json
      tartalmazza a publikációt + a játékba beépíthető "javaslatokat".

  python -m aether_lab godot-modell be.json --ki ki.json
      A forgatókönyv lefuttatása mindhárom érzékenységgel, teljes idősorral,
      az alapesettel összevetve.

Alapelv: a javaslatokat (mi kerülhet a modellbe) determinisztikus kód állítja
elő, kizárólag ELLENŐRZÖTT állításokból. A játékos hagyja jóvá őket.
"""
from __future__ import annotations

import json
import os
import time
import traceback
import urllib.request
from dataclasses import fields
from pathlib import Path
from typing import Dict, List, Optional

from . import climate as cl

# ---------------------------------------------------------------------------
# Hétköznapi nyelvű magyarázatok (alacsony tanulási görbe)
# ---------------------------------------------------------------------------
BIZONYOSSAG_SZOVEG = {
    "magas": "Erős bizonyíték: több forrás, köztük összefoglaló (meta-)elemzés.",
    "közepes": "Közepes bizonyíték: legalább két forrás vagy egy összefoglaló elemzés.",
    "alacsony": "Gyenge bizonyíték: csak egy forrás. Érdemes tovább kutatni.",
}

PARAM_NEV = {
    "cdr_potencial_gtco2_ev": "Mennyi CO2-t vonhat ki a levegőből évente",
    "cdr_koltseg_usd_tco2": "Mennyibe kerül egy tonna CO2 kivonása",
    "metan_csokkentes_pct": "Mennyivel csökkenthető a metánkibocsátás",
    "hozam_valtozas_pct_per_c": "Hogyan változik a termés 1 fok melegedéstől",
    "alkalmazkodas_hozam_elony_pct": "Mennyivel több termést ad aszályban",
    "viztakarekossag_pct": "Mennyi vizet takarít meg",
    "sai_kenyszer_w_m2_per_tg": "Mennyire hűt a légkörbe juttatott kén",
    "aeroszol_erf_w_m2": "Mennyire hűt vagy melegít a légszennyezés",
    "tcre_c_per_1000gtco2": "Mennyit melegít 1000 milliárd tonna CO2",
}


def hu(x: float, nd: Optional[int] = None) -> str:
    """Szám magyar tizedesvesszővel."""
    return (f"{x:.{nd}f}" if nd is not None else f"{x:g}").replace(".", ",")


def jelentes(param: str, ertek: float, egyseg: str) -> str:
    """Egy mondat arról, mit jelent a szám, szakszavak nélkül."""
    v = hu(ertek)
    if param == "cdr_potencial_gtco2_ev":
        pct = ertek / cl.E_CO2_NOW * 100
        return f"Évente kb. {v} milliárd tonna CO2-t vonhatna ki. Ez a mai világkibocsátás kb. {pct:.0f}%-a."
    if param == "cdr_koltseg_usd_tco2":
        return f"Egy tonna CO2 kivonása kb. {v} dollárba kerülne."
    if param == "metan_csokkentes_pct":
        return f"Az adott területen a metánkibocsátás kb. {v}%-kal csökkenthető."
    if param == "alkalmazkodas_hozam_elony_pct":
        return f"Aszályos években kb. {v}%-kal több termés. Ez nem hűti a Földet, de védi az élelmet."
    if param == "hozam_valtozas_pct_per_c":
        return f"Minden további fok melegedés kb. {v}%-kal változtatja a termést."
    if param == "viztakarekossag_pct":
        return f"Kb. {v}%-kal kevesebb víz kell ugyanahhoz."
    return f"A cikkek szerint az érték kb. {v} {egyseg}."


# ---------------------------------------------------------------------------
# Ellenőrzött eredményekből a modellbe beépíthető javaslatok
# ---------------------------------------------------------------------------
CDR_KULCSSZAVAK = [
    ("bioszen", ["biochar", "bioszén", "bioszen"]),
    ("kozetmallasztas", ["weathering", "mállasztás", "mallasztas", "basalt", "bazalt", "olivine"]),
    ("erdosites", ["afforest", "reforest", "forest", "erdő", "erdo", "tree"]),
    ("daccs", ["direct air", "dac", "levegőből"]),
    ("beccs", ["beccs", "bioenergy"]),
    ("talajszen", ["soil", "talaj"]),
]

CDR_NEV = {"bioszen": "Bioszén", "kozetmallasztas": "Kőzetmállasztás", "erdosites": "Erdősítés",
           "daccs": "Közvetlen levegős kivonás", "beccs": "Bioenergia + szén-tárolás", "talajszen": "Talajszén"}


def _cdr_method(text: str) -> Optional[str]:
    t = text.lower()
    for method, keys in CDR_KULCSSZAVAK:
        if any(k in t for k in keys):
            return method
    return None


def javaslatok(pub: Dict) -> List[Dict]:
    """A publikáció összesített (csak ellenőrzött) paramétereiből a modell
    "karjai" (lever), amelyeket a játékos jóváhagyhat."""
    out = []
    question = pub.get("kerdes", "")
    for key, a in pub.get("osszesitett_parameterek", {}).items():
        p, med = a["parameter"], a["sulyozott_median"]
        base = {"kulcs": key, "parameter": p, "alkategoria": a["alkategoria"], "ertek": med,
                "egyseg": a["egyseg"], "tartomany": a["tartomany"], "bizonyossag": a["bizonyossag"],
                "bizonyossag_szoveg": BIZONYOSSAG_SZOVEG.get(a["bizonyossag"], ""),
                "forrasok_szama": a["forrasok_szama"], "nev": PARAM_NEV.get(p, p),
                "jelentes": jelentes(p, med, a["egyseg"]), "publikacio": pub.get("azonosito", ""),
                "kar": None, "kar_ertek": None, "kar_nev": "", "megjegyzes": ""}
        if p == "cdr_potencial_gtco2_ev":
            m = _cdr_method(a["alkategoria"]) or _cdr_method(question)
            if m:
                hi = cl.CDR_LIMITS[m][1]
                base.update(kar=f"cdr:{m}", kar_ertek=round(min(med, hi), 3), kar_nev=CDR_NEV[m])
                if med > hi:
                    base["megjegyzes"] = (f"A cikkek értéke ({med:g}) nagyobb a fenntartható felső határnál "
                                          f"({hi:g}, Fuss et al. 2018), ezért a játék {hi:g}-t használ.")
        elif p == "alkalmazkodas_hozam_elony_pct":
            base.update(kar="alkalmazkodas", kar_ertek=round(min(max(med, 0.0), 100.0), 2),
                        kar_nev="Alkalmazkodás (aszálytűrő fajták)",
                        megjegyzes="Közelítés: az aszály alatti hozamelőnyt a melegedés okozta "
                                   "hozamveszteség ellensúlyozásaként használjuk.")
        if base["kar"] is None:
            base["megjegyzes"] = base["megjegyzes"] or "Tájékoztató adat: ebben a változatban még nem kerül a modellbe."
        out.append(base)
    return out


# ---------------------------------------------------------------------------
# Segédek
# ---------------------------------------------------------------------------
def _write_json(path: Path, data) -> None:
    """Atomikus írás, hogy a Godot sose olvasson félkész fájlt."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    os.replace(tmp, path)


class StatusLog:
    """A kutatás naplóját az allapot.json fájlba írja."""

    LEPESEK = ["Kérdés pontosítása", "Cikkek keresése", "Állítások kiemelése", "Ellenőrzés"]

    def __init__(self, path: Path):
        self.path = path
        self.lines: List[str] = []
        self.step = 0
        self._write("fut")

    def _write(self, state: str, **extra):
        _write_json(self.path, {"allapot": state, "lepes": self.step, "lepesek": self.LEPESEK,
                                "naplo": self.lines[-40:], "ido": time.time(), **extra})

    def __call__(self, msg: str):
        print(msg, flush=True)
        s = msg.strip()
        if len(s) > 3 and s[0].isdigit() and s[1:3] == "/4":
            self.step = int(s[0])
        self.lines.append(s)
        self._write("fut")

    def done(self, **extra):
        self._write("kesz", **extra)

    def error(self, msg: str):
        self.lines.append(msg)
        self._write("hiba", uzenet=msg)


# ---------------------------------------------------------------------------
# Parancsok
# ---------------------------------------------------------------------------
def ai_status(ollama_host: Optional[str] = None, timeout: float = 1.5) -> Dict:
    res = {"claude": {"elerheto": False, "ok": ""}, "ollama": {"elerheto": False, "ok": "", "modellek": []},
           "none": {"elerheto": True, "ok": "Mindig működik: csak cikkeket keres, AI nélkül."}}
    try:
        import anthropic  # noqa: F401
        if os.environ.get("ANTHROPIC_API_KEY"):
            res["claude"] = {"elerheto": True, "ok": "API-kulcs megtalálva."}
        else:
            res["claude"]["ok"] = "Nincs API-kulcs. Add meg a játékban, vagy állítsd be az ANTHROPIC_API_KEY változót."
    except ImportError:
        res["claude"]["ok"] = "Hiányzik az anthropic csomag: pip install anthropic"
    host = (ollama_host or os.environ.get("OLLAMA_HOST", "http://localhost:11434")).rstrip("/")
    try:
        with urllib.request.urlopen(host + "/api/tags", timeout=timeout) as r:
            models = [m.get("name", "") for m in json.loads(r.read()).get("models", [])]
        res["ollama"] = {"elerheto": bool(models), "modellek": models,
                         "ok": "Fut, letöltött modellek: " + ", ".join(models) if models
                         else "Fut, de nincs letöltött modell (pl. ollama pull qwen3:14b)."}
    except Exception:
        res["ollama"]["ok"] = "Nem fut a gépen (https://ollama.com)."
    return res


def cmd_ai(args):
    _write_json(Path(args.ki), ai_status())


def cmd_kutat(args, run_research=None, get_provider=None):
    from .llm import LLMError
    if run_research is None:
        from .research import run_research
    if get_provider is None:
        from .llm import get_provider
    folder = Path(args.mappa)
    folder.mkdir(parents=True, exist_ok=True)
    log = StatusLog(folder / "allapot.json")
    try:
        provider = get_provider(args.ai)
        # AI nélkül nincs kérdéspontosítás, ezért az angol keresőkifejezést használjuk
        question = args.kerdes if provider is not None else (getattr(args, "kereses", "") or args.kerdes)
        pub = run_research(question, provider, n_papers=args.cikkek, per_source=args.forrasonkent,
                           mailto=os.environ.get("AETHER_MAILTO", ""),
                           openalex_key=os.environ.get("OPENALEX_API_KEY", ""),
                           s2_key=os.environ.get("S2_API_KEY", ""), log=log)
        claims = pub["allitasok"]
        ok = sum(c["statusz"].startswith("ellenorizve") for c in claims)
        result = {"publikacio": pub, "javaslatok": javaslatok(pub),
                  "osszefoglalo": {"cikkek": len(pub["cikkek"]), "allitasok": len(claims),
                                   "ellenorizve": ok, "elutasitva": len(claims) - ok}}
        _write_json(folder / "eredmeny.json", result)
        log.done(eredmeny=str(folder / "eredmeny.json"))
    except LLMError as e:
        log.error(f"AI-hiba: {e}")
    except Exception as e:  # a Godot felé mindig érthető állapotot adunk
        traceback.print_exc()
        log.error(f"Váratlan hiba: {e}")


def _scenario_from(data: Dict) -> cl.Scenario:
    allowed = {f.name for f in fields(cl.Scenario)}
    unknown = set(data) - allowed
    if unknown:
        raise ValueError(f"Ismeretlen mezők: {sorted(unknown)}")
    return cl.Scenario(**data)


def model_series(data: Dict) -> Dict:
    s = _scenario_from(data)
    base = cl.Scenario(nev="Alapeset")
    out = {"nev": s.nev, "evek": list(range(cl.START_YEAR, cl.END_YEAR + 1)), "terv": {}, "alapeset": {},
           "osszegzes": cl.summarize(s)["eredmenyek"], "alapeset_osszegzes": cl.summarize(base)["eredmenyek"]}
    for e in cl.ENSEMBLE:
        r = cl.run(s, e)
        b = cl.run(base, e)
        out["terv"][e] = {"homerseklet": r.temp, "kukorica_pct": r.crop_change_pct["kukorica"], "netto_co2": r.co2_net}
        out["alapeset"][e] = {"homerseklet": b.temp}
    k, kb = out["osszegzes"]["kozep"], out["alapeset_osszegzes"]["kozep"]
    diff = kb["T2100"] - k["T2100"]
    lo, hi = out["osszegzes"]["alacsony"]["T2100"], out["osszegzes"]["magas"]["T2100"]
    txt = (f"2100-ban a Föld kb. {hu(k['T2100'], 1)} °C-kal melegebb, mint az ipari forradalom előtt "
           f"(bizonytalansági sáv: {hu(lo, 1)}–{hu(hi, 1)} °C). ")
    if diff >= 0.05:
        txt += f"Ez {hu(diff, 1)} °C-kal kevesebb, mint ha semmi sem változna."
    elif diff <= -0.05:
        txt += f"Ez {hu(-diff, 1)} °C-kal TÖBB, mint ha semmi sem változna."
    else:
        txt += "Ez gyakorlatilag ugyanannyi, mint ha semmi sem változna."
    out["jelentes"] = txt
    return out


def cmd_modell(args):
    try:
        data = json.loads(Path(args.be).read_text(encoding="utf-8"))
        _write_json(Path(args.ki), model_series(data))
    except Exception as e:
        _write_json(Path(args.ki), {"hiba": str(e)})
        raise SystemExit(1)


def add_parsers(sub):
    a = sub.add_parser("godot-ai"); a.add_argument("--ki", required=True); a.set_defaults(fn=cmd_ai)
    k = sub.add_parser("godot-kutat")
    k.add_argument("kerdes")
    k.add_argument("--ai", default="none", choices=["claude", "ollama", "none"])
    k.add_argument("--mappa", required=True)
    k.add_argument("--kereses", default="", help="angol keresőkifejezés AI nélküli módhoz")
    k.add_argument("--cikkek", type=int, default=12)
    k.add_argument("--forrasonkent", type=int, default=6)
    k.set_defaults(fn=cmd_kutat)
    m = sub.add_parser("godot-modell"); m.add_argument("be"); m.add_argument("--ki", required=True)
    m.set_defaults(fn=cmd_modell)
