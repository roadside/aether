"""Bizonyíték-kinyerés és -ellenőrzés.

Az AI által kinyert minden állítást determinisztikus kód ellenőriz:
  1. a hivatkozott cikk tényleg a keresési találatok között van,
  2. a megadott idézet SZÓ SZERINT szerepel a cikk absztraktjában,
  3. a kinyert szám(ok) szerepelnek az idézetben,
  4. az érték fizikailag/irodalmilag értelmes tartományban van,
  5. a cikk nincs visszavonva; a preprint (nem lektorált) jelölést kap.
Ami nem megy át, az "elutasítva" státuszt kap, és a modellbe nem kerülhet.
"""
from __future__ import annotations

import re
import statistics
import unicodedata
from dataclasses import dataclass, field, asdict
from typing import Dict, List, Optional, Tuple

from .literature import Paper

# Az AI csak ezeket a paramétereket töltheti, mindegyiknek egység és
# józan tartomány jár. ("egyeb" megengedett, de a modellbe sosem kerül.)
PARAMETERS: Dict[str, Dict] = {
    "cdr_potencial_gtco2_ev": {"unit": "GtCO2/év", "range": (0.0, 15.0),
        "leiras": "Egy CO2-eltávolítási módszer globális potenciálja"},
    "cdr_koltseg_usd_tco2": {"unit": "USD/tCO2", "range": (0.0, 3000.0),
        "leiras": "CO2-eltávolítás költsége tonnánként"},
    "metan_csokkentes_pct": {"unit": "%", "range": (0.0, 100.0),
        "leiras": "Metánkibocsátás csökkenthetősége egy ágazatban/intézkedéssel"},
    "hozam_valtozas_pct_per_c": {"unit": "%/°C", "range": (-40.0, 15.0),
        "leiras": "Terméshozam változása 1 °C melegedésre"},
    "alkalmazkodas_hozam_elony_pct": {"unit": "%", "range": (0.0, 100.0),
        "leiras": "Szárazságtűrő fajta / alkalmazkodás hozamelőnye stressz alatt"},
    "viztakarekossag_pct": {"unit": "%", "range": (0.0, 100.0),
        "leiras": "Vízfelhasználás csökkenése egy technológiával"},
    "sai_kenyszer_w_m2_per_tg": {"unit": "W/m²/(Tg SO2/év)", "range": (0.0, 1.0),
        "leiras": "Sztratoszférikus SO2 sugárzási kényszere egységnyi befecskendezésre"},
    "aeroszol_erf_w_m2": {"unit": "W/m²", "range": (-3.0, 1.0),
        "leiras": "Aeroszol effektív sugárzási kényszer"},
    "tcre_c_per_1000gtco2": {"unit": "°C/1000 GtCO2", "range": (0.0, 1.5),
        "leiras": "Tranziens klímaválasz kumulatív CO2-kibocsátásra"},
    "egyeb": {"unit": "", "range": (-1e12, 1e12), "leiras": "Egyéb (csak tájékoztató, modellbe nem kerül)"},
}

STUDY_TYPES = ["meta-analizis", "szisztematikus-attekintes", "attekintes", "terepkiserlet",
               "laborkiserlet", "megfigyeles", "modellezes", "egyeb"]
STUDY_WEIGHT = {"meta-analizis": 3.0, "szisztematikus-attekintes": 3.0, "attekintes": 2.0,
                "terepkiserlet": 2.0, "laborkiserlet": 1.5, "megfigyeles": 1.5,
                "modellezes": 1.2, "egyeb": 1.0}

# --- JSON-sémák az AI-nak -------------------------------------------------
QUERY_PLAN_SCHEMA = {
    "type": "object",
    "properties": {
        "kutatasi_kerdes_pontositva": {"type": "string"},
        "angol_keresokifejezesek": {"type": "array", "items": {"type": "string"}},
        "keresett_parameterek": {"type": "array", "items": {"type": "string", "enum": list(PARAMETERS)}},
        "megjegyzes": {"type": "string"},
    },
    "required": ["kutatasi_kerdes_pontositva", "angol_keresokifejezesek", "keresett_parameterek", "megjegyzes"],
    "additionalProperties": False,
}

EXTRACTION_SCHEMA = {
    "type": "object",
    "properties": {
        "allitasok": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "cikk_azonosito": {"type": "string"},
                    "parameter": {"type": "string", "enum": list(PARAMETERS)},
                    "alkategoria": {"type": "string"},
                    "ertek": {"type": "number"},
                    "also": {"type": ["number", "null"]},
                    "felso": {"type": ["number", "null"]},
                    "egyseg": {"type": "string"},
                    "szo_szerinti_idezet": {"type": "string"},
                    "vizsgalat_tipusa": {"type": "string", "enum": STUDY_TYPES},
                    "regio": {"type": "string"},
                    "korlatok": {"type": "string"},
                },
                "required": ["cikk_azonosito", "parameter", "alkategoria", "ertek", "also", "felso",
                             "egyseg", "szo_szerinti_idezet", "vizsgalat_tipusa", "regio", "korlatok"],
                "additionalProperties": False,
            },
        },
        "osszegzes": {"type": "string"},
        "ellentmondasok": {"type": "string"},
    },
    "required": ["allitasok", "osszegzes", "ellentmondasok"],
    "additionalProperties": False,
}

PLANNER_SYSTEM = """Te az AETHER kutatóállomás tudományos asszisztense vagy.
A játékos kutatási kérdéséből 3-5 rövid, ANGOL nyelvű tudományos keresőkifejezést
készítesz (pl. "drought tolerant maize yield meta-analysis"), és kiválasztod, mely
modellparaméterekhez keresünk bizonyítékot. Ne válaszolj a kérdésre, ne adj meg számokat."""

EXTRACTOR_SYSTEM = """Te az AETHER kutatóállomás tudományos asszisztense vagy.
Csak a megadott absztraktokból dolgozhatsz. Szabályok:
- Minden állításhoz adj SZÓ SZERINTI idézetet az absztraktból (pontosan másolva, karakterre).
- Az 'ertek' (és ha van, 'also'/'felso') számnak szerepelnie kell az idézetben.
- Ha az absztrakt nem tartalmaz számszerű eredményt az adott paraméterhez, NE találj ki semmit.
- Ne használd a saját háttértudásodat számokhoz. Ha bizonytalan vagy, hagyd ki.
- Az 'osszegzes' magyarul, 3-6 mondatban írja le, mit mutatnak a cikkek és mit NEM.
- Az 'ellentmondasok' mezőben jelezd, ha a cikkek ellentmondanak egymásnak."""


@dataclass
class Claim:
    cikk_azonosito: str
    parameter: str
    alkategoria: str
    ertek: float
    also: Optional[float]
    felso: Optional[float]
    egyseg: str
    szo_szerinti_idezet: str
    vizsgalat_tipusa: str
    regio: str
    korlatok: str
    statusz: str = "nincs-ellenorizve"
    indokok: List[str] = field(default_factory=list)
    forras: str = ""
    preprint: bool = False


def _norm_text(s: str) -> str:
    s = unicodedata.normalize("NFKC", s or "")
    s = s.replace("−", "-").replace("–", "-").replace("—", "-")
    s = s.replace(" ", " ").replace(" ", " ")
    return " ".join(s.lower().split())


_NUM = re.compile(r"-?\d+(?:[.,]\d+)?")


def numbers_in(text: str) -> List[float]:
    out = []
    for m in _NUM.findall(_norm_text(text)):
        try:
            out.append(float(m.replace(",", ".")))
        except ValueError:
            pass
    return out


def _num_present(x: float, nums: List[float]) -> bool:
    for n in nums:
        if abs(n - x) <= 1e-9 or abs(abs(n) - abs(x)) <= 1e-6 * max(1, abs(x)):
            return True  # előjelet szövegesen is jelölhetik ("decreased by 7")
    return False


def quote_in(quote: str, text: str) -> bool:
    """Szó szerint benne van-e az idézet. A szóközöket nem nézzük, mert az absztraktokban
    a képletek gyakran szét vannak törve ("GtCO 2 yr −1" = "GtCO2 yr−1"); a betűk és számok
    sorrendjének viszont pontosan egyeznie kell."""
    q = _norm_text(quote)
    if not q:
        return False
    t = _norm_text(text)
    return q in t or "".join(q.split()) in "".join(t.split())


def verify(claims: List[Claim], papers: Dict[str, Paper]) -> List[Claim]:
    for c in claims:
        c.indokok = []
        p = papers.get(c.cikk_azonosito)
        if p is None:
            c.indokok.append("A hivatkozott cikk nincs a keresési találatok között.")
        else:
            c.forras = p.citation()
            c.preprint = p.peer_reviewed is False
            if p.is_retracted:
                c.indokok.append("A cikket visszavonták.")
            if not quote_in(c.szo_szerinti_idezet, p.abstract):
                c.indokok.append("Az idézet nem található szó szerint az absztraktban.")
        nums = numbers_in(c.szo_szerinti_idezet)
        for label, v in (("érték", c.ertek), ("alsó", c.also), ("felső", c.felso)):
            if v is not None and not _num_present(v, nums):
                c.indokok.append(f"A(z) {label} ({v}) nem szerepel az idézetben.")
        spec = PARAMETERS.get(c.parameter)
        if spec is None:
            c.indokok.append("Ismeretlen paraméter.")
        else:
            lo, hi = spec["range"]
            if not (lo <= c.ertek <= hi):
                c.indokok.append(f"Az érték kívül esik a józan tartományon ({lo}..{hi} {spec['unit']}).")
        c.statusz = "elutasitva" if c.indokok else ("ellenorizve-preprint" if c.preprint else "ellenorizve")
    return claims


def aggregate(claims: List[Claim]) -> Dict[str, Dict]:
    """Paraméterenként (és alkategóriánként) súlyozott medián + teljes tartomány."""
    groups: Dict[Tuple[str, str], List[Claim]] = {}
    for c in claims:
        if c.statusz.startswith("ellenorizve") and c.parameter != "egyeb":
            groups.setdefault((c.parameter, c.alkategoria.lower().strip()), []).append(c)
    out = {}
    for (param, sub), cs in groups.items():
        weighted = []
        for c in cs:
            w = STUDY_WEIGHT.get(c.vizsgalat_tipusa, 1.0) * (0.5 if c.preprint else 1.0)
            weighted += [c.ertek] * max(1, int(round(w * 2)))
        vals = [c.ertek for c in cs] + [v for c in cs for v in (c.also, c.felso) if v is not None]
        out[f"{param}:{sub}"] = {
            "parameter": param,
            "alkategoria": sub,
            "egyseg": PARAMETERS[param]["unit"],
            "sulyozott_median": round(statistics.median(weighted), 4),
            "tartomany": [min(vals), max(vals)],
            "forrasok_szama": len({c.cikk_azonosito for c in cs}),
            "bizonyossag": _confidence(cs),
        }
    return out


def _confidence(cs: List[Claim]) -> str:
    n = len({c.cikk_azonosito for c in cs})
    strong = any(c.vizsgalat_tipusa in ("meta-analizis", "szisztematikus-attekintes") and not c.preprint for c in cs)
    if n >= 3 and strong:
        return "magas"
    if n >= 2 or strong:
        return "közepes"
    return "alacsony"
