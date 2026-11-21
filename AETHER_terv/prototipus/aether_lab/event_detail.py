"""Egy valós esemény (jelentés) részletei a játékosnak, érthetően.

A játékos a földgömbön vagy a listában egy eseményre kattint. Ez a parancs:
  1. letölti a hivatalos forrás oldalát (és GDACS esetén a gépi API-adatait),
  2. kiszedi belőle a szöveget és a fontos ábrákat (térképek, grafikonok),
  3. ha van AI, az 2-3 mondatban, a játékos nyelvén összefoglalja,
  4. a kiemelt számokat SZÓ SZERINT visszakeresi a forrás szövegében;
     ami nincs benne, azt kidobja (ugyanaz az elv, mint a kutatásnál).

AI nélkül is működik: ilyenkor a forrás saját adataiból (dátum, időtartam,
súlyosság, érintett országok) ír a játék egy egyszerű összefoglalót.

Használat:  python -m aether_lab esemeny-reszlet esemeny.json --mappa <dir> --ki reszlet.json
            [--ai none|ollama|claude|openai|gemini] [--nyelv hu|en]
"""
from __future__ import annotations

import datetime as _dt
import hashlib
import html as _html
import json
import os
import re
import urllib.parse
from pathlib import Path
from typing import Callable, Dict, List, Optional

from .evidence import _norm_text, numbers_in

MAX_TEXT = 8000          # ennyi karakter megy az AI-nak
MAX_IMAGES = 4
MAX_IMAGE_BYTES = 4_000_000
IMG_EXT = (".png", ".jpg", ".jpeg", ".webp")
IMG_SKIP = ("logo", "icon", "flag", "banner", "sprite", "button", "arrow", "spacer", "pixel", "avatar",
            "favicon", "social", "twitter", "facebook", "linkedin", "youtube", "loading", "badge")

SUMMARY_SCHEMA = {
    "type": "object",
    "properties": {
        "osszegzes": {"type": "string"},
        "miert_fontos": {"type": "string"},
        "fobb_szamok": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {"ertek": {"type": "string"}, "jelentes": {"type": "string"},
                               "idezet": {"type": "string"}},
                "required": ["ertek", "jelentes", "idezet"],
                "additionalProperties": False,
            },
        },
    },
    "required": ["osszegzes", "miert_fontos", "fobb_szamok"],
    "additionalProperties": False,
}

SUMMARY_SYSTEM = """Egy hivatalos katasztrófa- vagy környezeti jelentést foglalsz össze egy
klímajáték játékosának, aki nem szakember. Szabályok:
- CSAK a megadott forrásszövegben szereplő tényeket használd. Ne egészítsd ki saját tudással,
  ne becsülj, ne jósolj.
- Az 'osszegzes' 2-3 rövid, hétköznapi mondat a megadott nyelven: mi történik, hol, mióta,
  mekkora a baj. Ne sorold fel az összes országot: írd, hogy hány ország érintett, és nevezz meg
  legfeljebb 3-at.
- A 'miert_fontos' 2-3 hétköznapi mondat: miért számít ez az embereknek és a természetnek, és
  hogyan kapcsolódik a klímaváltozáshoz. Ez általános magyarázat: NE írj bele számot. Legyél
  őszinte: ha az esemény nem klímaesemény (pl. földrengés, vulkán), mondd ki; ha a kapcsolat
  bizonytalan (egyetlen esemény nem bizonyítja a klímaváltozást), azt is.
- A 'fobb_szamok' legfeljebb 4 fontos szám a szövegből (pl. időtartam, terület, érintett emberek).
  Az 'idezet' a forrásszöveg SZÓ SZERINTI részlete (eredeti nyelven), amely a számot tartalmazza.
  A 'jelentes' egy rövid magyarázat a megadott nyelven. Ha nincs ilyen szám, adj üres listát."""


# AI nélküli "Miért fontos?" kategóriánként. Csak általános, forrással alátámasztott
# állítások (IPCC AR6 WGI döntéshozói összefoglaló, 2021; WHO), számok nélkül.
IPCC_SPM = ("IPCC AR6 WGI, döntéshozói összefoglaló (2021)", "IPCC AR6 WGI, Summary for Policymakers (2021)",
            "https://www.ipcc.ch/report/ar6/wg1/chapter/summary-for-policymakers/")
WHO_AIR = ("WHO, levegőminőség és egészség", "WHO, ambient air quality and health",
           "https://www.who.int/news-room/fact-sheets/detail/ambient-(outdoor)-air-quality-and-health")
WHO_UV = ("WHO, ultraibolya sugárzás", "WHO, ultraviolet radiation",
          "https://www.who.int/news-room/fact-sheets/detail/ultraviolet-radiation")
WHY = {
    "aszaly": ("Az aszály csökkenti a termést és a vízkészletet. Az IPCC szerint az emberi hatású melegedés egyes "
               "régiókban hozzájárult a mezőgazdasági aszályok gyakoribbá válásához.",
               "Drought reduces harvests and water supplies. According to the IPCC, human-caused warming has "
               "contributed to more agricultural droughts in some regions.", IPCC_SPM),
    "arviz": ("Az árvíz otthonokat, termést és utakat tesz tönkre. Az IPCC szerint a legtöbb szárazföldi térségben "
              "gyakoribbak és hevesebbek lettek a nagy esőzések, és ebben fő szerepe van az emberi hatásnak.",
              "Floods destroy homes, crops and roads. According to the IPCC, heavy rainfall has become more frequent "
              "and intense over most land areas, mainly because of human influence.", IPCC_SPM),
    "hoseg": ("A hőség veszélyes az egészségre, főleg az idősekre. Az IPCC szerint a hőhullámok szinte biztosan "
              "gyakoribbak és erősebbek lettek, főleg az emberi hatás miatt.",
              "Heat is dangerous to health, especially for older people. According to the IPCC, heatwaves have "
              "almost certainly become more frequent and intense, mainly because of human influence.", IPCC_SPM),
    "vihar": ("A trópusi viharok szélvihart, áradást és tengerszint-emelkedést hoznak. Az IPCC szerint az utóbbi "
              "évtizedekben valószínűleg nőtt a legerősebb viharok aránya.",
              "Tropical storms bring wind, flooding and storm surges. According to the IPCC, the share of the "
              "strongest storms has likely increased in recent decades.", IPCC_SPM),
    "tuz": ("Az erdőtűz élőhelyeket és otthonokat pusztít, a füstje egészségkárosító. Az IPCC szerint egyes "
            "régiókban gyakoribb lett a tűzveszélyes időjárás.",
            "Wildfires destroy habitats and homes, and the smoke harms health. According to the IPCC, fire weather "
            "has become more frequent in some regions.", IPCC_SPM),
    "jeg": ("A jég fogyása emeli a tengerszintet és változtatja az óceánokat. Jéghegyek természetes módon is "
            "leválnak, egyetlen eseményből nem lehet a klímára következtetni. Az IPCC szerint a gleccserek "
            "visszahúzódásának fő oka nagyon valószínűleg az emberi hatás.",
            "Melting ice raises sea levels and changes the oceans. Icebergs also break off naturally, so one event "
            "says little about the climate. According to the IPCC, human influence is very likely the main driver "
            "of glacier retreat.", IPCC_SPM),
    "foldrenges": ("Ez nem klímaesemény: a földrengést a kéreg mozgása okozza, nem a melegedés. Azért látod, mert "
                   "a katasztrófák az embereket is sújtják, és a segítséghez erőforrás kell.",
                   "This is not a climate event: earthquakes come from movements of the Earth's crust, not from "
                   "warming. You see it because disasters hit people and recovery needs resources.", None),
    "vulkan": ("Ez nem klímaesemény: a vulkánkitörést a Föld belső folyamatai okozzák. Nagy kitörések rövid időre "
               "lehűthetik a Földet, de ez nem a klímaváltozás jele.",
               "This is not a climate event: eruptions are caused by processes inside the Earth. Large eruptions "
               "can cool the planet briefly, but they are not a sign of climate change.", None),
    "levego": ("A szennyezett levegő az egyik legnagyobb egészségügyi kockázat: szív- és tüdőbetegségeket okoz. "
               "Sok forrása (szén, olaj, égetés) a klímát is melegíti.",
               "Polluted air is one of the biggest health risks: it causes heart and lung disease. Many of its "
               "sources (coal, oil, burning) also warm the climate.", WHO_AIR),
    "uv": ("Az erős UV-sugárzás leégést, bőrrákot és szemkárosodást okozhat. Ilyenkor érdemes árnyékban maradni.",
           "Strong UV radiation can cause sunburn, skin cancer and eye damage. It is wise to stay in the shade.",
           WHO_UV),
}


# ---------------------------------------------------------------------------
# HTML -> szöveg és képek
# ---------------------------------------------------------------------------
_DROP_BLOCKS = re.compile(r"<(script|style|noscript|nav|header|footer|svg|form)\b.*?</\1\s*>", re.S | re.I)
_TAG = re.compile(r"<[^>]+>")
_BLOCK_END = re.compile(r"</(p|div|li|tr|h[1-6]|td|th|section|article)\s*>|<br\s*/?>", re.I)


def html_text(page: str) -> str:
    s = _DROP_BLOCKS.sub(" ", page or "")
    s = _BLOCK_END.sub("\n", s)
    s = _html.unescape(_TAG.sub(" ", s))
    lines = [" ".join(l.split()) for l in s.splitlines()]
    return "\n".join(l for l in lines if len(l) > 1)


_IMG = re.compile(r"<img\b[^>]*>", re.I)
_ATTR = re.compile(r'([a-zA-Z_:-]+)\s*=\s*("([^"]*)"|\'([^\']*)\')')
_OG = re.compile(r'<meta[^>]+(?:property|name)\s*=\s*["\'](?:og:image|twitter:image)["\'][^>]*>', re.I)


def _attrs(tag: str) -> Dict[str, str]:
    return {m.group(1).lower(): _html.unescape(m.group(3) if m.group(3) is not None else (m.group(4) or ""))
            for m in _ATTR.finditer(tag)}


def html_images(page: str, base_url: str) -> List[Dict]:
    """A tartalomhoz tartozó képek (térkép, grafikon), a díszítő elemek nélkül."""
    out, seen = [], set()

    def add(src: str, alt: str, w: str = "", h: str = ""):
        if not src or src.startswith("data:"):
            return
        url = urllib.parse.urljoin(base_url, src)
        path = urllib.parse.urlparse(url).path.lower()
        if not path.endswith(IMG_EXT) or any(k in path for k in IMG_SKIP):
            return
        try:
            if (w and int(w) < 150) or (h and int(h) < 100):
                return  # apró ikon
        except ValueError:
            pass
        if url not in seen:
            seen.add(url)
            out.append({"url": url, "alt": " ".join((alt or "").split())[:200]})

    for tag in _OG.findall(page or ""):
        add(_attrs(tag).get("content", ""), "")
    for tag in _IMG.findall(page or ""):
        a = _attrs(tag)
        add(a.get("src") or a.get("data-src", ""), a.get("alt", "") or a.get("title", ""), a.get("width", ""),
            a.get("height", ""))
    return out


# ---------------------------------------------------------------------------
# GDACS: gépi adatok az esemény API-jából
# ---------------------------------------------------------------------------
def gdacs_api_url(link: str) -> Optional[str]:
    q = urllib.parse.parse_qs(urllib.parse.urlparse(link or "").query)
    low = {k.lower(): v[0] for k, v in q.items() if v}
    if "eventtype" in low and "eventid" in low:
        return ("https://www.gdacs.org/gdacsapi/api/events/geteventdata?"
                + urllib.parse.urlencode({"eventtype": low["eventtype"], "eventid": low["eventid"]}))
    return None


def _days(a: str, b: str) -> Optional[int]:
    try:
        d1 = _dt.datetime.fromisoformat(a[:19])
        d2 = _dt.datetime.fromisoformat(b[:19])
        return max(0, (d2 - d1).days)
    except (TypeError, ValueError):
        return None


def gdacs_facts(data: Dict, lang: str = "hu") -> List[Dict]:
    """Tények a GDACS API válaszából (a forrás saját adatai, nem AI)."""
    en = lang.startswith("en")
    p = data.get("properties", data) if isinstance(data, dict) else {}
    facts = []

    def f(hu, eng, v):
        if v not in (None, "", []):
            facts.append({"nev": eng if en else hu, "ertek": str(v)})

    f("Riasztási szint", "Alert level", {"red": "piros", "orange": "narancs", "green": "zöld"}.get(
        str(p.get("alertlevel", "")).lower(), p.get("alertlevel")) if not en else str(p.get("alertlevel", "")).lower())
    sev = (p.get("severitydata") or {}).get("severitytext")
    f("Súlyosság (a forrás szerint)", "Severity (according to the source)", sev)
    f("Kezdete", "Start", str(p.get("fromdate", ""))[:10])
    f("Utolsó adat", "Latest data", str(p.get("todate", ""))[:10])
    d = _days(str(p.get("fromdate", "")), str(p.get("todate", "")))
    if d:
        f("Időtartam", "Duration", f"{d} nap" if not en else f"{d} days")
    countries = [c.get("countryname", "") for c in (p.get("affectedcountries") or []) if isinstance(c, dict)]
    countries = [c for c in countries if c] or [c.strip() for c in str(p.get("country", "")).split(",") if c.strip()]
    if countries:
        f("Érintett országok", "Affected countries", f"{len(countries)}: " + ", ".join(countries))
    return facts


# ---------------------------------------------------------------------------
# Összefoglaló
# ---------------------------------------------------------------------------
def verify_numbers(items: List[Dict], text: str) -> List[Dict]:
    """Csak az marad, aminek az idézete szó szerint benne van a forrásban, és a szám is az idézetben."""
    norm = _norm_text(text)
    ok = []
    for it in items or []:
        q = _norm_text(it.get("idezet", ""))
        nums = numbers_in(it.get("ertek", ""))
        if len(q) >= 8 and q in norm and nums and all(n in numbers_in(q) for n in nums):
            ok.append(it)
    return ok


def plain_summary(event: Dict, facts: List[Dict], lang: str = "hu") -> str:
    """AI nélküli, a forrás adataiból összerakott egyszerű összefoglaló."""
    en = lang.startswith("en")
    countries = [c.strip() for c in str(event.get("orszag", "")).split(",") if c.strip()]
    where = ""
    if len(countries) > 3:
        where = (f" in {len(countries)} countries, including {', '.join(countries[:3])}" if en
                 else f" {len(countries)} országban, például: {', '.join(countries[:3])}")
    elif countries:
        where = (" in " if en else ": ") + ", ".join(countries)
    src = event.get("forras", "")
    s = (f"{src} reports{where}." if en else f"A(z) {src} jelentése{where}.")
    sev = next((x["ertek"] for x in facts if x["nev"].startswith(("Súlyosság", "Severity"))), "")
    dur = next((x["ertek"] for x in facts if x["nev"] in ("Időtartam", "Duration")), "")
    if dur:
        s += f" It has lasted {dur} so far." if en else f" Már {dur} óta tart."
    if sev:
        s += (f" The source's own assessment: “{sev}”." if en else f" A forrás saját értékelése (angolul): „{sev}”.")
    return s


def build(event: Dict, folder: Path, fetch: Callable[..., bytes], provider=None, lang: str = "hu",
          log=print) -> Dict:
    en = lang.startswith("en")
    link = str(event.get("link", ""))
    res = {"link": link, "forras": event.get("forras", ""), "cim": event.get("cim", ""), "kepek": [],
           "tenyek": [], "osszegzes": "", "miert_fontos": "", "osszegzes_tipus": "nincs", "fobb_szamok": [], "megjegyzes": ""}
    text = str(event.get("leiras", "") or "")
    page = ""
    if link.startswith("http"):
        try:
            page = fetch(link).decode("utf-8", "replace")
            text = (text + "\n" + html_text(page)).strip()
        except Exception as e:
            res["megjegyzes"] = (f"The source page could not be downloaded: {e}" if en
                                 else f"A forrás oldala nem tölthető le: {e}")
    api = gdacs_api_url(link) if "gdacs" in link.lower() else None
    if api:
        try:
            data = json.loads(fetch(api))
            res["tenyek"] = gdacs_facts(data, lang)
            p = data.get("properties", {}) if isinstance(data, dict) else {}
            extra = " ".join(str(p.get(k, "")) for k in ("name", "description", "htmldescription") if p.get(k))
            text = (html_text(extra) + "\n" + text).strip()
            for k in ("images", "imagesurl"):
                v = p.get(k)
                if isinstance(v, str) and v.startswith("http"):
                    res.setdefault("_kep_oldalak", []).append(v)
        except Exception as e:
            log(f"GDACS API: {e}")

    # képek letöltése a gép gyorsítótárába
    folder.mkdir(parents=True, exist_ok=True)
    for im in html_images(page, link)[: MAX_IMAGES * 3]:
        if len(res["kepek"]) >= MAX_IMAGES:
            break
        try:
            raw = fetch(im["url"])
            if len(raw) > MAX_IMAGE_BYTES or len(raw) < 3000:
                continue  # túl nagy, vagy túl kicsi (ikon)
            ext = os.path.splitext(urllib.parse.urlparse(im["url"]).path)[1].lower() or ".png"
            name = hashlib.sha1(im["url"].encode()).hexdigest()[:16] + ext
            (folder / name).write_bytes(raw)
            res["kepek"].append({"fajl": str(folder / name), "url": im["url"], "alt": im["alt"]})
        except Exception as e:
            log(f"kép: {im['url']}: {e}")
    res.pop("_kep_oldalak", None)

    # összefoglaló
    if provider is not None and len(text) > 40:
        try:
            lang_name = "English" if en else "magyar"
            user = (f"Nyelv: {lang_name}\nEsemény: {event.get('cim', '')}\nForrás: {res['forras']}\n\n"
                    f"<forrasszoveg>\n{text[:MAX_TEXT]}\n</forrasszoveg>")
            raw = provider.json_call(SUMMARY_SYSTEM, user, SUMMARY_SCHEMA, 2000)
            res["osszegzes"] = str(raw.get("osszegzes", "")).strip()
            res["miert_fontos"] = str(raw.get("miert_fontos", "")).strip()
            res["fobb_szamok"] = verify_numbers(raw.get("fobb_szamok", []), text[:MAX_TEXT])
            res["osszegzes_tipus"] = "ai"
        except Exception as e:
            res["megjegyzes"] = (res["megjegyzes"] + " " + (f"AI summary failed: {e}" if en
                                 else f"Az AI-összefoglaló nem sikerült: {e}")).strip()
    if not res["osszegzes"]:
        res["osszegzes"] = plain_summary(event, res["tenyek"], lang)
        res["osszegzes_tipus"] = "forras"
    if not res["miert_fontos"] and event.get("kategoria") in WHY:
        hu_t, en_t, src = WHY[event["kategoria"]]
        res["miert_fontos"] = en_t if en else hu_t
        if src:
            res["miert_forras"] = {"nev": src[1] if en else src[0], "link": src[2]}
    return res


def cmd_reszlet(args):
    from .world_state import _http
    from .llm import get_provider
    event = json.loads(Path(args.esemeny).read_text(encoding="utf-8"))
    provider = None
    note = ""
    if args.ai != "none":
        try:
            provider = get_provider(args.ai)
        except Exception as e:  # pl. nincs kulcs: AI nélkül folytatjuk
            note = str(e)
    res = build(event, Path(args.mappa), _http, provider, args.nyelv)
    if note:
        res["megjegyzes"] = (res["megjegyzes"] + " " + note).strip()
    out = Path(args.ki)
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(".tmp")
    tmp.write_text(json.dumps(res, ensure_ascii=False, indent=1), encoding="utf-8")
    os.replace(tmp, out)


def add_parsers(sub):
    p = sub.add_parser("esemeny-reszlet", help="egy valós esemény érthető összefoglalója ábrákkal")
    p.add_argument("esemeny", help="az esemény JSON-fájlja (a vilag.json egy eleme)")
    p.add_argument("--mappa", required=True, help="ide kerülnek a letöltött ábrák")
    p.add_argument("--ki", required=True)
    p.add_argument("--ai", default="none", choices=["claude", "openai", "gemini", "ollama", "none"])
    p.add_argument("--nyelv", default="hu", choices=["hu", "en"])
    p.set_defaults(fn=cmd_reszlet)
