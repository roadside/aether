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
MIN_IMAGE_BYTES = 8_000  # ennél kisebb kép szinte mindig logó vagy ikon
MIN_SOURCE_CHARS = 300   # ennél kevesebb érdemi szövegből az AI nem foglal össze (kitalálna)
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
- Helyet (országot, tengert, várost, régiót) és számot CSAK akkor írj, ha szó szerint szerepel a
  forrásszövegben vagy az esemény adataiban. Ha a hely nem derül ki, ne nevezz meg helyet.
- Az 'osszegzes' 1-2 rövid, hétköznapi mondat a megadott nyelven: mi történik, hol, mekkora a baj.
  Ne sorold fel az országokat: írd, hány ország érintett, és nevezz meg legfeljebb 2-t.
- A 'miert_fontos' 2-5 rövid, hétköznapi mondat: miért számít ez az embereknek és a természetnek, és
  hogyan kapcsolódik a klímaváltozáshoz. Csak biztos, általánosan elfogadott tudást írj; ha nem tudsz
  többet, maradj rövid. Ez általános magyarázat: NE írj bele számot. Legyél
  őszinte: ha az esemény nem klímaesemény (pl. földrengés, vulkán), mondd ki; ha a kapcsolat
  bizonytalan (egyetlen esemény nem bizonyítja a klímaváltozást), azt is.
- A 'fobb_szamok' legfeljebb 3 fontos szám a szövegből (pl. időtartam, terület, érintett emberek).
  Az 'idezet' a forrásszöveg SZÓ SZERINTI részlete (eredeti nyelven), amely a számot tartalmazza.
  A 'jelentes' egy rövid magyarázat a megadott nyelven. Ha nincs ilyen szám, adj üres listát."""


# "Miért fontos?" kategóriánként: bővebb, tagolt magyarázat (legfeljebb kb. 15 sor). Minden állítás a
# megadott forrásból van (IPCC AR6 WGI döntéshozói összefoglaló, 2021; WHO-tájékoztatók, 2022/2024),
# ellenőrizve 2026-11-21-én. Ha egy kategóriához van ilyen szöveg, ez jelenik meg, nem az AI-é.
IPCC_SPM = ("IPCC AR6 WGI, döntéshozói összefoglaló (2021)", "IPCC AR6 WGI, Summary for Policymakers (2021)",
            "https://www.ipcc.ch/report/ar6/wg1/chapter/summary-for-policymakers/")
WHO_AIR = ("WHO, levegőminőség és egészség", "WHO, ambient air quality and health",
           "https://www.who.int/news-room/fact-sheets/detail/ambient-(outdoor)-air-quality-and-health")
WHO_UV = ("WHO, ultraibolya sugárzás", "WHO, ultraviolet radiation",
          "https://www.who.int/news-room/fact-sheets/detail/ultraviolet-radiation")
WHY = {
    'aszaly': ('Az aszály csökkenti a termést, kiszárítja a talajt és fogyasztja a vízkészleteket. A gazdák bevétele csökken, a háziállatoknak kevesebb a takarmány, és a városok ivóvízellátása is veszélybe kerülhet.\nAz IPCC szerint az emberi hatású klímaváltozás egyes régiókban hozzájárult a mezőgazdasági és ökológiai aszályok gyakoribbá válásához, mert a melegebb levegő több vizet párologtat el a talajból (közepes bizonyosság).\nA jövőről: minden további fél fok melegedéssel egyes régiókban jól kimutathatóan gyakoribbak és erősebbek lesznek az aszályok (magas bizonyosság).\nFontos: egyetlen aszályból nem lehet a klímaváltozásra következtetni, csak sok év adatából.',
        'Drought cuts harvests, dries out soils and depletes water supplies. Farmers lose income, livestock have less fodder, and city drinking water can be at risk.\nAccording to the IPCC, human-caused climate change has contributed to more agricultural and ecological droughts in some regions, because warmer air draws more water from the soil (medium confidence).\nLooking ahead: with every additional half degree of warming, droughts become clearly more frequent and intense in some regions (high confidence).\nNote: a single drought does not prove climate change; only many years of data can show a trend.',
        IPCC_SPM),
    'arviz': ('Az árvíz otthonokat, termést, utakat és hidakat tesz tönkre, és szennyezheti az ivóvizet.\nAz IPCC szerint az 1950-es évek óta a szárazföldek nagy részén gyakoribbak és hevesebbek lettek a nagy esőzések (magas bizonyosság), és ennek valószínűleg az emberi hatású klímaváltozás a fő oka.\nMiért? A melegebb levegő több vízgőzt tud tartani: az IPCC szerint a szélsőséges napi csapadék minden 1 °C melegedéssel kb. 7%-kal erősödik.\nA jövőről: nagyon valószínű, hogy további melegedéssel a legtöbb régióban még hevesebbek és gyakoribbak lesznek a nagy esőzések.\nFontos: az árvíz kárát az is meghatározza, hol építkezünk és milyen a gátak, csatornák állapota.',
        'Floods destroy homes, crops, roads and bridges, and can contaminate drinking water.\nAccording to the IPCC, heavy rainfall has become more frequent and intense over most land areas since the 1950s (high confidence), and human-caused climate change is likely the main driver.\nWhy? Warmer air can hold more water vapour: the IPCC says extreme daily rainfall intensifies by about 7% for each 1 °C of warming.\nLooking ahead: it is very likely that heavy rainfall will become even more intense and frequent in most regions with further warming.\nNote: flood damage also depends on where we build and on the state of dams and drainage.',
        IPCC_SPM),
    'hoseg': ('A hőség veszélyes az egészségre, főleg az idősekre, a kisgyerekekre és a szabadban dolgozókra.\nAz IPCC szerint szinte biztos, hogy az 1950-es évek óta a legtöbb szárazföldi térségben gyakoribbak és erősebbek lettek a hőhullámok, és ennek fő oka az emberi hatású klímaváltozás (magas bizonyosság).\nA tengerekben is: a tengeri hőhullámok az 1980-as évek óta nagyjából kétszer olyan gyakoriak lettek.\nA jövőről: minden további fél fok melegedéssel jól kimutathatóan erősebbek és gyakoribbak lesznek a hőhullámok (nagyon valószínű). A ritka, szélsőséges hőségek gyakorisága nő a legnagyobb arányban.',
        'Heat is dangerous to health, especially for older people, small children and outdoor workers.\nAccording to the IPCC, it is virtually certain that heatwaves have become more frequent and intense over most land areas since the 1950s, and human-caused climate change is the main driver (high confidence).\nAt sea too: marine heatwaves have roughly doubled in frequency since the 1980s.\nLooking ahead: every additional half degree of warming brings clearly more intense and frequent heatwaves (very likely). The rarest extremes increase the most in frequency.',
        IPCC_SPM),
    'vihar': ('A trópusi viharok (hurrikán, tájfun, ciklon) pusztító szelet, özönvízszerű esőt és a partokon vihardagályt hoznak. A tengerszint emelkedése miatt a vihardagály egyre magasabbra ér.\nAz IPCC szerint valószínű, hogy az utóbbi négy évtizedben nőtt a nagy erejű (3–5. kategóriájú) viharok aránya, és ez a természetes ingadozással önmagában nem magyarázható (közepes bizonyosság).\nA jövőről: a legerősebb (4–5. kategóriájú) viharok aránya és a legerősebb szelek sebessége a melegedéssel tovább nő (magas bizonyosság).\nFontos: nem feltétlenül lesz több vihar összesen, de a legerősebbek aránya nő.',
        'Tropical storms (hurricanes, typhoons, cyclones) bring destructive winds, torrential rain and storm surges on coasts. Because of sea-level rise, storm surges reach higher.\nAccording to the IPCC, the share of major (Category 3–5) storms has likely increased over the last four decades, and this cannot be explained by natural variability alone (medium confidence).\nLooking ahead: the share of the strongest (Category 4–5) storms and their peak wind speeds will increase with warming (high confidence).\nNote: there may not be more storms in total, but a larger share of them will be very strong.',
        IPCC_SPM),
    'tuz': ('Az erdőtűz élőhelyeket, otthonokat és termést pusztít, a füstje pedig messze elszállva is egészségkárosító. Az égő erdő szén-dioxidot bocsát ki, ami tovább melegíti a klímát.\nAz IPCC szerint az emberi hatás valószínűleg növelte a tűzveszélyes időjárás (forróság, szárazság, szél együtt) esélyét minden lakott kontinens egyes régióiban (közepes bizonyosság).\nA jövőről: 2 °C és afölötti melegedésnél több régióban nő a tűzveszélyes időjárás.\nFontos: a tüzek keletkezését és terjedését az emberi tevékenység és az erdőgazdálkodás is befolyásolja; a klíma a tűzveszélyes időjárást teszi gyakoribbá.',
        'Wildfires destroy habitats, homes and crops, and the smoke harms health even far away. Burning forests release carbon dioxide, which warms the climate further.\nAccording to the IPCC, human influence has likely increased the chance of fire weather (heat, drought and wind together) in some regions of every inhabited continent (medium confidence).\nLooking ahead: at 2 °C of warming and above, fire weather increases in more regions.\nNote: how fires start and spread also depends on human activity and forest management; climate makes fire weather more common.',
        IPCC_SPM),
    'jeg': ('A szárazföldi jég (gleccserek, jégtakarók) olvadása emeli a tengerszintet, a tengeri jég fogyása pedig a sarkvidéki élővilágot és az óceánt változtatja meg.\nAz IPCC szerint a gleccserek 1990-es évek óta tartó visszahúzódásának fő oka nagyon valószínűleg az emberi hatás. Az északi-sarki tengeri jég 2011–2020-ban a legkisebb volt legalább 1850 óta; szeptemberben kb. 40%-kal kevesebb, mint 1979–1988-ban.\nA tengerszint 1901 és 2018 között kb. 20 cm-t emelkedett, és egyre gyorsabban nő: 2006–2018-ban évi kb. 3,7 mm volt.\nFontos: a jéghegyek természetes módon is leválnak; egyetlen jéghegyből nem lehet a klímára következtetni. Az Antarktisz jégvesztésében az emberi hatásra még kevés a bizonyíték.',
        'Melting land ice (glaciers, ice sheets) raises sea levels, and shrinking sea ice changes Arctic life and the ocean.\nAccording to the IPCC, human influence is very likely the main driver of the global retreat of glaciers since the 1990s. Arctic sea ice in 2011–2020 was at its lowest since at least 1850; in September about 40% less than in 1979–1988.\nSea level rose by about 20 cm between 1901 and 2018, and it is rising faster: about 3.7 mm per year in 2006–2018.\nNote: icebergs also break off naturally; one iceberg says little about the climate. Evidence of human influence on Antarctic ice loss is still limited.',
        IPCC_SPM),
    'foldrenges': ('Ez nem klímaesemény: a földrengést a kéreg mozgása okozza, nem a melegedés. Azért látod, mert a katasztrófák az embereket is sújtják, és a segítséghez erőforrás kell.',
        "This is not a climate event: earthquakes come from movements of the Earth's crust, not from warming. You see it because disasters hit people and recovery needs resources.",
        None),
    'vulkan': ('Ez nem klímaesemény: a vulkánkitörést a Föld belső folyamatai okozzák. Nagy kitörések rövid időre lehűthetik a Földet, de ez nem a klímaváltozás jele.',
        'This is not a climate event: eruptions are caused by processes inside the Earth. Large eruptions can cool the planet briefly, but they are not a sign of climate change.',
        None),
    'levego': ('Mit jelent? A PM2,5 a 2,5 mikrométernél kisebb porszemcsék mennyisége a levegőben. Olyan aprók, hogy mélyen a tüdőbe jutnak, és onnan a véráramba is.\nEgészség: a WHO szerint a kültéri légszennyezés 2019-ben a becslések szerint 4,2 millió ember korai halálát okozta. Ezek kb. 68%-a szívbetegség és stroke, 14% krónikus tüdőbetegség, 14% alsó légúti fertőzés, 4% tüdőrák. A korai halálesetek 89%-a alacsony és közepes jövedelmű országokban történt.\nUgyanebben az évben a világ népességének 99%-a olyan helyen élt, ahol a levegő nem felelt meg a WHO irányértékeinek.\nHonnan jön? A WHO szerint főleg a közlekedésből (különösen a dízel járművekből), az áramtermelésből, az iparból, a szilárd tüzelős főzésből és fűtésből, valamint a hulladékégetésből.\nMi köze a klímához? Ezek nagy része fosszilis tüzelőanyag (szén, olaj, gáz) égetése, ami a CO2-kibocsátás fő forrása is. A tisztább áramtermelés, közlekedés és az energiahatékony épületek ezért egyszerre védik az egészséget és a klímát.',
        "What does it mean? PM2.5 is the amount of dust particles smaller than 2.5 micrometres in the air. They are so small that they get deep into the lungs and from there into the bloodstream.\nHealth: according to WHO, outdoor air pollution caused an estimated 4.2 million premature deaths in 2019. About 68% of these were heart disease and stroke, 14% chronic lung disease, 14% lower respiratory infections and 4% lung cancer. 89% of the premature deaths occurred in low- and middle-income countries.\nIn the same year, 99% of the world's population lived in places where the air did not meet WHO guideline levels.\nWhere does it come from? According to WHO, mainly from transport (especially diesel vehicles), power generation, industry, cooking and heating with solid fuels, and waste burning.\nWhat does it have to do with the climate? Much of this is burning fossil fuels (coal, oil, gas), which is also the main source of CO2 emissions. Cleaner power, transport and energy-efficient buildings therefore protect both health and the climate.",
        WHO_AIR),
    'uv': ('Mit jelent? Az UV-index azt mutatja, mennyire károsítja a napsugárzás a bőrt és a szemet: minél magasabb, annál nagyobb a veszély. A WHO szerint már 3-as indextől védekezni kell.\nEgészség: rövid távon leégés és szemgyulladás, hosszú távon bőröregedés, bőrrák (köztük melanóma) és szürkehályog. A WHO szerint 2020-ban világszerte több mint 1,5 millió bőrrákot diagnosztizáltak, és több mint 120 000 haláleset kapcsolódott hozzá. A szürkehályog miatti vakság kb. 10%-a az UV-sugárzásnak tudható be.\nVédekezés: déli órákban árnyék, testet takaró ruha, széles karimájú kalap, UV-szűrős napszemüveg, a szabadon maradó bőrre széles spektrumú naptej. A szolárium növeli a bőrrák kockázatát.\nMi köze a klímához? Kevesebb ózon mellett több UV éri el a felszínt. A WHO szerint a klímaváltozás az ózonon és a felhőzeten keresztül várhatóan hatással lesz a felszíni UV-szintre.\nFontos: kis mennyiségű napfény hasznos is, mert ettől termel a szervezet D-vitamint.',
        'What does it mean? The UV index shows how much sunlight can damage skin and eyes: the higher it is, the greater the danger. WHO recommends protection from UV index 3 upwards.\nHealth: in the short term sunburn and eye inflammation; in the long term skin ageing, skin cancer (including melanoma) and cataract. According to WHO, over 1.5 million skin cancers were diagnosed worldwide in 2020, and over 120,000 deaths were associated with them. About 10% of blindness from cataract may be due to UV.\nProtection: shade around midday, covering clothes, a wide-brimmed hat, UV-blocking sunglasses and broad-spectrum sunscreen on exposed skin. Sunbeds increase the risk of skin cancer.\nWhat does it have to do with the climate? With less ozone, more UV reaches the ground. WHO says climate change, through ozone and cloud cover, is expected to affect UV levels at the surface.\nNote: a little sunlight is good for you, because the body needs it to make vitamin D.',
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


_ARRAYMAPS = re.compile(r"var\s+arraymaps\s*=\s*(\[.*?\])\s*;", re.S)
_MAP_ITEM = re.compile(r'["\']?title["\']?\s*:\s*["\']([^"\']*)["\'][^}]*?["\']?image["\']?\s*:\s*["\']([^"\']+)["\']', re.S)


def gdacs_images(page: str, data: Optional[Dict], base_url: str) -> List[Dict]:
    """A GDACS saját térképei: az API 'images' mezője és a jelentésoldal 'arraymaps' listája.
    (A GDACS-oldal <img> elemei logók, ezért azokat nem használjuk.)"""
    out, seen = [], set()

    def add(url: str, alt: str):
        url = urllib.parse.urljoin(base_url, url or "")
        if url.startswith("http") and urllib.parse.urlparse(url).path.lower().endswith(IMG_EXT) and url not in seen:
            seen.add(url)
            out.append({"url": url, "alt": " ".join((alt or "").split())[:200]})

    p = data.get("properties", data) if isinstance(data, dict) else {}
    imgs = p.get("images") if isinstance(p, dict) else None
    if isinstance(imgs, dict):
        for k in ("thumbnailmap", "map", "overviewmap"):
            if isinstance(imgs.get(k), str):
                add(imgs[k], "")
    m = _ARRAYMAPS.search(page or "")
    if m:
        try:
            items = [(str(i.get("title", "")), str(i.get("image", ""))) for i in json.loads(m.group(1))
                     if isinstance(i, dict)]
        except ValueError:
            items = _MAP_ITEM.findall(m.group(1))
        for title, img in items:
            add(img, title)
    return out


def looks_like_html(page: str) -> bool:
    head = (page or "")[:2000].lower()
    return "<html" in head or "<body" in head or "<!doctype html" in head or "<p" in head


_GROUPED = re.compile(r"(?<=\d)[ ,.\u00a0\u202f](?=\d{3}(?!\d))")


def _num_set(text: str) -> List[float]:
    """Számok a szövegben; az ezres tagolást (12 000 / 12,000) előbb összevonjuk."""
    s = _norm_text(re.sub(r"[\u00b2\u00b3\u00b9\u2070-\u209f]", "", text or ""))  # km², CO₂: nem számok
    prev = None
    while prev != s:
        prev, s = s, _GROUPED.sub("", s)
    return [abs(x) for x in numbers_in(s)]


def unsupported_numbers(summary: str, source: str) -> List[float]:
    """Az összefoglaló olyan számai, amelyek nincsenek a forrásban (= az AI kitalálta)."""
    have = _num_set(source)
    return [n for n in _num_set(summary) if n not in have]


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
        f("Érintett országok", "Affected countries", f"{len(countries)}: " + ", ".join(_names(countries, en)))
    return facts


def _names(countries: List[str], en: bool) -> List[str]:
    if en:
        return countries
    from .geo import hu_country
    return [hu_country(c) for c in countries]


# Az ország területe (km²) az összevetéshez. Forrás: KSH, Magyarország területe 93 030 km².
HOME_AREA = {"HU": 93030}
_AREA = re.compile(r"([0-9][0-9 ,.]*[0-9])\s*km(?:2|²)", re.I)


def _area_sentence(text: str, home: str, en: bool) -> str:
    """Ha a forrás egy területet ad meg km²-ben: érthetően, és összevetve a játékos országával."""
    hit = _AREA.search(text or "")
    if not hit:
        return ""
    try:
        km2 = float(re.sub(r"[ ,]", "", hit.group(1)))
    except ValueError:
        return ""
    if km2 >= 1e6:
        size = f"{_fmt(km2 / 1e6, en, 2)} million km²" if en else f"{_fmt(km2 / 1e6, en, 2)} millió km²"
    else:
        size = f"{km2:,.0f}".replace(",", "," if en else "\u00a0") + " km²"
    s = f" The affected area is about {size}" if en else f" Az érintett terület kb. {size}"
    area = HOME_AREA.get(home.upper())
    if not area:
        return s + "."
    from .geo import country_name
    name = country_name(home, not en)
    if km2 >= 1.5 * area:
        x = round(km2 / area)
        return s + (f", roughly {x} times the size of {name}." if en else f", nagyjából {x}-szer akkora, mint {name}.")
    pct = round(100 * km2 / area)
    return s + (f", about {pct}% of the size of {name}." if en else f", ez {name} területének kb. {pct}%-a.")


def _home_sentence(countries: List[str], home: str, en: bool) -> str:
    if not home:
        return ""
    from .geo import country_name
    name_en = country_name(home)
    if name_en and name_en in countries:
        return f" {name_en} is among the affected countries." if en else f" {country_name(home, True)} is az érintettek között van."
    return ""


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


# WHO 2021 levegőminőségi irányelvek, 24 órás értékek (µg/m³)
WHO_24H = {"pm2_5": 15.0, "pm10": 45.0, "no2": 25.0}
_TITLE_NUM = {"pm2_5": re.compile(r"PM2[,.]5\s*=\s*([0-9]+(?:[,.][0-9]+)?)"),
              "uv": re.compile(r"UV[- ]?(?:index|índex)\s*=\s*([0-9]+(?:[,.][0-9]+)?)", re.I)}


def _fmt(x: float, en: bool, nd: int = 1) -> str:
    t = f"{x:.{nd}f}".rstrip("0").rstrip(".")
    return t if en else t.replace(".", ",")


def measurement_summary(event: Dict, lang: str = "hu") -> str:
    """Levegő- és UV-eseménynél: a modell értéke és a WHO-határ többszöröse, érthetően."""
    en = lang.startswith("en")
    kat = event.get("kategoria")
    if kat not in ("levego", "uv"):
        return ""
    m = dict(event.get("meres") or {})
    title = str(event.get("cim", ""))
    for k, rx in _TITLE_NUM.items():          # régebbi események: az érték a címből
        if k not in m:
            hit = rx.search(title)
            if hit:
                m[k] = float(hit.group(1).replace(",", "."))
    city = m.get("varos_en" if en else "varos") or title.split(":")[0].strip()
    src = (event.get("forras_en" if en else "forras", "") or event.get("forras", ""))
    src = src.replace(" (modellbecslés)", "").replace(" (model estimate)", "")
    if kat == "levego" and "pm2_5" in m:
        pm = float(m["pm2_5"])
        x = pm / WHO_24H["pm2_5"]
        if en:
            s = (f"In {city}, the model estimates fine particulate matter (PM2.5) at {_fmt(pm, en)} µg/m³. "
                 f"That is {_fmt(x, en)} times the WHO 24-hour guideline ({WHO_24H['pm2_5']:g} µg/m³).")
        else:
            s = (f"{city}: a modell szerint a levegő finompor-tartalma (PM2,5) {_fmt(pm, en)} µg/m³. "
                 f"Ez a WHO 24 órás irányértékének ({WHO_24H['pm2_5']:g} µg/m³) {_fmt(x, en)}-szorosa.")
        extra = []
        for k, hu_n, en_n in (("pm10", "durva por (PM10)", "coarse dust (PM10)"), ("no2", "nitrogén-dioxid", "nitrogen dioxide")):
            if m.get(k) is not None:
                v = float(m[k])
                extra.append(f"{en_n} {_fmt(v, en)} µg/m³ (WHO: {WHO_24H[k]:g})" if en
                             else f"{hu_n} {_fmt(v, en)} µg/m³ (WHO: {WHO_24H[k]:g})")
        if extra:
            s += (" Also: " if en else " Továbbá: ") + "; ".join(extra) + "."
        s += (f" This is an hourly model estimate ({src}), not a local station measurement, while the WHO value is a "
              f"24-hour average, so the comparison is indicative." if en else
              f" Ez a(z) {src} egy órára vonatkozó becslése, nem helyi mérőállomás adata, a WHO-érték pedig 24 órás "
              f"átlag, ezért az összevetés tájékoztató jellegű.")
        return s
    if kat == "uv" and "uv" in m:
        uv = float(m["uv"])
        return (f"In {city}, the model estimates a UV index of {_fmt(uv, en)}. WHO recommends sun protection from "
                f"UV index 3 upwards. Source: {src} (model estimate)." if en else
                f"{city}: a modell szerint az UV-index {_fmt(uv, en)}. A WHO szerint már 3-as indextől védekezni "
                f"kell a nap ellen. Forrás: {src} (modellbecslés).")
    return ""


def plain_summary(event: Dict, facts: List[Dict], lang: str = "hu", home: str = "") -> str:
    """AI nélküli, a forrás adataiból összerakott egyszerű összefoglaló."""
    en = lang.startswith("en")
    ms = measurement_summary(event, lang)
    if ms:
        return ms
    raw = [c.strip() for c in str(event.get("orszag", "")).split(",") if c.strip()]
    countries = _names(raw, en)
    if home:   # a játékos országa kerüljön előre
        from .geo import country_name
        mine = country_name(home)
        if mine in raw:
            i = raw.index(mine)
            countries.insert(0, countries.pop(i))
    src = event.get("forras", "")
    if en:
        if len(countries) > 3:
            s = f"{src} reports {len(countries)} affected countries, including {', '.join(countries[:3])}."
        else:
            s = f"{src} reports" + (" in " + ", ".join(countries) if countries else "") + "."
    elif len(countries) > 3:
        s = f"{src} szerint {len(countries)} ország érintett, például: {', '.join(countries[:3])}."
    elif countries:
        s = f"{src} szerint érintett: {', '.join(countries)}."
    else:
        s = f"Forrás: {src}."
    lat, lon = event.get("lat"), event.get("lon")
    if not countries and isinstance(lat, (int, float)) and isinstance(lon, (int, float)):
        ns, ew = ("N" if lat >= 0 else "S"), ("E" if lon >= 0 else "W")
        if not en:
            ns, ew = ("É" if lat >= 0 else "D"), ("K" if lon >= 0 else "Ny")
        if en:
            s = f"Location according to {src}: {abs(lat):.1f}° {ns}, {abs(lon):.1f}° {ew}."
        else:
            a, b = f"{abs(lat):.1f}".replace(".", ","), f"{abs(lon):.1f}".replace(".", ",")
            s = f"{src} szerint az esemény helye: {a}° {ns}, {b}° {ew}."
    sev = next((x["ertek"] for x in facts if x["nev"].startswith(("Súlyosság", "Severity"))), "")
    dur = next((x["ertek"] for x in facts if x["nev"] in ("Időtartam", "Duration")), "")
    if dur:
        s += f" It has lasted {dur} so far." if en else f" Már {dur} óta tart."
    if sev:
        s += (f" The source's own assessment: “{sev}”." if en else f" A forrás saját értékelése (angolul): „{sev}”.")
        s += _area_sentence(sev, home, en)
    return s + (_home_sentence(raw, home, en) if len(raw) > 3 else "")


def build(event: Dict, folder: Path, fetch: Callable[..., bytes], provider=None, lang: str = "hu",
          log=print, home: str = "") -> Dict:
    en = lang.startswith("en")
    link = str(event.get("link", ""))
    res = {"link": link, "forras": event.get("forras", ""), "cim": event.get("cim", ""), "kepek": [],
           "tenyek": [], "osszegzes": "", "miert_fontos": "", "osszegzes_tipus": "nincs", "fobb_szamok": [], "megjegyzes": ""}
    text = str(event.get("leiras", "") or "")
    page = ""
    if link.startswith("http"):
        try:
            page = fetch(link).decode("utf-8", "replace")
            if looks_like_html(page):
                text = (text + "\n" + html_text(page)).strip()
            else:
                page = ""   # pl. CSV- vagy adatfájl-link: nem összefoglalható szöveg
        except Exception as e:
            res["megjegyzes"] = (f"The source page could not be downloaded: {e}" if en
                                 else f"A forrás oldala nem tölthető le: {e}")
    is_gdacs = "gdacs" in link.lower()
    api = gdacs_api_url(link) if is_gdacs else None
    data = None
    if api:
        try:
            data = json.loads(fetch(api))
            res["tenyek"] = gdacs_facts(data, lang)
            p = data.get("properties", {}) if isinstance(data, dict) else {}
            extra = " ".join(str(p.get(k, "")) for k in ("name", "description", "htmldescription") if p.get(k))
            text = (html_text(extra) + "\n" + text).strip()
        except Exception as e:
            log(f"GDACS API: {e}")

    # képek letöltése a gép gyorsítótárába
    folder.mkdir(parents=True, exist_ok=True)
    images = gdacs_images(page, data, link) if is_gdacs else html_images(page, link)
    for im in images[: MAX_IMAGES * 3]:
        if len(res["kepek"]) >= MAX_IMAGES:
            break
        try:
            raw = fetch(im["url"])
            if len(raw) > MAX_IMAGE_BYTES or len(raw) < MIN_IMAGE_BYTES:
                continue  # túl nagy, vagy túl kicsi (ikon)
            ext = os.path.splitext(urllib.parse.urlparse(im["url"]).path)[1].lower() or ".png"
            name = hashlib.sha1(im["url"].encode()).hexdigest()[:16] + ext
            (folder / name).write_bytes(raw)
            res["kepek"].append({"fajl": str(folder / name), "url": im["url"], "alt": im["alt"]})
        except Exception as e:
            log(f"kép: {im['url']}: {e}")

    # összefoglaló
    # Kevés érdemi szövegből az AI csak kitalálna: ilyenkor a forrás saját adatai maradnak.
    if provider is not None and len(text) >= MIN_SOURCE_CHARS:
        try:
            lang_name = "English" if en else "magyar"
            known = (f"Esemény: {event.get('cim', '')}\nKategória: {event.get('kategoria', '')}\n"
                     f"Dátum: {event.get('datum', '')}\nOrszág(ok): {event.get('orszag', '') or '-'}\n"
                     f"Koordináta: {event.get('lat', '')}, {event.get('lon', '')}\nForrás: {res['forras']}")
            user = (f"Nyelv: {lang_name}\n{known}\n\n<forrasszoveg>\n{text[:MAX_TEXT]}\n</forrasszoveg>")
            raw = provider.json_call(SUMMARY_SYSTEM, user, SUMMARY_SCHEMA, 2000)
            summary = str(raw.get("osszegzes", "")).strip()
            bad = unsupported_numbers(summary, known + "\n" + text[:MAX_TEXT] + "\n" +
                                      " ".join(f["ertek"] for f in res["tenyek"]))
            if bad:   # olyan szám, ami nincs a forrásban: az összefoglalót nem mutatjuk
                log(f"AI-összefoglaló elvetve, forrásban nem szereplő számok: {bad}")
            else:
                res["osszegzes"] = summary
                res["miert_fontos"] = str(raw.get("miert_fontos", "")).strip()
                res["osszegzes_tipus"] = "ai"
            res["fobb_szamok"] = verify_numbers(raw.get("fobb_szamok", []), text[:MAX_TEXT])
        except Exception as e:
            res["megjegyzes"] = (res["megjegyzes"] + " " + (f"AI summary failed: {e}" if en
                                 else f"Az AI-összefoglaló nem sikerült: {e}")).strip()
    if not res["osszegzes"]:
        res["osszegzes"] = plain_summary(event, res["tenyek"], lang, home)
        res["osszegzes_tipus"] = "forras"
    else:
        raw = [c.strip() for c in str(event.get("orszag", "")).split(",") if c.strip()]
        if len(raw) > 3:
            res["osszegzes"] += _home_sentence(raw, home, en)
    # Az ellenőrzött, forrásolt magyarázat elsőbbséget kap az AI-szöveggel szemben.
    if event.get("kategoria") in WHY:
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
    res = build(event, Path(args.mappa), _http, provider, args.nyelv, home=args.orszag)
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
    p.add_argument("--orszag", default="", help="a játékos országa (ISO-kód), pl. HU: ezt kiemeljük")
    p.set_defaults(fn=cmd_reszlet)
