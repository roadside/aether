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
    # Tudásfa-témák általános mennyiségei (tájékoztató, a modellbe még nem kerülnek)
    "kibocsatas_csokkentes_pct": {"unit": "%", "range": (0.0, 100.0),
        "leiras": "Üvegházgáz-kibocsátás (vagy energiafelhasználás) relatív csökkenése egy technológiával/intézkedéssel"},
    "kibocsatas_potencial_gtco2e_ev": {"unit": "GtCO2e/év", "range": (0.0, 25.0),
        "leiras": "Globális kibocsátáscsökkentési potenciál évente"},
    "hatasfok_pct": {"unit": "%", "range": (0.0, 100.0), "leiras": "Átalakítási vagy visszanyerési hatásfok"},
    "energiasuruseg_wh_kg": {"unit": "Wh/kg", "range": (0.0, 1500.0), "leiras": "Energiatároló tömegre vetített energiasűrűsége"},
    "valtozas_pct_per_c": {"unit": "%/°C", "range": (-100.0, 300.0), "leiras": "Egy hatás változása 1 °C melegedésre"},
    "tengerszint_cm": {"unit": "cm", "range": (0.0, 500.0), "leiras": "Tengerszint-emelkedés (pl. 2100-ig)"},
    "jegveszteseg_gt_ev": {"unit": "Gt/év", "range": (0.0, 3000.0), "leiras": "Jégtömeg-veszteség évente"},
    "klimaerzekenyseg_c": {"unit": "°C", "range": (0.5, 10.0), "leiras": "Egyensúlyi klímaérzékenység (CO2-duplázódás)"},
    "kockazat_csokkentes_pct": {"unit": "%", "range": (0.0, 100.0), "leiras": "Kockázat, kár vagy halálozás csökkenése alkalmazkodással"},
    "lehules_c": {"unit": "°C", "range": (0.0, 20.0), "leiras": "Helyi hűtő hatás (lehűlés °C-ban)"},
    "elkerult_melegedes_c": {"unit": "°C", "range": (0.0, 5.0), "leiras": "Elkerült (megelőzött) globális melegedés °C-ban"},
    "sugarzasi_kenyszer_w_m2": {"unit": "W/m²", "range": (-10.0, 10.0),
        "leiras": "Melegítő (+) vagy hűtő (-) hatás W/m²-ben (sugárzási kényszer, energiaegyensúly)"},
    "visszacsatolas_w_m2_c": {"unit": "W/m²/°C", "range": (-3.0, 3.0),
        "leiras": "Visszacsatolás erőssége: W/m² minden °C melegedésre"},
    "valtozas_pct": {"unit": "%", "range": (-100.0, 1000.0),
        "leiras": "Egy hatás változása százalékban (a cikkben megadott melegedésnél vagy időszakra)"},
    "csokkenes_pct": {"unit": "%", "range": (0.0, 100.0),
        "leiras": "Csökkenés vagy veszteség százalékban (pl. áramlás gyengülése, élőhely vagy munkaidő elvesztése)"},
    "reszarany_pct": {"unit": "%", "range": (0.0, 100.0),
        "leiras": "Részarány százalékban (pl. a többlethő, a kibocsátás vagy a halálesetek mekkora része; túlélési vagy megtartási arány)"},
    "szen_gtc": {"unit": "Gt C", "range": (0.0, 2000.0),
        "leiras": "Szénmennyiség milliárd tonna szénben (tárolt vagy kibocsátott, pl. 2100-ig)"},
    "terulet_mha_ev": {"unit": "Mha/év", "range": (0.0, 100.0), "leiras": "Terület változása évente, millió hektárban"},
    "ph_valtozas": {"unit": "pH", "range": (-1.0, 0.5), "leiras": "A pH-érték változása (negatív: savasodás)"},
    "megkotes_mmol_g": {"unit": "mmol/g", "range": (0.0, 30.0), "leiras": "Gázmegkötő képesség: mmol gáz grammonként"},
    "eletciklus_gco2_kwh": {"unit": "gCO2e/kWh", "range": (0.0, 1500.0),
        "leiras": "Életciklus-kibocsátás: gramm CO2-egyenérték egy kilowattóra áramra (építéstől a bontásig)"},
    "szenmegkotes_t_ha_ev": {"unit": "t C/ha/év", "range": (0.0, 50.0),
        "leiras": "Szénmegkötés hektáronként évente, tonna szénben"},
    "energia_nyereseg": {"unit": "×", "range": (0.0, 1000.0), "leiras": "Energianyereség: a kinyert és a befektetett energia aránya"},
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
- Az idézetben a szám MÉRTÉKEGYSÉGE is szerepeljen, és egyezzen a paraméterével (pl. GtCO2/év).
  Egy célérték (pl. "1.5°C") vagy más mennyiség (pl. talaj széntartalma %-ban) nem CDR-potenciál.
- Az alkalmazkodási hozamelőny (alkalmazkodas_hozam_elony_pct) a jobb fajta TERMÉSTÖBBLETE a hagyományoshoz
  képest. Nem az: termésveszteség, a fajtát termesztő gazdák vagy terület aránya.
- A szám arra a módszerre vonatkozzon, amelyet az 'alkategoria' megnevez, és ez a módszer
  szerepeljen az idézetben (pl. "for biochar"). Ha egy mondat több módszer számát sorolja fel,
  mindegyikhez külön állítást adj.
- Az 'alkategoria' az idézetben szereplő módszer vagy fajta EREDETI szava legyen, ahogy a cikkben áll
  (pl. "biochar", "drought-tolerant maize"). NE fordítsd le, és a rövidítést (pl. DT, BECCS) se
  fordítsd: a játék maga cseréli köznapi magyarra.
- Ha az absztrakt nem tartalmaz számszerű eredményt az adott paraméterhez, NE találj ki semmit.
- Ne használd a saját háttértudásodat számokhoz. Ha bizonytalan vagy, hagyd ki.
- Az 'osszegzes' magyarul, 3-5 rövid, hétköznapi mondatban írja le, mit mutatnak a cikkek és mit NEM.
  Egy nem szakember is értse. Ne használj angol szót és megmagyarázatlan rövidítést; tizedesvesszőt írj (0,5).
  Szójegyzék: BECCS = növényi energia a CO2 föld alá zárásával; DACCS / DAC = CO2-szűrés közvetlenül a
  levegőből; enhanced (rock) weathering = kőzetmállasztás (kőpor a földekre); biochar = bioszén;
  soil carbon sequestration = talaj szénmegkötése; afforestation = erdősítés; GtCO2/év = milliárd tonna CO2 évente.
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


# Az idézetben a paraméter mértékegységének nyoma (kisbetűs, normalizált szövegben).
UNIT_PATTERNS: Dict[str, object] = {
    # CO2-ben (nem szénben: a "Pg C"/"Gt C" 3,67-szer kisebb szám) ÉS évente
    "cdr_potencial_gtco2_ev": [r"(g\s*t|gigaton\w*|billion\s+(metric\s+)?tonnes?|bn\s*t|pg)\s*(of\s+)?-?\s*co\s*2",
                               r"yr|year|annual|/\s*a\b|\ba\s*-\s*1|y\s*-\s*1"],
    "cdr_koltseg_usd_tco2": r"\$|usd|dollar|€|eur",
    "metan_csokkentes_pct": r"%|percent|per\s*cent",
    "hozam_valtozas_pct_per_c": r"%|percent|per\s*cent",
    "alkalmazkodas_hozam_elony_pct": r"%|percent|per\s*cent",
    "viztakarekossag_pct": r"%|percent|per\s*cent",
    "sai_kenyszer_w_m2_per_tg": r"w\s*m|w/m",
    "aeroszol_erf_w_m2": r"w\s*m|w/m",
    "tcre_c_per_1000gtco2": r"°\s*c|\bk\b|kelvin|degree",
    "kibocsatas_csokkentes_pct": r"%|percent|per\s*cent",
    "kibocsatas_potencial_gtco2e_ev": [r"(g\s*t|gigaton\w*|billion\s+(metric\s+)?tonnes?|bn\s*t|pg)\s*(of\s+)?-?\s*co\s*2", r"yr|year|annual|/\s*a\b|\ba\s*-\s*1|y\s*-\s*1"],
    "hatasfok_pct": r"%|percent|per\s*cent",
    "energiasuruseg_wh_kg": r"wh\s*(/|per)?\s*kg|wh\s*kg",
    "valtozas_pct_per_c": [r"%|percent|per\s*cent", r"°\s*c|\bk\b|kelvin|degree"],
    "tengerszint_cm": r"\bcm\b|centimet",
    "jegveszteseg_gt_ev": [r"\bgt\b|gigaton|gt\s*(yr|a\b|/)", r"yr|year|annual|/\s*a\b|\ba\s*-\s*1|y\s*-\s*1"],
    "klimaerzekenyseg_c": r"°\s*c|\bk\b|kelvin|degree",
    "kockazat_csokkentes_pct": r"%|percent|per\s*cent",
    "lehules_c": r"°\s*c|\bk\b|kelvin|degree",
    "elkerult_melegedes_c": r"°\s*c|\bk\b|kelvin|degree",
    "sugarzasi_kenyszer_w_m2": r"w\s*m|w/m",
    "visszacsatolas_w_m2_c": [r"w\s*m|w/m", r"°\s*c|\bk\b|kelvin|degree|k\s*-\s*1"],
    "valtozas_pct": r"%|percent|per\s*cent",
    "csokkenes_pct": r"%|percent|per\s*cent",
    "reszarany_pct": r"%|percent|per\s*cent",
    "szen_gtc": r"\b(pg|gt)\s*-?\s*c\b|\bp?g\s*t?\s*c\b|petagram|gigaton\w*\s+(of\s+)?carbon|billion\s+(metric\s+)?tonnes?\s+of\s+carbon|\bpg\b|\bgtc\b|\bpgc\b",
    "terulet_mha_ev": r"\bmha\b|million\s+hectares|\bm\s*ha\b|million\s+ha\b",
    "ph_valtozas": r"\bph\b",
    "megkotes_mmol_g": r"mmol",
    "eletciklus_gco2_kwh": [r"g\s*-?\s*co\s*2|gco2|grams?\s+(of\s+)?co2", r"kwh|kw\s*h|kilowatt"],
    "szenmegkotes_t_ha_ev": [r"\bt\b|\bmg\b|tonnes?|tons?|\bpg\b", r"\bha\b|hectare"],
    "energia_nyereseg": r"gain|\bq\b|\bmj\b|ratio",
}


# Az idézet tényleg a paraméter mennyiségéről szól-e (nem csak az egység stimmel).
# (kötelező minta, tiltott minta) – pl. az aszálytűrő fajta előnye termésNÖVEKEDÉS,
# nem veszteség és nem az elterjedtség aránya ("30% of households").
QUOTE_RULES: Dict[str, tuple] = {
    "alkalmazkodas_hozam_elony_pct": (
        r"increas|higher|more|greater|advantage|gain|outyield|out-yield|improv|boost|benefit|superior",
        r"household|farmers\s+(were|are)|adoption\s+(rate|share|level)|share\s+of|area\s+(under|planted)|"
        r"\bloss(es)?\b|decreas|declin|reduc"),
}


def quote_fits(param: str, quote: str) -> bool:
    rule = QUOTE_RULES.get(param)
    if rule is None:
        return True
    q = _norm_text(quote)
    return re.search(rule[0], q) is not None and re.search(rule[1], q) is None


def unit_in_quote(param: str, quote: str) -> bool:
    """Minden megadott mintának illeszkednie kell (pl. CO2-egység ÉS évenként)."""
    pats = UNIT_PATTERNS.get(param)
    if pats is None:
        return True
    q = _norm_text(quote)
    return all(re.search(p, q) is not None for p in ([pats] if isinstance(pats, str) else pats))


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
        if spec is not None and not unit_in_quote(c.parameter, c.szo_szerinti_idezet):
            c.indokok.append(f"Az idézetben nincs a paraméter mértékegysége ({spec['unit']}).")
        elif spec is not None and not quote_fits(c.parameter, c.szo_szerinti_idezet):
            c.indokok.append("Az idézet nem a keresett mennyiségről szól (pl. veszteség vagy elterjedtség).")
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
    if n >= 2:   # egyetlen forrás (akár összefoglaló is) csak gyenge bizonyíték
        return "közepes"
    return "alacsony"


# ---------------------------------------------------------------------------
# Magyarítás: az AI szövegében maradt angol szakszavak és rövidítések cseréje
# ---------------------------------------------------------------------------
HU_GLOSSARY = [
    (r"enhanced\s+rock\s+weathering|enhanced\s+weathering|rock\s+weathering", "kőzetmállasztás"),
    (r"soil\s+carbon\s+sequestration", "talaj szénmegkötése"),
    (r"soil\s+organic\s+carbon", "talaj szerves szene"),
    (r"direct\s+air\s+(?:carbon\s+)?capture(?:\s+and\s+storage)?", "CO2-szűrés közvetlenül a levegőből"),
    (r"bioenergy\s+with\s+carbon\s+capture\s+and\s+storage", "növényi energia a CO2 föld alá zárásával"),
    (r"carbon\s+capture\s+and\s+storage", "CO2 leválasztása és föld alá zárása"),
    (r"negative\s+emissions?\s+technolog(?:y|ies)", "CO2-kivonó módszerek"),
    (r"carbon\s+dioxide\s+removal", "CO2-kivonás"),
    (r"biochar", "bioszén"),
    (r"afforestation", "erdősítés"),
    (r"reforestation", "újraerdősítés"),
    (r"meta-?analys[ie]s", "metaanalízis"),
    (r"drought[\s-]+toleran(?:t|ce)\s+(?:maize|corn)", "aszálytűrő kukorica"),
    (r"drought[\s-]+toleran(?:t|ce)", "aszálytűrő"),
    (r"\bmaize\b", "kukorica"),
]
HU_ABBR = [
    (r"\bBECCS\b", "növényi energia a CO2 föld alá zárásával"),
    (r"\bDACCS\b|\bDACS\b|\bDAC\b", "CO2-szűrés közvetlenül a levegőből"),
    (r"\bCCS\b", "CO2 föld alá zárása"),
    (r"\bNETs?\b", "CO2-kivonó módszerek"),
    (r"\bCDR\b", "CO2-kivonás"),
    (r"\bEW\b|\bERW\b", "kőzetmállasztás"),
    (r"\bSCS\b", "talaj szénmegkötése"),
    (r"\bDT\s+(?:maize|corn)\b", "aszálytűrő kukorica"),
    (r"\bDT\b", "aszálytűrő"),
    (r"GtCO2\s*/\s*(?:év|yr|year)", "milliárd tonna CO2/év"),
    (r"\bUSD\s*/\s*t\s*CO2\b", "dollár/tonna CO2"),
]


def plausible_subcategory(sub: str, *texts: str) -> bool:
    """Az AI által megnevezett alkategória (módszer, fajta) legalább egy jelentős szava szerepel-e
    az idézetben vagy a cikkben. Ha nem, valószínűleg félrefordítás (pl. "DT maize" -> "asztal"),
    és nem szabad megjeleníteni."""
    words = [w for w in re.findall(r"[^\W\d_]+", (sub or "").lower()) if len(w) >= 3]
    if not words:
        return True
    hay = " ".join(t or "" for t in texts).lower()
    return any(w in hay for w in words)


def hungarianize(text: str) -> str:
    """A magyar szövegben maradt angol szakszavakat és rövidítéseket köznapi magyarra cseréli,
    és a tizedespontot tizedesvesszőre."""
    if not text:
        return text
    for pat, hu in HU_GLOSSARY:
        text = re.sub(pat, hu, text, flags=re.I)
    for pat, hu in HU_ABBR:
        text = re.sub(pat, hu, text)
    return re.sub(r"(?<=\d)\.(?=\d)", ",", text)


# ---------------------------------------------------------------------------
# Az AI szabad szövegében (összegzés) csak ellenőrzött szám maradhat
# ---------------------------------------------------------------------------
_NUM_RE = re.compile(r"(?<![\w.,])[-+−–]?\d+(?:[.,]\d+)?")
_SENT_RE = re.compile(r"(?<=[.!?])\s+")
_ABBREV = ("pl.", "kb.", "ill.", "stb.", "ún.", "vö.", "e.g.", "i.e.", "etc.", "vs.", "ca.", "cf.",
           "approx.", "fig.", "al.", "mtsai.", "max.", "min.", "sz.")


def split_sentences(text: str) -> List[str]:
    """Mondatokra bont, de nem vág zárójelen belül és rövidítés (pl., kb., e.g.) után."""
    out: List[str] = []
    cur = ""
    for part in _SENT_RE.split(text.strip()):
        cur = (cur + " " + part) if cur else part
        low = cur.lower()
        if cur.count("(") > cur.count(")") or low.endswith(_ABBREV):
            continue
        out.append(cur)
        cur = ""
    if cur:
        out.append(cur)
    return out


def only_verified_numbers(text: str, claims: List[Claim]) -> str:
    """Kihagyja a szövegből azokat a mondatokat, amelyekben olyan szám áll, amit az ellenőrzés
    nem igazolt. Az alapelv: a játék csak azt a számot mutatja, ami szó szerint benne van egy
    cikkben. Évszám (1800–2100) maradhat. Ha semmi sem marad, üres szöveget ad."""
    if not text:
        return ""
    allowed = set()
    for c in claims:
        if not str(getattr(c, "statusz", "")).startswith("ellenorizve"):
            continue
        for v in (c.ertek, c.also, c.felso):
            if v is not None:
                allowed.add(round(abs(float(v)), 6))
    kept = []
    cut = False                    # az előző mondatot kihagytuk
    for sent in split_sentences(text):
        ok = True
        for m in _NUM_RE.finditer(sent):
            raw = m.group(0).lstrip("+-−–").replace(",", ".")
            try:
                v = float(raw)
            except ValueError:
                continue
            if "." not in raw and 1800 <= v <= 2100:
                continue          # évszám
            if round(v, 6) not in allowed:
                ok = False
                break
        if ok and sent.strip():
            kept.append(_drop_linking(sent.strip()) if cut else sent.strip())
        cut = not ok
    return " ".join(k for k in kept if k)


_LINK_START = re.compile(
    r"^(?:azonban|viszont|ugyanakkor|ezzel szemben|ennek ellenére|emellett|ezért|így|tehát|de|"
    r"however|but|yet|still|nevertheless|in contrast|therefore|thus|moreover)\b\s*,?\s*", re.I)
_LINK_SECOND = re.compile(
    r"^((?:\S+\s+){1,3}?)(?:azonban|viszont|ugyanakkor|pedig|however),?\s+", re.I)


def _drop_linking(sent: str) -> str:
    """Ha a megelőző mondatot kihagytuk, a mondat elejéről lekerül az arra visszautaló
    kötőszó („Azonban…", „A fajták azonban…", „However, …"), hogy a szöveg önállóan is álljon."""
    out = _LINK_START.sub("", sent, count=1)
    if out == sent:
        out = _LINK_SECOND.sub(r"\1", sent, count=1)
    if out and out != sent:
        out = out[0].upper() + out[1:]
    return out
