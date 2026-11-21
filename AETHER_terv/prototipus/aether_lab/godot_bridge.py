"""Híd a Godot-kliens és a Python kutatólabor között.

A Godot külön folyamatként indítja ezeket a parancsokat, és fájlokon keresztül
kommunikál velük (egyszerű, platformfüggetlen, nincs szükség hálózati portra):

  python -m aether_lab godot-ai --ki ai.json
      Mely AI-szolgáltatók érhetők el ezen a gépen (Claude, OpenAI, Gemini kulcs; Ollama).

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
import re
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
    "közepes": "Közepes bizonyíték: legalább két forrás.",
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


BIZONYOSSAG_SZOVEG_EN = {
    "magas": "Strong evidence: several sources, including a review (meta-)analysis.",
    "közepes": "Medium evidence: at least two sources.",
    "alacsony": "Weak evidence: only one source. Worth researching further.",
}

PARAM_NEV_EN = {
    "cdr_potencial_gtco2_ev": "How much CO2 it could remove from the air each year",
    "cdr_koltseg_usd_tco2": "What removing one tonne of CO2 costs",
    "metan_csokkentes_pct": "How much methane emissions can be cut",
    "hozam_valtozas_pct_per_c": "How harvests change with 1 degree of warming",
    "alkalmazkodas_hozam_elony_pct": "How much more harvest it gives in a drought",
    "viztakarekossag_pct": "How much water it saves",
    "sai_kenyszer_w_m2_per_tg": "How much sulphur put into the atmosphere cools",
    "aeroszol_erf_w_m2": "How much air pollution cools or warms",
    "tcre_c_per_1000gtco2": "How much 1000 billion tonnes of CO2 warms",
}

# Mértékegységek angolul (a belső kód magyar marad)
EGYSEG_EN = {"GtCO2/év": "GtCO2/yr", "W/m²/(Tg SO2/év)": "W/m²/(Tg SO2/yr)"}


def is_en(lang: str) -> bool:
    return (lang or "hu").lower().startswith("en")


def hu(x: float, nd: Optional[int] = None, lang: str = "hu") -> str:
    """Szám a nyelv tizedesjelével (magyarul vessző, angolul pont)."""
    s = f"{x:.{nd}f}" if nd is not None else f"{x:g}"
    return s if is_en(lang) else s.replace(".", ",")


def jelentes(param: str, ertek: float, egyseg: str, lang: str = "hu") -> str:
    """Egy mondat arról, mit jelent a szám, szakszavak nélkül."""
    if is_en(lang):
        return _jelentes_en(param, ertek, egyseg)
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


def _jelentes_en(param: str, ertek: float, egyseg: str) -> str:
    v = f"{ertek:g}"
    if param == "cdr_potencial_gtco2_ev":
        pct = ertek / cl.E_CO2_NOW * 100
        return f"It could remove about {v} billion tonnes of CO2 a year. That is about {pct:.0f}% of today's global emissions."
    if param == "cdr_koltseg_usd_tco2":
        return f"Removing one tonne of CO2 would cost about {v} dollars."
    if param == "metan_csokkentes_pct":
        return f"Methane emissions in this area can be cut by about {v}%."
    if param == "alkalmazkodas_hozam_elony_pct":
        return f"About {v}% more harvest in drought years. It does not cool the Earth, but it protects food."
    if param == "hozam_valtozas_pct_per_c":
        return f"Every extra degree of warming changes harvests by about {v}%."
    if param == "viztakarekossag_pct":
        return f"About {v}% less water is needed for the same result."
    return f"According to the papers, the value is about {v} {EGYSEG_EN.get(egyseg, egyseg)}."


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
CDR_NEV_EN = {"bioszen": "Biochar", "kozetmallasztas": "Enhanced rock weathering", "erdosites": "Afforestation",
              "daccs": "Direct air capture", "beccs": "Bioenergy + carbon storage", "talajszen": "Soil carbon"}


def _cdr_method(text: str) -> Optional[str]:
    t = text.lower()
    for method, keys in CDR_KULCSSZAVAK:
        if any(k in t for k in keys):
            return method
    return None


def javaslatok(pub: Dict, lang: str = "hu") -> List[Dict]:
    """A publikáció összesített (csak ellenőrzött) paramétereiből a modell
    "karjai" (lever), amelyeket a játékos jóváhagyhat. A kódok (kar, parameter,
    bizonyossag) nyelvfüggetlenek, csak a megjelenített szövegek fordítottak."""
    en = is_en(lang)
    out = []
    question = pub.get("kerdes", "")
    for key, a in pub.get("osszesitett_parameterek", {}).items():
        p, med = a["parameter"], a["sulyozott_median"]
        base = {"kulcs": key, "parameter": p, "alkategoria": a["alkategoria"], "ertek": med,
                "egyseg": EGYSEG_EN.get(a["egyseg"], a["egyseg"]) if en else a["egyseg"], "tartomany": a["tartomany"], "bizonyossag": a["bizonyossag"],
                "bizonyossag_szoveg": (BIZONYOSSAG_SZOVEG_EN if en else BIZONYOSSAG_SZOVEG).get(a["bizonyossag"], ""),
                "forrasok_szama": a["forrasok_szama"], "nev": (PARAM_NEV_EN if en else PARAM_NEV).get(p, p),
                "jelentes": jelentes(p, med, a["egyseg"], lang), "publikacio": pub.get("azonosito", ""),
                "kar": None, "kar_ertek": None, "kar_nev": "", "megjegyzes": ""}
        if p == "cdr_potencial_gtco2_ev":
            m = _cdr_method(a["alkategoria"]) or _cdr_method(question)
            if m:
                hi = cl.CDR_LIMITS[m][1]
                base.update(kar=f"cdr:{m}", kar_ertek=round(min(med, hi), 3), kar_nev=(CDR_NEV_EN if en else CDR_NEV)[m])
                if med > hi and en:
                    base["megjegyzes"] = (f"The papers' value ({med:g}) is above the sustainable upper limit "
                                          f"({hi:g}, Fuss et al. 2018), so the game uses {hi:g}.")
                elif med > hi:
                    base["megjegyzes"] = (f"A cikkek értéke ({med:g}) nagyobb a fenntartható felső határnál "
                                          f"({hi:g}, Fuss et al. 2018), ezért a játék {hi:g}-t használ.")
        elif p == "alkalmazkodas_hozam_elony_pct":
            base.update(kar="alkalmazkodas", kar_ertek=round(min(max(med, 0.0), 100.0), 2),
                        kar_nev="Adaptation (drought-tolerant varieties)" if en
                        else "Alkalmazkodás (aszálytűrő fajták)",
                        megjegyzes="Approximation: the yield advantage in drought is used to offset "
                                   "the yield loss caused by warming." if en else
                                   "Közelítés: az aszály alatti hozamelőnyt a melegedés okozta "
                                   "hozamveszteség ellensúlyozásaként használjuk.")
        if base["kar"] is None:
            base["megjegyzes"] = base["megjegyzes"] or (
                "For information: this version does not put it into the model yet." if en
                else "Tájékoztató adat: ebben a változatban még nem kerül a modellbe.")
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
    LEPESEK_EN = ["Refining the question", "Searching for papers", "Picking out claims", "Checking"]

    def __init__(self, path: Path, lang: str = "hu"):
        self.path = path
        self.en = is_en(lang)
        self.lines: List[str] = []
        self.step = 0
        self.rovid = ""
        self._write("fut")

    def _write(self, state: str, **extra):
        _write_json(self.path, {"allapot": state, "lepes": self.step, "lepesek": self.LEPESEK_EN if self.en else self.LEPESEK,
                                "naplo": self.lines[-40:], "rovid": self.rovid, "ido": time.time(), **extra})

    def __call__(self, msg: str):
        print(msg, flush=True)
        s = msg.strip()
        if self.en:  # az irodalomkereső naplósorai magyarok
            s = s.replace(" találat", " results").replace("HIBA", "ERROR").replace("– kihagyva", "– skipped")
        if len(s) > 3 and s[0].isdigit() and s[1:3] == "/4":
            self.step = int(s[0])
        self.lines.append(s)
        short = self._short(s)
        if short:
            self.rovid = short
        self._write("fut")

    def _short(self, s: str) -> str:
        """A játékosnak szóló egyetlen rövid sor (a technikai napló a Részletek mögött van)."""
        m = re.match(r"(\d+) (?:egyedi|unique).*?(?:legjobb|best) (\d+)", s)
        if m:
            return (f"{m.group(1)} papers found, the AI reads the best {m.group(2)}." if self.en else
                    f"{m.group(1)} cikket találtunk. Az AI most a {m.group(2)} legjobbat olvassa.")
        m = re.match(r"(\d+)/(\d+) (?:cikkben van|papers contain)", s)
        if m:
            return (f"{m.group(1)} of {m.group(2)} papers contain a usable number. The AI is reading them." if self.en
                    else f"{m.group(2)} cikkből {m.group(1)} tartalmaz használható számot. Az AI most ezeket olvassa.")
        m = re.match(r"(\d+)/(\d+) (?:állítás|claims)", s)
        if m:
            return (f"{m.group(1)} of {m.group(2)} numbers passed the check." if self.en else
                    f"{m.group(2)} számból {m.group(1)} ment át az ellenőrzésen.")
        return ""

    def done(self, **extra):
        self._write("kesz", **extra)

    def error(self, msg: str):
        self.lines.append(msg)
        self._write("hiba", uzenet=msg)


# ---------------------------------------------------------------------------
# Parancsok
# ---------------------------------------------------------------------------
def ai_status(ollama_host: Optional[str] = None, timeout: float = 1.5, lang: str = "hu") -> Dict:
    en = is_en(lang)
    res = {"claude": {"elerheto": False, "ok": ""}, "ollama": {"elerheto": False, "ok": "", "modellek": []},
           "none": {"elerheto": True, "ok": "Always works: only searches for papers, without AI." if en
                    else "Mindig működik: csak cikkeket keres, AI nélkül."}}
    try:
        import anthropic  # noqa: F401
        if os.environ.get("ANTHROPIC_API_KEY"):
            res["claude"] = {"elerheto": True, "ok": "API key found." if en else "API-kulcs megtalálva."}
        else:
            res["claude"]["ok"] = ("No API key yet. A Claude Pro subscription is not enough: you need an API key "
                                   "(console.anthropic.com)." if en else
                                   "Még nincs API-kulcs. A Claude Pro előfizetés nem elég: API-kulcs kell "
                                   "(console.anthropic.com).")
    except ImportError:
        res["claude"]["ok"] = ("The anthropic package is missing: pip install anthropic" if en
                               else "Hiányzik az anthropic csomag: pip install anthropic")
    # OpenAI (ChatGPT) és Gemini: csak a kulcs meglétét nézzük (nem küldünk kérést)
    plus = (" A ChatGPT Plus előfizetés nem elég: API-kulcs kell (platform.openai.com)." if not en else
            " A ChatGPT Plus subscription is not enough: you need an API key (platform.openai.com).")
    if os.environ.get("OPENAI_API_KEY"):
        res["openai"] = {"elerheto": True, "ok": "API key found." if en else "API-kulcs megtalálva."}
    else:
        res["openai"] = {"elerheto": False, "ok": ("No API key yet." if en else "Még nincs API-kulcs.") + plus}
    if os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY"):
        res["gemini"] = {"elerheto": True, "ok": "API key found." if en else "API-kulcs megtalálva."}
    else:
        res["gemini"] = {"elerheto": False, "ok": "No API key yet. Google AI Studio gives one for free (with limits)."
                         if en else "Még nincs API-kulcs. A Google AI Studio ingyen ad egyet (korlátozott kerettel)."}
    host = (ollama_host or os.environ.get("OLLAMA_HOST", "http://localhost:11434")).rstrip("/")
    try:
        with urllib.request.urlopen(host + "/api/tags", timeout=timeout) as r:
            models = [m.get("name", "") for m in json.loads(r.read()).get("models", [])]
        if en:
            msg = ("Running, downloaded models: " + ", ".join(models) if models
                   else "Running, but no model downloaded (e.g. ollama pull qwen3:8b).")
        else:
            msg = ("Fut, letöltött modellek: " + ", ".join(models) if models
                   else "Fut, de nincs letöltött modell (pl. ollama pull qwen3:8b).")
        res["ollama"] = {"elerheto": bool(models), "modellek": models, "ok": msg}
    except Exception:
        res["ollama"]["ok"] = ("Not running on this computer (https://ollama.com)." if en
                               else "Nem fut a gépen (https://ollama.com).")
    return res


def cmd_ai(args):
    lang = getattr(args, "nyelv", "hu")
    st = ai_status(lang=lang)
    try:
        from .hardware import detect
        st["gep"] = detect(lang)     # videókártyák + ajánlott helyi modell
    except Exception as e:
        st["gep"] = {"hiba": str(e)}
    _write_json(Path(args.ki), st)


def cmd_kutat(args, run_research=None, get_provider=None):
    from .llm import LLMError
    if run_research is None:
        from .research import run_research
    if get_provider is None:
        from .llm import get_provider
    folder = Path(args.mappa)
    folder.mkdir(parents=True, exist_ok=True)
    lang = getattr(args, "nyelv", "hu")
    en = is_en(lang)
    log = StatusLog(folder / "allapot.json", lang)
    try:
        provider = get_provider(args.ai)
        # Előre összeállított kérdésnél a játék adja a keresőkifejezéseket ("|" választja el)
        # és a paramétereket; AI nélkül csak a keresőkifejezések számítanak.
        queries = [q.strip() for q in (getattr(args, "kereses", "") or "").split("|") if q.strip()]
        params = [p.strip() for p in (getattr(args, "parameterek", "") or "").split(",") if p.strip()]
        question = args.kerdes if provider is not None else (" ".join(queries[:1]) or args.kerdes)
        pub = run_research(question, provider, n_papers=args.cikkek, per_source=args.forrasonkent,
                           queries=queries or ([question] if provider is None else None),
                           params=params or ([] if provider is None else None),
                           mailto=os.environ.get("AETHER_MAILTO", ""),
                           openalex_key=os.environ.get("OPENALEX_API_KEY", ""),
                           s2_key=os.environ.get("S2_API_KEY", ""), log=log, lang=lang)
        claims = pub["allitasok"]
        ok = sum(c["statusz"].startswith("ellenorizve") for c in claims)
        result = {"publikacio": pub, "javaslatok": javaslatok(pub, lang),
                  "osszefoglalo": {"cikkek": len(pub["cikkek"]), "allitasok": len(claims),
                                   "ellenorizve": ok, "elutasitva": len(claims) - ok}}
        _write_json(folder / "eredmeny.json", result)
        log.done(eredmeny=str(folder / "eredmeny.json"))
    except LLMError as e:
        log.error(f"AI error: {e}" if en else f"AI-hiba: {e}")
    except Exception as e:  # a Godot felé mindig érthető állapotot adunk
        traceback.print_exc()
        log.error(f"Unexpected error: {e}" if en else f"Váratlan hiba: {e}")


def _scenario_from(data: Dict) -> cl.Scenario:
    allowed = {f.name for f in fields(cl.Scenario)}
    unknown = set(data) - allowed
    if unknown:
        raise ValueError(f"Ismeretlen mezők: {sorted(unknown)}")
    return cl.Scenario(**data)


def model_series(data: Dict, lang: str = "hu") -> Dict:
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
    if is_en(lang):
        f = lambda x: f"{x:.1f}"  # noqa: E731
        txt = (f"In 2100 the Earth is about {f(k['T2100'])} °C warmer than before the industrial revolution "
               f"(uncertainty range: {f(lo)}–{f(hi)} °C). ")
        if diff >= 0.05:
            txt += f"That is {f(diff)} °C less than if nothing changed."
        elif diff <= -0.05:
            txt += f"That is {f(-diff)} °C MORE than if nothing changed."
        else:
            txt += "That is practically the same as if nothing changed."
        out["jelentes"] = txt
        return out
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
        _write_json(Path(args.ki), model_series(data, getattr(args, "nyelv", "hu")))
    except Exception as e:
        _write_json(Path(args.ki), {"hiba": str(e)})
        raise SystemExit(1)


def add_parsers(sub):
    a = sub.add_parser("godot-ai"); a.add_argument("--ki", required=True)
    a.add_argument("--nyelv", default="hu", choices=["hu", "en"]); a.set_defaults(fn=cmd_ai)
    k = sub.add_parser("godot-kutat")
    k.add_argument("kerdes")
    k.add_argument("--ai", default="none", choices=["claude", "openai", "gemini", "ollama", "none"])
    k.add_argument("--mappa", required=True)
    k.add_argument("--kereses", default="", help="angol keresőkifejezések, '|' jellel elválasztva")
    k.add_argument("--parameterek", default="", help="a keresett modellparaméterek, vesszővel elválasztva")
    k.add_argument("--cikkek", type=int, default=12)
    k.add_argument("--forrasonkent", type=int, default=6)
    k.add_argument("--nyelv", default="hu", choices=["hu", "en"], help="a játékos nyelve (hu/en)")
    k.set_defaults(fn=cmd_kutat)
    m = sub.add_parser("godot-modell"); m.add_argument("be"); m.add_argument("--ki", required=True)
    m.add_argument("--nyelv", default="hu", choices=["hu", "en"])
    m.set_defaults(fn=cmd_modell)
