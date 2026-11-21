"""A játék valós kiindulópontja: a Föld mai állapota nyílt, ellenőrizhető forrásokból.

ALAPELV: minden adat valódi mérés vagy hivatalos jelentés, dátummal, hellyel és
linkkel. Amihez nincs ellenőrizhető forrás, az nem jelenik meg. Ha egy forrás
nem érhető el, a játék ezt megmondja, és nem pótolja kitalált adattal.

Források (API-kulcs nélkül):
  - GDACS (ENSZ + EU JRC): aszály, árvíz, trópusi ciklon, földrengés, vulkán, erdőtűz
    riasztások, országonként.                          https://www.gdacs.org
  - ReliefWeb (ENSZ OCHA): humanitárius jelentések, élelmiszerhiány, járványok,
    katasztrófák minden országból.                     https://reliefweb.int
  - NASA EONET: természeti események műholdas forrásokkal (tűz, jég, por, vulkán).
                                                       https://eonet.gsfc.nasa.gov
  - NOAA GML: a légköri CO2 havi mérése (Mauna Loa).    https://gml.noaa.gov/ccgg/trends/
  - NSIDC Sea Ice Index: az északi-sarki tengeri jég kiterjedése naponta.
                                                       https://nsidc.org/data/seaice_index
  - Open-Meteo (Copernicus CAMS és időjárási modellek alapján): levegőminőség (PM2,5,
    NO2, ózon), UV-index és talajnedvesség 30 nagyvárosban, minden kontinensen.
    FIGYELEM: ezek modellbecslések, nem mérőállomás-adatok; a játék így jelöli őket.
                                                       https://open-meteo.com
Az országot koordinátából, internet nélkül adjuk meg (geo.py, GeoNames-adat).
Még hiányzik: vízminőség (UNEP GEMStat, regisztráció), élelmiszerhiány országonként
(ReliefWeb, jóváhagyott appname; HDX HAPI).

Használat:  python -m aether_lab vilag --ki vilag.json
"""
from __future__ import annotations

import csv
import datetime as _dt
import io
import json
import os
import time
import urllib.parse
import urllib.request
from typing import Callable, Dict, List, Optional

USER_AGENT = "AETHER-climate-game-prototype/0.1 (educational)"
RELIEFWEB_APPNAME = os.environ.get("AETHER_RELIEFWEB_APPNAME", "aether-climate-game")

# Állandó, idézett kiinduló értékek (évente frissítendők). Minden sorhoz forrás tartozik.
CITED_FACTS = [
    {"azonosito": "melegedes_ember_2024", "cim": "Ember okozta melegedés (2024)", "ertek": 1.36, "egyseg": "°C",
     "magyarazat": "Ennyivel melegebb a Föld az ipari forradalom előttinél, az emberi hatás miatt.",
     "cim_en": "Human-caused warming (2024)",
     "magyarazat_en": "This is how much warmer the Earth is than before the industrial revolution, because of human activity.",
     "forras": "Forster et al. 2025, Earth System Science Data (Indicators of Global Climate Change 2024)",
     "link": "https://doi.org/10.5194/essd-17-2641-2025"},
    {"azonosito": "co2_keret_1_5", "cim": "Maradék CO2-keret 1,5 °C-hoz (2025 eleje)", "ertek": 130, "egyseg": "milliárd t",
     "magyarazat": "Ennyi CO2 kibocsátása után 50% eséllyel elérjük az 1,5 °C-ot. A mai ütemben kb. 3 év.",
     "cim_en": "Remaining CO2 budget for 1.5 °C (start of 2025)", "egyseg_en": "billion t",
     "magyarazat_en": "After emitting this much CO2 we reach 1.5 °C with a 50% chance. At today's pace, about 3 years.",
     "forras": "Forster et al. 2025, Earth System Science Data",
     "link": "https://doi.org/10.5194/essd-17-2641-2025"},
]

KATEGORIA = {  # egységes, hétköznapi kategóriák a játékhoz
    "DR": "aszaly", "FL": "arviz", "TC": "vihar", "EQ": "foldrenges", "VO": "vulkan", "WF": "tuz",
    "drought": "aszaly", "floods": "arviz", "severeStorms": "vihar", "earthquakes": "foldrenges",
    "volcanoes": "vulkan", "wildfires": "tuz", "seaLakeIce": "jeg", "snow": "jeg", "dustHaze": "levego",
    "manmade": "szennyezes", "waterColor": "viz", "tempExtremes": "hoseg", "landslides": "arviz",
}
# Nagyvárosok a levegő- és UV-adatokhoz (minden kontinens; koordináták: városközpont)
CITIES = [
    ("Budapest", 47.50, 19.04), ("London", 51.51, -0.13), ("Moszkva", 55.76, 37.62), ("Isztambul", 41.01, 28.98),
    ("Kairó", 30.04, 31.24), ("Lagos", 6.52, 3.38), ("Kinshasa", -4.32, 15.31), ("Nairobi", -1.29, 36.82),
    ("Johannesburg", -26.20, 28.05), ("Teherán", 35.69, 51.39), ("Karacsi", 24.86, 67.01), ("Delhi", 28.61, 77.21),
    ("Dakka", 23.81, 90.41), ("Bangkok", 13.76, 100.50), ("Jakarta", -6.21, 106.85), ("Manila", 14.60, 120.98),
    ("Peking", 39.90, 116.41), ("Sanghaj", 31.23, 121.47), ("Tokió", 35.68, 139.69), ("Szöul", 37.57, 126.98),
    ("Sydney", -33.87, 151.21), ("Auckland", -36.85, 174.76), ("Los Angeles", 34.05, -118.24), ("New York", 40.71, -74.01),
    ("Mexikóváros", 19.43, -99.13), ("Bogotá", 4.71, -74.07), ("Lima", -12.05, -77.04), ("São Paulo", -23.55, -46.63),
    ("Buenos Aires", -34.60, -58.38), ("Reykjavík", 64.15, -21.94),
]
# A városnevek angolul (ahol eltér a magyartól)
CITY_EN = {"Moszkva": "Moscow", "Isztambul": "Istanbul", "Kairó": "Cairo", "Teherán": "Tehran", "Karacsi": "Karachi",
           "Dakka": "Dhaka", "Peking": "Beijing", "Sanghaj": "Shanghai", "Tokió": "Tokyo", "Szöul": "Seoul",
           "Mexikóváros": "Mexico City"}
CAMS_FORRAS = "Open-Meteo / Copernicus CAMS (modellbecslés)"
CAMS_FORRAS_EN = "Open-Meteo / Copernicus CAMS (model estimate)"
WHO_PM25_24H = 15.0      # µg/m³, WHO 2021 levegőminőségi irányelv, 24 órás érték
UV_VERY_HIGH = 8.0       # WHO UV-index skála: 8–10 nagyon magas, 11+ extrém

KATEGORIA_NEV = {"aszaly": "Aszály", "arviz": "Árvíz", "vihar": "Vihar", "foldrenges": "Földrengés",
                 "vulkan": "Vulkán", "tuz": "Erdőtűz", "jeg": "Jég és hó", "levego": "Por, füst, levegő",
                 "szennyezes": "Szennyezés", "viz": "Vízminőség", "hoseg": "Hőség", "ehezes": "Élelmiszerhiány",
                 "jarvany": "Járvány", "uv": "Erős UV-sugárzás", "egyeb": "Egyéb"}


def _http(url: str, data: Optional[bytes] = None, timeout: int = 30, retries: int = 2) -> bytes:
    headers = {"User-Agent": USER_AGENT, "Accept": "application/json, text/csv, */*"}
    if data is not None:
        headers["Content-Type"] = "application/json"
    last = None
    for i in range(retries):
        try:
            req = urllib.request.Request(url, data=data, headers=headers)
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read()
        except Exception as e:
            last = e
            time.sleep(1.0 * (i + 1))
    raise ConnectionError(f"{url}: {last}")


def _event(forras, cim, kat, datum, orszag, lat, lon, link, szint="", leiras="", cim_en="", forras_en="") -> Dict:
    """Egy esemény. A forrás eredeti címe (többnyire angol) változatlan marad;
    a játék által írt címekhez *_en angol változat is tartozik."""
    e = {"forras": forras, "cim": cim.strip(), "kategoria": kat, "kategoria_nev": KATEGORIA_NEV.get(kat, kat),
         "datum": (datum or "")[:10], "orszag": orszag or "", "lat": lat, "lon": lon, "link": link,
         "szint": szint, "leiras": (leiras or "").strip()[:300]}
    if cim_en:
        e["cim_en"] = cim_en.strip()
    if forras_en:
        e["forras_en"] = forras_en
    return e


# --- GDACS ------------------------------------------------------------------
def gdacs_url(days: int = 30, today: Optional[_dt.date] = None) -> str:
    today = today or _dt.date.today()
    q = {"eventlist": "DR;FL;TC;EQ;VO;WF", "fromdate": (today - _dt.timedelta(days=days)).isoformat(),
         "todate": today.isoformat(), "alertlevel": "orange;red"}
    return "https://www.gdacs.org/gdacsapi/api/events/geteventlist/SEARCH?" + urllib.parse.urlencode(q)


def parse_gdacs(data: Dict) -> List[Dict]:
    out = []
    for f in data.get("features", []) or []:
        p = f.get("properties", {}) or {}
        coords = (f.get("geometry") or {}).get("coordinates") or [None, None]
        url = p.get("url") or {}
        link = (url.get("report") if isinstance(url, dict) else url) or \
            f"https://www.gdacs.org/report.aspx?eventtype={p.get('eventtype','')}&eventid={p.get('eventid','')}"
        sev = (p.get("severitydata") or {}).get("severitytext", "")
        title = p.get("name") or p.get("description") or ""
        out.append(_event("GDACS", title or "GDACS-riasztás",
                          KATEGORIA.get(p.get("eventtype", ""), "egyeb"), p.get("fromdate", ""), p.get("country", ""),
                          coords[1] if len(coords) > 1 else None, coords[0], link,
                          szint=str(p.get("alertlevel", "")).lower(), leiras=sev,
                          cim_en="" if title else "GDACS alert"))
    return out


# --- ReliefWeb ----------------------------------------------------------------
RELIEFWEB_THEMES = "drought OR famine OR \"food insecurity\" OR flood OR heatwave OR \"air pollution\" OR \"water contamination\" OR cholera OR glacier"


def reliefweb_body(limit: int = 40) -> Dict:
    return {"limit": limit, "sort": ["date.created:desc"], "query": {"value": RELIEFWEB_THEMES},
            "fields": {"include": ["title", "url", "date.created", "primary_country",  # v2: a .location alpontot nem fogadja el
                                   "source.shortname", "disaster_type.name", "theme.name"]}}


def _rw_category(f: Dict) -> str:
    text = " ".join([f.get("title", "")] + [d.get("name", "") for d in f.get("disaster_type", []) or []]).lower()
    for keys, kat in [(("famine", "food", "hunger", "malnutrition"), "ehezes"), (("drought",), "aszaly"),
                      (("flood", "landslide"), "arviz"), (("heat",), "hoseg"), (("cholera", "epidemic", "outbreak"), "jarvany"),
                      (("cyclone", "storm", "typhoon", "hurricane"), "vihar"), (("pollution", "contamina", "air quality"), "szennyezes"),
                      (("fire",), "tuz"), (("glacier", "ice", "snow"), "jeg")]:
        if any(k in text for k in keys):
            return kat
    return "egyeb"


def parse_reliefweb(data: Dict) -> List[Dict]:
    out = []
    for item in data.get("data", []) or []:
        f = item.get("fields", {}) or {}
        pc = f.get("primary_country") or {}
        if isinstance(pc, list):
            pc = pc[0] if pc else {}
        loc = pc.get("location") or {}
        src = ", ".join(s.get("shortname", "") for s in (f.get("source") or [])[:2])
        out.append(_event("ReliefWeb" + (f" / {src}" if src else ""), f.get("title", ""), _rw_category(f),
                          (f.get("date") or {}).get("created", ""), pc.get("name", ""),
                          loc.get("lat"), loc.get("lon"), f.get("url", "")))
    return out


# --- NASA EONET ---------------------------------------------------------------
EONET_URL = "https://eonet.gsfc.nasa.gov/api/v3/events?status=open&days=60&limit=150"


def parse_eonet(data: Dict) -> List[Dict]:
    out = []
    for e in data.get("events", []) or []:
        cats = e.get("categories") or [{}]
        geo = (e.get("geometry") or [{}])[-1]
        coords = geo.get("coordinates") or [None, None]
        if coords and isinstance(coords[0], list):  # poligon: az első pont
            while coords and isinstance(coords[0], list):
                coords = coords[0]
        srcs = e.get("sources") or []
        link = srcs[0].get("url") if srcs else e.get("link", "")
        out.append(_event("NASA EONET", e.get("title", ""), KATEGORIA.get(cats[0].get("id", ""), "egyeb"),
                          geo.get("date", ""), "", coords[1] if len(coords) > 1 else None, coords[0] if coords else None,
                          link or e.get("link", ""), leiras=e.get("description") or ""))
    return out


# --- NOAA CO2 -----------------------------------------------------------------
NOAA_CO2_URL = "https://gml.noaa.gov/webdata/ccgg/trends/co2/co2_mm_mlo.csv"


def parse_noaa_co2(text: str) -> Dict:
    rows = [r for r in csv.reader(io.StringIO(text)) if r and not r[0].startswith("#")]
    data = []
    for r in rows:
        try:
            y, m, avg = int(r[0]), int(r[1]), float(r[3])
        except (ValueError, IndexError):
            continue  # fejléc
        if avg > 0:
            data.append((y, m, avg))
    if not data:
        raise ValueError("Üres NOAA CO2-adatsor")
    y, m, v = data[-1]
    prev = [d for d in data if d[0] == y - 1 and d[1] == m]
    return {"azonosito": "co2_ppm", "cim": "CO2 a levegőben (Mauna Loa)", "ertek": round(v, 2), "egyseg": "ppm",
            "datum": f"{y}-{m:02d}", "valtozas_1_ev": round(v - prev[0][2], 2) if prev else None,
            "magyarazat": "Ennyi szén-dioxid-molekula jut egymillió levegőmolekulára. Az ipari forradalom előtt kb. 280 volt.",
            "cim_en": "CO2 in the air (Mauna Loa)",
            "magyarazat_en": "This many carbon dioxide molecules per million air molecules. Before the industrial revolution it was about 280.",
            "forras": "NOAA Global Monitoring Laboratory", "link": "https://gml.noaa.gov/ccgg/trends/"}


# --- NSIDC tengeri jég --------------------------------------------------------
NSIDC_URLS = ["https://noaadata.apps.nsidc.org/NOAA/G02135/north/daily/data/N_seaice_extent_daily_v4.0.csv",
              "https://noaadata.apps.nsidc.org/NOAA/G02135/north/daily/data/N_seaice_extent_daily_v3.0.csv"]


def parse_nsidc(text: str) -> Dict:
    rows = []
    for r in csv.reader(io.StringIO(text)):
        try:
            rows.append((int(r[0]), int(r[1]), int(r[2]), float(r[3])))
        except (ValueError, IndexError):
            continue  # fejléc és egység-sor
    if not rows:
        raise ValueError("Üres NSIDC-adatsor")
    y, m, d, ext = rows[-1]
    same_day = [x[3] for x in rows if x[1] == m and x[2] == d and 1981 <= x[0] <= 2010]
    avg = sum(same_day) / len(same_day) if same_day else None
    return {"azonosito": "arktisz_jeg", "cim": "Északi-sarki tengeri jég", "ertek": round(ext, 2), "egyseg": "millió km²",
            "datum": f"{y}-{m:02d}-{d:02d}", "atlag_1981_2010": round(avg, 2) if avg else None,
            "elteres_pct": round((ext - avg) / avg * 100, 1) if avg else None,
            "magyarazat": "Ekkora területet borít ma tengeri jég az Északi-sarkon, az 1981–2010-es átlaghoz képest.",
            "cim_en": "Arctic sea ice", "egyseg_en": "million km²",
            "magyarazat_en": "This is the area covered by sea ice in the Arctic today, compared with the 1981–2010 average.",
            "forras": "NSIDC Sea Ice Index (G02135)", "link": "https://nsidc.org/data/seaice_index"}


# --- Open-Meteo: levegő, UV, talajnedvesség ------------------------------------
def open_meteo_urls(cities=CITIES) -> Dict[str, str]:
    lats = ",".join(f"{c[1]:.2f}" for c in cities)
    lons = ",".join(f"{c[2]:.2f}" for c in cities)
    return {
        "levego": "https://air-quality-api.open-meteo.com/v1/air-quality?" + urllib.parse.urlencode(
            {"latitude": lats, "longitude": lons, "current": "pm2_5,pm10,nitrogen_dioxide,ozone,uv_index,european_aqi",
             "timezone": "UTC"}),
        "talaj": "https://api.open-meteo.com/v1/forecast?" + urllib.parse.urlencode(
            {"latitude": lats, "longitude": lons, "current": "soil_moisture_0_to_1cm,temperature_2m", "timezone": "UTC"}),
    }


def _as_list(data) -> List[Dict]:
    return data if isinstance(data, list) else [data]


def city_url(kind: str, lat: float, lon: float) -> str:
    """Egyetlen város lekérdezése: ezt a linket bárki megnyithatja ellenőrzésre."""
    return open_meteo_urls([("x", lat, lon)])[kind]


def parse_open_meteo_air(data, cities=CITIES) -> List[Dict]:
    out = []
    for (name, lat, lon), d in zip(cities, _as_list(data)):
        cur = d.get("current") or {}
        if cur.get("pm2_5") is None and cur.get("uv_index") is None:
            continue
        out.append({"varos": name, "varos_en": CITY_EN.get(name, name), "lat": lat, "lon": lon,
                    "ido": str(cur.get("time", "")), "pm2_5": cur.get("pm2_5"), "pm10": cur.get("pm10"), "no2": cur.get("nitrogen_dioxide"),
                    "ozon": cur.get("ozone"), "uv": cur.get("uv_index"), "eu_aqi": cur.get("european_aqi"),
                    "link": city_url("levego", lat, lon)})
    return out


def parse_open_meteo_soil(data, cities=CITIES) -> List[Dict]:
    out = []
    for (name, lat, lon), d in zip(cities, _as_list(data)):
        cur = d.get("current") or {}
        if cur.get("soil_moisture_0_to_1cm") is None:
            continue
        out.append({"varos": name, "varos_en": CITY_EN.get(name, name), "lat": lat, "lon": lon,
                    "ido": str(cur.get("time", "")), "talajnedvesseg": cur.get("soil_moisture_0_to_1cm"), "homerseklet": cur.get("temperature_2m"),
                    "link": city_url("talaj", lat, lon)})
    return out


def air_events(rows: List[Dict]) -> List[Dict]:
    """Csak a küszöb feletti értékekből lesz esemény (WHO-határok)."""
    ev = []
    for r in rows:
        country = ""
        try:
            from .geo import country_at
            country = country_at(r["lat"], r["lon"])
        except Exception:
            pass
        city_en = r.get("varos_en") or CITY_EN.get(r["varos"], r["varos"])
        pm = r.get("pm2_5")
        if pm is not None and pm >= 3 * WHO_PM25_24H:
            ev.append(_event(CAMS_FORRAS,
                             f"{r['varos']}: szennyezett levegő, PM2,5 = {pm:g} µg/m³ (a WHO 24 órás határa {WHO_PM25_24H:g})",
                             "levego", r["ido"], country, r["lat"], r["lon"], r["link"], szint="orange" if pm < 5 * WHO_PM25_24H else "red",
                             cim_en=f"{city_en}: polluted air, PM2.5 = {pm:g} µg/m³ (WHO 24-hour limit {WHO_PM25_24H:g})",
                             forras_en=CAMS_FORRAS_EN))
        uv = r.get("uv")
        if uv is not None and uv >= UV_VERY_HIGH:
            ev.append(_event(CAMS_FORRAS,
                             f"{r['varos']}: nagyon erős UV-sugárzás, UV-index = {uv:g}",
                             "uv", r["ido"], country, r["lat"], r["lon"], r["link"], szint="orange" if uv < 11 else "red",
                             cim_en=f"{city_en}: very strong UV radiation, UV index = {uv:g}", forras_en=CAMS_FORRAS_EN))
    return ev


def air_summary(rows: List[Dict]) -> Optional[Dict]:
    pm = [r for r in rows if r.get("pm2_5") is not None]
    if not pm:
        return None
    worst = max(pm, key=lambda r: r["pm2_5"])
    over = sum(1 for r in pm if r["pm2_5"] > WHO_PM25_24H)
    return {"azonosito": "levego_varosok", "cim": "Levegőminőség 30 nagyvárosban", "ertek": over, "egyseg": f"/ {len(pm)} város",
            "datum": worst["ido"][:16], "legrosszabb": worst["varos"],
            "legrosszabb_en": worst.get("varos_en") or CITY_EN.get(worst["varos"], worst["varos"]),
            "legrosszabb_pm2_5": worst["pm2_5"], "cim_en": f"Air quality in {len(CITIES)} large cities",
            "egyseg_en": f"/ {len(pm)} cities",
            "magyarazat": (f"{over} városban több a finom por (PM2,5), mint a WHO 24 órás határa ({WHO_PM25_24H:g} µg/m³). "
                           f"Most a legrosszabb: {worst['varos']}, {worst['pm2_5']:g} µg/m³. Modellbecslés, nem mérőállomás."),
            "magyarazat_en": (f"In {over} cities there is more fine dust (PM2.5) than the WHO 24-hour limit "
                              f"({WHO_PM25_24H:g} µg/m³). Worst right now: "
                              f"{worst.get('varos_en') or CITY_EN.get(worst['varos'], worst['varos'])}, {worst['pm2_5']:g} µg/m³. "
                              "Model estimate, not a monitoring station."),
            "forras": "Open-Meteo Air Quality API (Copernicus CAMS)", "link": worst["link"]}


# --- Összeállítás ----------------------------------------------------------------
def build(fetch: Callable[..., bytes] = _http, log=print, today: Optional[_dt.date] = None) -> Dict:
    world = {"letoltve": _dt.datetime.now(_dt.timezone.utc).isoformat(timespec="seconds"),
             "esemenyek": [], "meresek": [], "levego": [], "talaj": [], "idezett": CITED_FACTS, "forrasok": {}}

    def attempt(name, fn):
        try:
            n = fn()
            world["forrasok"][name] = {"ok": True, "uzenet": f"{n} tétel"}
            log(f"  {name}: {n} tétel")
        except Exception as e:
            world["forrasok"][name] = {"ok": False, "uzenet": str(e)[:200]}
            log(f"  {name}: NEM ÉRHETŐ EL ({e})")

    def gd():
        ev = parse_gdacs(json.loads(fetch(gdacs_url(today=today))))
        world["esemenyek"] += ev
        return len(ev)

    def rw():
        # A v1 API-t leállították (410 Gone); a v2 jóváhagyott appname-et kér
        # (AETHER_RELIEFWEB_APPNAME). A hiba okát változatlanul jelentjük.
        body = json.dumps(reliefweb_body()).encode()
        url = f"https://api.reliefweb.int/v2/reports?appname={RELIEFWEB_APPNAME}"
        try:
            raw = fetch(url, data=body)
        except Exception as e:
            if "403" in str(e):
                raise ConnectionError("ReliefWeb v2: HTTP 403 – nem jóváhagyott appname "
                                      f"('{RELIEFWEB_APPNAME}'); igényelj egyet: "
                                      "https://apidoc.reliefweb.int/parameters#appname, "
                                      "majd állítsd be: AETHER_RELIEFWEB_APPNAME") from e
            raise
        ev = parse_reliefweb(json.loads(raw))
        world["esemenyek"] += ev
        return len(ev)

    def eo():
        ev = parse_eonet(json.loads(fetch(EONET_URL)))
        world["esemenyek"] += ev
        return len(ev)

    def co2():
        world["meresek"].append(parse_noaa_co2(fetch(NOAA_CO2_URL).decode("utf-8", "replace")))
        return 1

    def ice():
        last = None
        for u in NSIDC_URLS:
            try:
                world["meresek"].append(parse_nsidc(fetch(u).decode("utf-8", "replace")))
                return 1
            except Exception as e:
                last = e
        raise ConnectionError(last)

    urls = open_meteo_urls()

    def air():
        rows = parse_open_meteo_air(json.loads(fetch(urls["levego"])))
        world["levego"] = rows
        world["esemenyek"] += air_events(rows)
        summ = air_summary(rows)
        if summ:
            world["meresek"].append(summ)
        return len(rows)

    def soil():
        rows = parse_open_meteo_soil(json.loads(fetch(urls["talaj"])))
        world["talaj"] = rows
        return len(rows)

    log("Valós adatok letöltése…")
    for name, fn in [("GDACS", gd), ("ReliefWeb", rw), ("NASA EONET", eo), ("NOAA CO2", co2), ("NSIDC jég", ice),
                     ("Levegő és UV (Open-Meteo/CAMS)", air), ("Talajnedvesség (Open-Meteo)", soil)]:
        attempt(name, fn)
    # hiányzó ország pótlása koordinátából (internet nélkül, GeoNames-adat)
    try:
        from .geo import country_at
        for e in world["esemenyek"]:
            if not e["orszag"] and e["lat"] is not None:
                e["orszag"] = country_at(e["lat"], e["lon"])
    except Exception as e:
        log(f"  Országkeresés kihagyva: {e}")
    # csak hellyel és linkkel rendelkező, egyedi események; legfrissebb elöl
    seen, clean = set(), []
    for e in sorted(world["esemenyek"], key=lambda e: e["datum"], reverse=True):
        key = (e["cim"].lower(), e["datum"])
        if e["link"] and key not in seen:
            seen.add(key)
            clean.append(e)
    world["esemenyek"] = clean
    return world


def cmd_vilag(args):
    from .godot_bridge import _write_json
    from pathlib import Path
    world = build()
    _write_json(Path(args.ki), world)
    ok = sum(1 for s in world["forrasok"].values() if s["ok"])
    print(f"{len(world['esemenyek'])} esemény, {len(world['meresek'])} mérés; {ok}/{len(world['forrasok'])} forrás elérhető.")


def add_parsers(sub):
    v = sub.add_parser("vilag", help="A Föld mai állapota valós forrásokból")
    v.add_argument("--ki", default="vilag.json")
    v.set_defaults(fn=cmd_vilag)
