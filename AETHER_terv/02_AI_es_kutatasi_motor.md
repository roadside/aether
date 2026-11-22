# AETHER – Az AI és a kutatási motor technikai terve

Ez a dokumentum leírja, hogyan kerül **valódi AI** a játékba, és hogyan kutat **valódi, publikált tudományos irodalomban** úgy, hogy az eredmény ellenőrizhető legyen. A leírt folyamat nagy része már működik a `prototipus/` mappában (Python, külső függőség nélkül; a Claude-hoz az `anthropic` csomag kell).

## 1. Alapelv: az AI olvas, a kód számol és ellenőriz

A nyelvi modellek jól olvasnak és összegeznek, de hajlamosak magabiztosan kitalálni számokat. Ezért a szerepek szét vannak választva:

| Feladat | Ki végzi | Miért |
|---|---|---|
| Kérdés pontosítása, angol keresőkifejezések | AI | Nyelvi feladat |
| Irodalomkeresés | Kód (nyílt API-k) | Determinisztikus, naplózható |
| Számszerű állítások kinyerése absztraktokból, **szó szerinti idézettel** | AI, szigorú JSON-sémában | Nyelvi feladat |
| Az idézet tényleg szerepel-e, a szám benne van-e, a tartomány józan-e, a cikk nincs-e visszavonva | **Kód** | Nem bízhatunk az AI-ban |
| Paraméterek összesítése (súlyozott medián, tartomány) | Kód | Átlátható |
| Klímamodell futtatása | Kód | Fizika, nem nyelv |
| Közérthető összefoglaló | AI | Nyelvi feladat; a játékos látja mellette a forrásokat |
| A modellbe kerülő érték jóváhagyása | **Ember (játékos)** | Felelősség |

## 2. Architektúra

```
┌──────────────────────── Játékos gépe ─────────────────────────┐
│                                                               │
│  Godot-kliens (földgömb, labor, UI)                           │
│        │  JSON a localhost-on (WebSocket)                     │
│        ▼                                                      │
│  AETHER Lab (Python háttérfolyamat)                           │
│   ├─ research.py   kérdés → keresés → kivonatolás → ellenőrzés│
│   ├─ literature.py OpenAlex / Semantic Scholar / arXiv / Crossref
│   ├─ llm.py        Claude API  |  Ollama (helyi)  |  AI nélkül │
│   ├─ evidence.py   sémák, idézet-ellenőrzés, összesítés       │
│   ├─ climate.py    AETHER-mini modell (később FaIR-adapter)   │
│   └─ Archívum      SQLite + FTS5 offline cikktár (M4)         │
│                                                               │
│  API-kulcs: OS kulcstár (Windows Credential Manager / Keychain)│
└───────────────┬───────────────────────────────────────────────┘
                │ csak publikációk, chat, megállapodások (kulcs soha)
                ▼
┌──────────────── Játékszerver („közös Föld”) ──────────────────┐
│  Nakama: fiókok, chat, csoportok, valós idejű események       │
│  PostgreSQL: publikációk, replikációk, bizalom                │
│  Világszimuláció: a szerver összesíti a bevezetett intézkedéseket,
│  és negyedévente futtatja a közös klímamodellt                │
└───────────────────────────────────────────────────────────────┘
```

A kutatás **a játékos gépén és a játékos AI-keretéből** fut. A szerver csak a kész publikációt kapja meg, és mások gépén replikálható.

## 3. Valódi irodalomforrások

| Forrás | Mit ad | Megjegyzés |
|---|---|---|
| **OpenAlex** (`api.openalex.org`) | ~250 millió mű, absztrakt (inverted index), idézettség, `is_retracted` | Nyílt (CC0). Ingyenes API-kulcs ajánlott; `mailto` paraméterrel udvarias. Teljes adatbázis letölthető (offline mód). |
| **Semantic Scholar** (`api.semanticscholar.org`) | Absztrakt, idézettség, nyílt PDF-link | Kulcs nélkül is megy, kulccsal nagyobb keret |
| **arXiv** (`export.arxiv.org`) | Preprintek (fizika, csillagászat, matematika, klímamodellezés) | **Nem lektorált:** a súlya felére csökken, és jelölést kap. Max. 1 kérés / 3 mp. |
| **Crossref** (`api.crossref.org`) | DOI-metaadat, absztrakt (ha van), **visszavonások** | A visszavonás-ellenőrzés a `updates:` szűrővel |

Ellenőriztem: az OpenAlex ma élesben válaszol, és a mezők (`abstract_inverted_index`, `is_retracted`, `primary_location.source.display_name`) a prototípus szerint olvashatók. A 3. mockup forrásai (Zhao et al. 2017, Liu et al. 2016) valódi OpenAlex-találatok.

**Duplikátumok:** DOI alapján (ennek hiányában normalizált cím) összevonás, a leghosszabb absztrakt marad.
**Rangsor** (csak olvasási sorrend, nem „igazságmérő”): idézettség (log), lektorált > preprint, áttekintés / meta-analízis előny, frissesség; visszavont cikk kiesik.

## 4. A kutatási folyamat lépései

1. **Kérdéspontosítás** (`QUERY_PLAN_SCHEMA`): az AI 3–5 angol keresőkifejezést és a keresett paramétereket adja vissza. Számot nem adhat.
2. **Keresés** mind a négy forrásban, összevonás, rangsor, a legjobb N (alapból 12) cikk.
3. **Kivonatolás** (`EXTRACTION_SCHEMA`): az AI csak a megadott absztraktokból dolgozhat. Minden állítás: cikkazonosító, engedélyezett paraméter, érték (és alsó/felső), egység, **szó szerinti idézet**, vizsgálattípus, régió, korlátok.
4. **Determinisztikus ellenőrzés** (`evidence.verify`):
   - a cikk szerepel-e a találatok között,
   - az idézet szó szerint benne van-e az absztraktban (Unicode- és szóköznormalizálással),
   - az érték, az alsó és a felső szám benne van-e az idézetben,
   - az érték a paraméter józan tartományán belül van-e,
   - nincs-e visszavonva; preprint-e.
   Ami elbukik, „elutasítva” lesz, indoklással, és **nem kerülhet a modellbe**.
5. **Összesítés:** paraméterenként súlyozott medián (meta-analízis 3×, áttekintés 2×, terepkísérlet 2× … preprint fele súly), teljes tartomány, bizonyossági szint (alacsony / közepes / magas).
6. **Publikáció:** JSON + Markdown, minden bemenettel együtt, SHA-256 alapú azonosítóval.
7. **Játékos jóváhagyása** → a paraméter bekerül a forgatókönyvbe → modellfuttatás.

### Engedélyezett paraméterek (bővíthető)

`cdr_potencial_gtco2_ev`, `cdr_koltseg_usd_tco2`, `metan_csokkentes_pct`, `hozam_valtozas_pct_per_c`, `alkalmazkodas_hozam_elony_pct`, `viztakarekossag_pct`, `sai_kenyszer_w_m2_per_tg`, `aeroszol_erf_w_m2`, `tcre_c_per_1000gtco2`, valamint `egyeb` (csak tájékoztató). Mindegyikhez egység és józan tartomány tartozik.

## 5. AI-szolgáltatók

| Mód | Megvalósítás | Mikor |
|---|---|---|
| **Claude** (saját előfizetés) | Hivatalos `anthropic` Python SDK, `claude-opus-5-5` modell, strukturált kimenet (`output_config.format` JSON-sémával), `effort` beállítással. Bekapcsoltam a szerveroldali tartalékmodellt (`fallbacks: "default"`), hogy egy elutasított kérés esetén a hívás egy másik modellen fusson tovább. Ha nem kéred, egy sorban kikapcsolható. | Online, legjobb minőség |
| **Ollama** (helyi modell) | Az Ollama natív `/api/chat` végpontja JSON-séma szerinti `format` mezővel. Modell: `AETHER_OLLAMA_MODEL` környezeti változó (alapból `qwen3:14b`, FELTEVÉS: bármelyik letöltött modell megy) | Offline, ingyenes, lassabb |
| **AI nélkül** | Csak keresés és forráslista | Ha nincs AI-keret |

Új szolgáltató hozzáadása: egy osztály a `json_call(system, user, schema)` metódussal.

**Kulcskezelés:** a prototípus a környezetből olvas (`ANTHROPIC_API_KEY`). A kész játékban az OS kulcstárba kerül (Windows Credential Manager / macOS Keychain), a szerverre soha.

**Költségkontroll:** a kliens a kérés előtt token-számlálással megbecsüli a költséget; napi plafon; a hosszú, ismétlődő bemenetek (pl. ugyanazok az absztraktok egy replikációnál) gyorsítótárazhatók (prompt caching), ami csökkenti a költséget.

## 6. Replikáció (más játékosok AI-ja ellenőriz)

1. A publikáció tartalmazza: kérdés, terv, lekérdezések, cikkek (DOI + absztrakt), állítások, ellenőrzési eredmények, összesített paraméterek.
2. A replikátor kliense **újra lekéri** a cikkeket (DOI alapján), újrafuttatja az *ellenőrzést* (determinisztikus → azonosnak kell lennie), és a saját AI-jával **újra kivonatol**.
3. Egyezés: ugyanaz a paraméter ±10%-on belül, ugyanabból a forrásból. Eltérés esetén a publikáció „vitatott” lesz, és mindkét változat látszik.
4. Bizonyosság: 0 replikáció → legfeljebb „közepes”; 2+ független egyezés → lehet „magas”.

## 7. Offline mód részletei

- **Archívum:** minden letöltött cikk metaadata és absztraktja SQLite-ba kerül, FTS5 teljes szöveges indexszel. Offline a keresés ebből megy.
- **Témacsomagok:** az OpenAlex nyílt pillanatképéből előre szűrt csomag (pl. „klíma + mezőgazdaság + energia”, néhány GB), opcionálisan letölthető.
- **Helyi modell:** Ollama. A játék a gép erőforrásai alapján ajánl modellméretet.
- **Visszakapcsoláskor:** az offline publikációk replikációs sorba kerülnek; a DOI-k és a visszavonások újra ellenőrződnek.

## 8. A prototípus futtatása (Windows)

```powershell
cd D:\AETHER_C\AETHER_terv\prototipus
python -m unittest discover -s tests          # 12 offline teszt
python -m aether_lab demo                     # beépített forgatókönyvek, internet nélkül

# Valódi irodalomkutatás Claude-dal (saját API-kulcs):
pip install anthropic
$env:ANTHROPIC_API_KEY = "..."                # vagy: ant auth login
$env:AETHER_MAILTO = "sajat@email.hu"         # opcionális, udvarias azonosítás az OpenAlex/Crossref felé
python -m aether_lab kutat "Mennyivel növeli a szárazságtűrő kukorica a hozamot aszály alatt?" --ai claude

# Ugyanez helyi modellel (offline AI):
ollama pull qwen3:14b
python -m aether_lab kutat "biochar carbon removal potential" --ai ollama

# AI nélkül (csak forráslista):
python -m aether_lab kutat "enhanced weathering croplands" --ai none
```

Az eredmény a `publikaciok/` mappába kerül (`AETHER-xxxx.json` és `.md`).

**Mit teszteltem és mit nem:** az offline teszteket (klímamodell, OpenAlex/arXiv-feldolgozás, duplikátum-szűrés, a kitalált idézet elutasítása) lefuttattam, mind zöld. Az éles API-hívásokat a saját környezetemből nem tudtam végigfuttatni (hálózati korlát), az OpenAlex válaszformátumát külön ellenőriztem. Az első éles futás a te gépeden lesz; ha hibát ír, küldd el, és javítom.

## 9. Következő technikai lépések

1. Godot 4 kliens váz: földgömb-shader (a mockup logikája), WebSocket-kapcsolat a Python-háttérrel.
2. `aether_lab serve`: WebSocket-szerver a háttérfolyamatnak, haladásjelzéssel.
3. Archívum (SQLite FTS5) és témacsomag-letöltő.
4. FaIR-adapter a globális modellhez, és regionális modell (~40 régió).
5. Replikációs protokoll és szerveroldali publikációtár.
