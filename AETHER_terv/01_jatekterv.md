# AETHER – Játékterv (Game Design Document), 1. változat

**AETHER** – *Artificial Intelligence for Earth's Thermal & Ecological Recovery*
Valós idejű, szüneteltethető stratégiai játék egy közös, virtuális földgömbön, ahol minden játékos saját AI-ja **valódi, publikált tudományos irodalomból** kutat, a játék pedig egy átlátható klímamodellen futtatja le az eredményt.

> Állapot: első terv. A „FELTEVÉS” jelölésű döntéseket én hoztam meg, hogy haladni tudjunk; a 20. pontban összegyűjtöttem, miről kérem a döntésedet.

---

## 0. Egy mondatban

*Te vezeted a Föld egyik kutatóállomását. Az AI-od több ezer valódi tudományos cikkben keres választ, a játék lemodellezi, mi történne, és neked kell eldöntened: megosztod-e a tudást a többi kutatóval, vagy egyedül próbálsz előbbre jutni, miközben mindenkinek ugyanaz a bolygó melegszik.*

## 1. Őszinte alapállás

Ezt a tervben végig betartom, mert a játék hitelessége ezen múlik:

1. **A játék modellezi a tudományt, nem helyettesíti.** Amit a játék kiszámol, az egy egyszerűsített modell eredménye bizonytalansági sávval, nem jóslat és nem szakpolitikai javaslat.
2. **Csak publikált forrásból dolgozunk.** Minden szám, ami a modellbe kerül, egy valódi cikk absztraktjából származó, *szó szerinti idézettel* alátámasztott érték, és a kód ellenőrzi, hogy az idézet tényleg ott van. Amit nem lehet ellenőrizni, az nem kerül be.
3. **A játék nem fogja „megmenteni a Földet”, és ezt nem is ígéri.** Amit tehet: emberek tízezreivel megérteti, *mi működik és mi nem*, valódi irodalmat olvastat, és nyilvános, ellenőrizhető összefoglalókat hoz létre. Ez valódi érték. Új tudományos felfedezést a játékos AI-ja nem tesz; legfeljebb jól összegzi és összeveti a meglévőt.
4. **A kiindulópont a valóság.** A játék a mai napon (2026) indul, a Föld valódi állapotával. Minden jelentés a jelenig (aszály, olvadás, élelmiszerhiány, szennyezés, levegő-, talaj- és vízminőség, UV-sugárzás) valódi, nyilvános forrásból jön, dátummal, hellyel és kattintható linkkel, a Föld bármely országából. Ami nem ellenőrizhető, az nem jelenik meg; ha egy forrás nem érhető el, a játék ezt megmondja, és nem pótolja kitalált adattal. A részleteket lásd a 9.1 pontban.
5. **Mindenki számára játszható.** Alacsony tanulási görbe: hétköznapi szavak szakkifejezések helyett, képernyőnként egyetlen döntés, kész kérdés-gombok üres szövegmező helyett, minden szám mellett egy egyszerű „mit jelent ez” mondat, a tudományos részletek pedig egy „Részletek” gomb mögött. Az első küldetés lépésről lépésre vezet (lásd 13. pont).
6. **Nem lehet hibázni?** A tudományban mindig lehet. Ezért nem azt tervezem, hogy a rendszer ne hibázzon, hanem hogy *a hibák kiderüljenek*: idézet-ellenőrzés, bizonytalansági sávok, független replikáció más játékosok AI-jával, visszavont cikkek kizárása.

## 2. A te kérdéseid, és amit a tudomány ma mond rájuk

A beépített modell (lásd `03_klimamodell_es_forrasok.md`) mostani eredményei, 2025-ös kiindulásból. Közép érzékenység, zárójelben az IPCC AR6 valószínű tartománya:

| Forgatókönyv | 2050 | 2100 | Mit jelent |
|---|---|---|---|
| Alapeset: a kibocsátás a mai 42 GtCO2/év szinten marad | 1,88 °C | **2,83 °C** (2,26–3,41) | 1,5 °C ~2030 körül, 2 °C ~2057 körül |
| Szárazságtűrő növények + víztakarékosság | 1,88 °C | **2,83 °C** | **Nem hűt.** A kukoricahozam-veszteség 2050-re −3,7%-ról −2,6%-ra mérséklődik (a 30%-os kompenzáció FELTEVÉS) |
| Légszennyezés csökkentése (szulfát, korom −80%) | 2,20 °C | 3,19 °C | Életeket ment (tisztább levegő), de **átmenetileg melegít**: a szulfát-aeroszol eddig elfedte a melegedés egy részét |
| Metán −45% 2030-ig | 1,69 °C | 2,57 °C | Gyorsan hat, **időt nyer** (~0,2 °C 2050-re) |
| Nettó zéró CO2 2050-re | 1,64 °C | **1,64 °C** | **Megállítja** a melegedést |
| Nettó zéró + metán −45% + CO2-eltávolítás (+ tiszta levegő) | 1,74 °C (csúcs 2045) | **1,59 °C** | Csúcs, majd lassú csökkenés |
| Csak sztratoszférikus aeroszol, 2070-ben leáll | 1,30 °C | 2,79 °C | Elfedi a gondot; leállításkor ~0,1 °C/év „visszarúgás” |

**A játék központi felismerése tehát:** a szárazságtűrő növények és a víztakarékosság *alkalmazkodás*: embereket, termést, ökoszisztémákat véd, és erre nagy szükség van, de a hőmérsékletet nem csökkenti. A melegedést csak a nettó nulla CO2-kibocsátás állítja meg (a melegedés a kumulatív CO2-vel arányos), a gyors metáncsökkentés időt nyer, a CO2-eltávolítás pedig lassan visszafelé is tud vinni. A játék úgy van megtervezve, hogy ezt a játékos *maga fedezze fel*, nem nekünk kell kimondanunk.

## 3. A játékos szerepe

- **Az állomásigazgató.** A játékos egy kutatóállomást vezet, amelyet a földgömb egy választott pontjára épít (a saját városa is lehet).
- **Az AI-mag.** Az állomás szíve a játékos *saját* AI-ja (saját előfizetés vagy helyi modell). A játékban „Számítás” erőforrásként jelenik meg, és tényleg dolgozik: keres, olvas, kivonatol.
- **A többiek.** Ugyanazon a szerveren 50–500 másik kutató játszik ugyanazon a Földön. A globális hőmérséklet **közös**: mindenki döntése mindenkire hat.

## 4. Fő játékciklus

Valós idejű, bármikor szüneteltethető. **1 negyedév ≈ 3–5 perc játékidő** (FELTEVÉS). Egy „korszak” ~20 játékév, egy teljes játék 2025-től 2100-ig ~8–12 óra, több estére bontva.

```
  ┌────────────► 1. MEGFIGYELÉS: riasztások a földgömbön (aszály, korall, olvadás)
  │                     │
  │              2. KÉRDÉS: a játékos kutatási kérdést tesz fel (szabad szöveg)
  │                     │
  │              3. KUTATÁS: az AI valódi irodalmat keres és kivonatol (perc–tíz perc)
  │                     │
  │              4. ELLENŐRZÉS: a kód ellenőrzi az idézeteket; a játékos dönt
  │                     │
  │              5. MODELLEZÉS: forgatókönyv futtatása, bizonytalansági sávval
  │                     │
  │              6. PUBLIKÁLÁS: nyílt / szövetségi / titkos  → replikáció mások AI-jával
  │                     │
  │              7. BEVEZETÉS: szakpolitika vagy terepprojekt egy régióban (bizalom + pénz kell)
  │                     │
  └────────────── 8. A VILÁG REAGÁL: hőmérséklet, termés, víz, bizalom, új riasztások
```

Közben folyik a klasszikus stratégiai réteg: építkezés, erőforrás-gazdálkodás, terepállomások, diplomácia.

### Mitől szippant be (az „első Age of Empires” érzés)

- **Látható növekedés:** az állomás modulról modulra épül, a földgömbön terjednek a terepállomásaid és a szövetségesi vonalaid.
- **Korszakváltás:** a következő korszakba lépés nagy, ünnepelt pillanat (zene, új épületek, új tudásfa-ág), de itt *ellenőrzött publikációk* kellenek hozzá, nem nyersanyag.
- **Igazi tét és igazi tartalom:** minden kutatás valódi cikkeket hoz fel; a játékos a játék végére tényleg többet tud a klímáról.
- **Mások jelenléte:** élő kutatók a földgömbön, akikkel lehet szövetkezni vagy versenyezni.
- **Rövid és hosszú ciklusok:** másodpercek (építés), percek (kutatás), órák (korszak), napok (szerver-szintű sors).

## 5. Erőforrások

| Erőforrás | Mi ez a valóságban | Hogyan szerzed | Mire költöd |
|---|---|---|---|
| **⚡ Számítás** | A játékos AI-kerete (API-tokenek vagy helyi GPU-idő) | Saját előfizetés; offline módban helyi modell | Irodalomkutatás, kivonatolás, replikáció |
| **✦ Adat** | Terepmérések, adatsorok | Terepállomások, cserék más játékosokkal | Regionális modellek pontosítása, korszakváltás |
| **♥ Bizalom** | Közbizalom, társadalmi elfogadottság | Nyílt, replikált publikációk; teljesített ígéretek | Szakpolitikák bevezetése, szövetségek |
| **⛁ Finanszírozás** | Pénz | Kormányzati és alapítványi pályázatok (játékon belül), eredmények | Építés, terepprojektek |
| **⏳ Szénkeret** | A közös, megmaradt CO2-keret | Nem szerezhető, csak fogy | Ez a szerver közös „órája” |

A **Számítás** szándékosan kötődik a valódi AI-költséghez: a játék előre megmutatja egy kutatás becsült tokenigényét és árát, és napi/havi limitet lehet beállítani.

## 6. Építkezés és egységek

**Állomásmodulok** (mind fejleszthető 3 szinten):
- **AI-mag:** párhuzamos kutatások száma, kivonatolási mélység.
- **Archívum:** offline cikk-gyorsítótár mérete (fontos offline módhoz).
- **Üvegház:** fajta- és talajkísérletek (a szimulált hozamhatás itt látszik).
- **Klímakamra:** mérőműszerek, jégmagok; regionális adatok.
- **Kommunikációs torony:** egyszerre fenntartható szövetségek és megállapodások száma.
- **Oktatási központ:** bizalom termelése, a publikációk közérthető változata.

**Terepállomások a földgömbön** (biomhoz kötve: sivatag, szavanna, trópusi erdő, tundra, óceán, mezőgazdasági terület). Adatot termelnek, és ott lehet terepprojektet indítani.

**Egységek:** terepkutató csapat, mintavevő drón, mérőhajó, szakpolitikai tanácsadó. Kicsi, szerethető pixelfigurák, amelyek a földgömb felszínén mozognak a célrégióba.

## 7. Korszakok

| Korszak | Téma | Belépés feltétele (példa) |
|---|---|---|
| I. **Felismerés** | Mérés, megértés: klímaérzékenység, szénkeret, termés és hőség | Kezdő állapot |
| II. **Mérséklés** | Metán, energiahatékonyság, alkalmazkodás (szárazságtűrő fajták, víz) | 3 ellenőrzött publikáció, ebből 1 replikált |
| III. **Átalakulás** | Nettó zéró energia, ipar, közlekedés, CO2-eltávolítás | 8 publikáció, 2 régióban bevezetett intézkedés, bizalom ≥ 50% |
| IV. **Helyreállítás** | Ökoszisztéma-helyreállítás, óceán, a csúcs utáni csökkenés | A szerver globális kibocsátása csökken, és van legalább 1 szövetséged |

A napsugár-módosítás (sztratoszférikus aeroszol) a IV. korszakban *kutatható*, de bevezetése szerver-szintű szavazást igényel, és a modell kötelezően mutatja a leállítási kockázatot. A játék **nem** ad valós telepítési útmutatót semmilyen geomérnöki beavatkozáshoz.

## 8. Tudásfa

- A csomópontok **témák** (pl. „Rizsföldek metánja”, „Kőzetmállasztás”), nem kitalált technológiák.
- Egy csomópont akkor nyílik meg, ha a játékos (vagy akitől átvette) ellenőrzött publikációt készített róla.
- **A csomópont hatásának számát nem a tervező írja be, hanem a publikációból jön**, egy engedélyezett paraméterlistán és józan tartományon belül (lásd `evidence.py` → `PARAMETERS`). Ha két játékos más forrásokból más értéket kap, mindkettő látszik, és a replikáció dönt.
- Ellentmondó irodalomnál (pl. kőzetmállasztás: egyes terepmérések korlátozott eltávolítást mutatnak) a csomópont „vitatott” jelzést kap, és emberi döntés kell.

## 9. Világszimuláció

Két szint:

1. **Globális:** az AETHER-mini klímamodell (TCRE + kétrétegű energiamérleg), évenként, három érzékenységgel. Később FaIR-adapter.
2. **Regionális (2. fázis):** ~40 régió a földgömbön. Mindegyiknek van éghajlati melegedési szorzója, főbb terményei, vízstressz-indexe, népessége és sebezhetősége. Az alkalmazkodási intézkedések itt hatnak (hozam, vízhiány, hőhullám-kitettség), a mérséklési intézkedések a globális modellen keresztül.

### 9.1 A valós kiindulópont (2026)

A játék indításakor a Python-háttér letölti a Föld mai állapotát nyílt, hivatalos forrásokból (`aether_lab vilag`), és elmenti a gépen a letöltés idejével, így offline is megmarad.

| Terület | Forrás | Kulcs kell? | Állapot |
|---|---|---|---|
| Katasztrófariasztások (aszály, árvíz, ciklon, tűz, vulkán, földrengés), országonként | GDACS (ENSZ + EU JRC) | nem | kész (1. mérföldkő) |
| Humanitárius jelentések: élelmiszerhiány, járvány, árvíz, hőség | ReliefWeb (ENSZ OCHA) | jóváhagyott alkalmazásnév | kód kész, engedélyre vár |
| Természeti események műholdas forrással (tűz, jég, por, vulkán) | NASA EONET | nem | kész |
| Légköri CO2 havi mérése | NOAA GML, Mauna Loa | nem | kész |
| Északi-sarki tengeri jég naponta | NSIDC Sea Ice Index | nem | kész |
| Levegőminőség (PM2,5, PM10, NO2, ózon) és UV-index 30 nagyvárosban, minden kontinensen | Open-Meteo (Copernicus CAMS modell) | nem | kész; modellbecslésként jelölve |
| Talajnedvesség ugyanott | Open-Meteo | nem | kész (adat), megjelenítés később |
| Ország a koordinátából (internet nélkül) | GeoNames (CC BY 4.0) + ISO 3166 | nem | kész |
| Levegőminőség mérőállomásokról | OpenAQ | ingyenes kulcs | később |
| Talaj (szén, pH, textúra) | ISRIC SoilGrids | nem | később |
| Vízminőség | UNEP GEMStat | regisztráció | következő lépés |
| Gleccserek, jégtakarók | WGMS, NASA GRACE | nem | következő lépés |

A melegedés és a maradék CO2-keret idézett érték (Forster és mtsai 2025, *Earth System Science Data*), évente frissítendő.

Minden intézkedésnek van **felfutási ideje**, **költsége**, **bizalomigénye** és **mellékhatása** (pl. BECCS: földhasználati verseny; tiszta levegő: aeroszolos „leleplezés”; SAI: leállítási sokk, csapadékváltozás).

## 10. Többjátékos mód: közös Föld, megosztás vagy elzárkózás

**Szerverek („közös Földek”)**: 50–500 kutató egy szerveren, közös globális hőmérséklettel és szénkerettel.

**Láthatóság a földgömbön:** minden állomás látszik (helyzet, nyitottsági státusz, szövetségek). Az elzárkózott állomások szürkék, lakat jellel; csak a puszta létezésük látszik.

**Kommunikáció:**
- Közvetlen és csoportos chat (moderálással, jelentés funkcióval).
- **Publikációk** (nyílt / szövetségi / titkos).
- **Megállapodások:** adat- vagy modellcsere szerződés (mit adsz, mit kapsz, időtartam, felmondhatóság, továbbadási tilalom).
- **Szövetségek:** közös kutatási sor, közös publikáció.

**A megosztás dilemmája (a játék etikai magja), mint közjószág-játék:**
- A tudás **nem fogy el**, ha megosztod: egy nyílt publikáció *minden* szerverlakó kutatási sebességét növeli.
- **Nyílt publikáció:** + bizalom, + replikáció (más AI-k ellenőrzik → magasabb bizonyosság), + korszakváltási pont. Viszont mások is profitálnak belőle.
- **Elzárkózás:** rövid távon előny (csak te használod az eredményt), de nincs replikáció (alacsonyabb bizonyosság a modellben), csökken a bizalom, és a közös Föld lassabban gyógyul, ami téged is sújt.
- A számokat úgy hangoljuk, hogy **hosszú távon az együttműködés legyen egyértelműen jobb, de rövid távon legyen csábító az elzárkózás.** Ettől lesz valódi döntés.

**Replikáció és csalás elleni védelem:** minden publikáció tartalmazza a teljes bemenetet (lekérdezések, cikkazonosítók, idézetek, paraméterek) és egy SHA-256 ujjlenyomatot. Egy másik játékos AI-ja ugyanabból újra lefuttatja, a kód újra ellenőrzi az idézeteket. A kitalált vagy hamisított eredmény így kiderül, és a hamisító bizalmat veszít.

**Szerver-szintű epilógus:** a játék végén a szerver kap egy közös „2100-as jelentést”: a csúcshőmérséklet, a védett emberek, a nyílt publikációk aránya, a legtöbbet replikált eredmények.

## 11. Offline mód

Ha nincs internet, vagy bármilyen okból nem érhető el a felhős AI vagy a szerver:
- **Helyi modell:** a játék az Ollama-n keresztül a játékos gépén futó nyílt modellt használja (a prototípusban `--ai ollama`).
- **Helyi cikktár:** az Archívum-modul offline gyorsítótárat épít a már letöltött absztraktokból (SQLite + teljes szöveges keresés). A Pro szint letölthet egy témaszűrt OpenAlex-részletet (az OpenAlex teljes adatbázisa nyílt licencű, letölthető).
- **Egyjátékos kampány** AI-vezérelt rivális állomásokkal.
- **Szinkron:** visszakapcsoláskor az offline publikációk replikációs sorba kerülnek.

Őszintén: offline a kutatás lassabb és sekélyebb (kisebb modell, kevesebb forrás). A játék ezt jelzi a publikáció bizonyossági szintjén.

## 12. Győzelem és értékelés

Nincs „megnyerted a Földet” képernyő. Pontozás 2100-ban (és korszakonként):
- csúcshőmérséklet és 2100-as hőmérséklet (szerver),
- védett emberek (regionális sebezhetőség csökkenése),
- biodiverzitás-index,
- bizalom,
- **nyílt tudományos hozzájárulás**: hány replikált publikációd van, hányan építettek rá.

Egyéni rangsor helyett „hozzájárulási” profil, hogy az együttműködés legyen a dicsőség forrása.

## 13. Kezdés: az első küldetés

**Megvalósítva az 1. mérföldkőben (Godot):** a jobb oldali „Első küldetés” panel négy lépésen vezet végig: (1) nézd meg a mai Földet a valós jelentésekkel, (2) kutass egy kész kérdés-gombbal, (3) nézd meg, mit találtál, és hagyd jóvá, (4) állítsd be a terved, és nézd meg, mi lesz 2100-ban. Mindig csak az aktuális lépés magyarázata látszik.

**„Az első kérdés”** (oktató, ~20 perc): a játékos megépíti az AI-magot, és feltesz egy kérdést, javasolt: *„Megmenti-e a Földet a szárazságtűrő növény?”* Az AI valódi cikkeket hoz, a modell megmutatja, hogy a hozam javul, a hőmérséklet nem. A narrátor nem magyaráz; a második küldetés természetes kérdése: *„Akkor mi hűti a bolygót?”*

## 14. Művészeti irány: „festett pixel”

Saját stílus, amely a kézzel festett hatású pixelgrafikák műfajába tartozik, de **semmilyen meglévő játék elemeit nem másolja**.

- **Felbontás:** 400×225 belső felbontás, 4× nagyítás (1600×900), egész számú skálázás.
- **Paletta („alkonyi parázs és tengerkék”):** éjtinta `#0b0f1a`, mélykék `#141b2d`, tengerkék `#1d4e6b`/`#3a86a8`, moha `#4f7a3a`/`#6fa04a`, homok `#c9a25a`, parázs `#d9532f` (hőstressz), jég `#e8f1f4`, arany kiemelés `#f2c14e`, AETHER-cián `#5ff2e0`.
- **Festőiség pixelben:** rendezett (Bayer) dither a színátmenetekben, puha fényudvarok lépcsőzetes gyűrűkként, peremfények, alkonyi ég. Kevés, de gazdag szín.
- **Földgömb:** forgó pixelgömb valódi kontinenshatárokkal (Natural Earth), biom-színezéssel, felhőkkel, éjszakai városfényekkel; a hőstressz parázsszínű foltként jelenik meg.
- **UI:** pixeles betűtípus (a mockupban Pixelify Sans, SIL OFL licenc), keretes panelek, nagy kontraszt.
- **Hang:** lassú, ambient szintetizátor + akusztikus elemek; a korszakváltáskor kórusszerű téma; a hőmérséklet növekedésével finoman „nyugtalanabb” hangszerelés.

Mockupok: `mockupok/aether_mockupok.html` (böngészőben, animált) és a 4 PNG.

## 15. Motorválasztás

**Javaslat: Godot 4 (kliens) + Python „AETHER Lab” háttérfolyamat (kutatási motor) + nyílt forrású játékszerver.**

| Szempont | Godot 4 | Unity | Saját webes (pl. TypeScript + Pixi) |
|---|---|---|---|
| 2D pixelgrafika | Kiváló, natív pixel-snap, könnyű | Jó, de több beállítás | Jó |
| Licenc, költség | MIT, ingyenes, nincs díj | Üzleti feltételek változhatnak | Ingyenes |
| Asztali + offline | Igen | Igen | Electron/Tauri kell |
| Python-integráció | Helyi HTTP/WebSocket a háttérfolyamattal | Ugyanígy | Ugyanígy |
| Csapat, közösség | Gyorsan növő indie közösség | A legnagyobb | Nagy |

Indoklás: a játék 2D, pixeles, és asztali offline működést kér; a Godot ehhez könnyű, ingyenes és nyílt. A tudományos rész (irodalomkeresés, AI-hívások, modell) **Pythonban** marad, mert ott vannak a tudományos eszközök (pl. FaIR), és ez a prototípus már működik. A Godot-kliens a háttérfolyamattal `localhost`-on, JSON-üzenetekkel beszél.

**Többjátékos háttér:** Nakama (nyílt forrású játékszerver: chat, csoportok, tárolás, valós idejű üzenetek) + PostgreSQL a publikációknak + objektumtár a replikációs csomagoknak. FELTEVÉS, a 2. fázisban dől el.

## 16. AI-előfizetés és költségek

- **BYOK (saját kulcs):** a játékos a saját AI-előfizetését köti be. A kulcs csak a játékos gépén, az operációs rendszer kulcstárában van, a játékszerver soha nem látja.
- **Átlátható költség:** kutatás előtt becsült tokenszám és ár; napi/havi plafon.
- **Ingyenes út:** helyi modell (Ollama), lassabban.
- **Bármelyik AI:** a prototípus Claude-ot és helyi modelleket támogat; a szolgáltató-felület bővíthető.

## 17. Etika és biztonság

- Nincs kitalált tudomány: idézet-ellenőrzés, visszavont cikkek kizárása, preprint-jelölés.
- Minden publikáción figyelmeztetés: játékon belüli összefoglaló, nem lektorált szakvélemény.
- Valós személyek (tudósok) nem jelennek meg szereplőként; a játékosok becenevet használnak.
- Chat-moderálás, jelentés, tiltás.
- Geomérnöki beavatkozásokhoz nincs valós gyakorlati útmutató.
- Az OpenAlex, Semantic Scholar, arXiv és Crossref használati feltételeinek betartása (sebességkorlát, udvarias azonosítás).

## 18. Haszon a valódi világnak

A játék nem menti meg a Földet, és új mérési adatot sem hoz létre. Három módon segíthet mégis valóban: a tudományos irodalom rendszerezésével, a közösségi tudomány eszközeivel, és azzal, hogy az emberek jobban megértik, mi hat és mi nem.

### 18.1 Bizonyított minták

- **Foldit** (Washingtoni Egyetem): a játékosok 2011-ben megfejtették egy majomvírus (Mason-Pfizer) proteáz-enzimének szerkezetét. Az eredmény a *Nature Structural & Molecular Biology* folyóiratban jelent meg (Khatib és mtsai, 2011), a játékosok társszerzőként.
- **EteRNA** (Carnegie Mellon és Stanford): a játékosok által tervezett RNS-molekulákat laborban legyártották és megmérték (Lee és mtsai, *PNAS*, 2014).
- **En-ROADS** (Climate Interactive és MIT Sloan): egyszerűsített klímaszimulátor, amelyet döntéshozók, cégek és iskolák használnak a lehetőségek megértésére.

A közös tanulság: mindhárom mögött valódi kutatócsoport áll, és a játékosok munkáját szakemberek ellenőrzik, mielőtt eredménynek számít.

### 18.2 Mit tud és mit nem tud az AETHER

| Tud | Nem tud |
|---|---|
| Ezer cikkből ellenőrzött, forrással ellátott állításokat gyűjteni | Új mérést végezni vagy új adatot előállítani |
| Megmutatni, hol mondanak ellent egymásnak a cikkek | Eldönteni, melyik cikknek van igaza |
| Kimutatni, mit nem vizsgált még senki | Lektorált tudományos eredményt adni |
| Átlátható, egyszerű modellel szemléltetni a hatásokat | Pontos regionális előrejelzést adni (ehhez teljes klímamodell kell) |

### 18.3 Nyílt bizonyíték-adatbázis

Minden ellenőrzött állítás bekerülhet egy nyílt, letölthető adatbázisba, ha a játékos ezt engedi:

- DOI és link a cikkhez, rövid szó szerinti idézet, a kinyert számok és tartományok;
- az ellenőrzés állapota: *gépileg ellenőrzött* (az idézet és a számok megtalálhatók a forrásban), *játékosok által megismételt* (több független AI ugyanazt találta), *szakértő által megerősített*;
- figyelmeztetés: preprint, visszavont cikk, kis minta.

Licenc: a saját metaadatunk CC BY 4.0. Teljes cikkszöveget és hosszú kivonatot nem terjesztünk újra, csak rövid idézetet és linket (FELTEVÉS: ezt jogász nézze át a kiadás előtt).

### 18.4 „Ezt nem tudjuk” térkép

A játék automatikusan összegyűjti:

- **Ellentmondásokat:** ugyanarra a mennyiségre egymással nem átfedő tartományok (például egy beavatkozás hűtőhatására).
- **Hiányokat:** beavatkozás × régió párok, amelyekre nincs vagy alig van cikk (például szárazságtűrő fajták Száhel-övezetben).
- **Gyenge lábakon álló állításokat:** csak preprint, csak egy forrás, vagy visszavont cikkre épül.

Ez a térkép a játékban küldetésként jelenik meg („Senki sem vizsgálta még…”), a valódi világban pedig a kutatók témaválasztását segítheti.

### 18.5 Emberi ellenőrzés

- Bármely játékos jelezhet hibát egy állításban; a jelzéseket a rendszer összesíti.
- Valódi kutatók ORCID-azonosítóval jelentkezhetnek ellenőrnek; egy állítás csak az ő jóváhagyásukkal kapja meg a *szakértő által megerősített* jelzést.
- A játék a **pontosságot** jutalmazza, nem a mennyiséget: a hibásnak bizonyult állítás hírnév-vesztéssel jár, így nem éri meg tömegesen gyenge állításokat beküldeni.
- A szakértő által megerősített hozzájárulásért a játékos „Valós hozzájárulás” jelvényt kap, játékbeli előny nélkül.

### 18.6 Oktatás

- **Osztálytermi mód:** a tanár közös Földet indít, a diákok csapatokban kutatnak, a tanár látja a forrásokat és az érveket.
- Választható (opt-in), névtelen előtte-utána kvíz méri, hogy a játék tényleg javítja-e a megértést. Ha nem javítja, azt is nyilvánosan közöljük.

### 18.7 Adatvédelem és önkéntesség

- Semmi nem kerül az adatbázisba a játékos kifejezett engedélye nélkül.
- Az elzárkózó játékos (lásd 10. pont) semmit nem oszt meg; ez a valódi adatbázisra is érvényes.
- A beküldött adat névtelen, vagy a játékos választása szerint becenévvel jelölt; személyes adat nem kerül bele.

### 18.8 Kutatói partner

Egy egyetemi vagy kutatóintézeti partner nélkül az adatbázis csak játék marad. Lehetséges magyarországi partnerek (FELTEVÉS, még senkit nem kerestünk meg): HUN-REN Ökológiai Kutatóközpont, ELTE Meteorológiai Tanszék, HungaroMet. Nemzetközileg a meglévő közösségi tudományos platformok (például Zooniverse) is szóba jöhetnek.

### 18.9 Honnan tudjuk, hogy tényleg használ?

Évente nyilvános jelentés:

- hány állítás került az adatbázisba, és ebből hányat erősített meg szakértő;
- a szakértők által talált hibaarány (a gépi ellenőrzés minőségének mérése);
- hányszor hivatkoztak az adatbázisra valódi kutatásban;
- az oktatási kvízek eredménye.

### 18.10 Amit nem ígérünk

Nem állítjuk, hogy a játék megoldja a klímaváltozást, hogy a játékbeli eredmény tudományos felfedezés, vagy hogy a modell pontos jövőt mutat. A játékbeli eredmény ötlet és szemléltetés; a valódi döntéshez lektorált tudomány kell.

## 19. Fejlesztési ütemterv (javaslat)

| Mérföldkő | Tartalom | Becslés |
|---|---|---|
| **M0 – most kész** | Terv, mockupok, működő Python kutatólabor-prototípus, klímamodell, tesztek | ✓ |
| M1 – Függőleges szelet | Godot-kliens: földgömb + 1 állomás + 1 teljes kutatási ciklus a Python-háttérrel, egyjátékos | 2–3 hónap, 1–2 fő |
| M2 – Stratégiai réteg | Építkezés, erőforrások, korszakok, tudásfa, regionális modell | +3–4 hónap |
| M3 – Közös Föld | Szerver, chat, publikációk, replikáció, szövetségek; nyílt bizonyíték-adatbázis első változata; zárt teszt 50 fővel | +4 hónap |
| M4 – Offline | Helyi modell, Archívum-cikktár, szinkron | +2 hónap |
| M5 – Korai hozzáférés | Hangolás, hang, lokalizáció (magyar + angol), tudományos tanácsadói átnézés, kutatói partner, osztálytermi mód | +3 hónap |

Erősen ajánlott egy **klímatudós tanácsadó** bevonása M2-től, aki a modell feltevéseit és a paramétertartományokat átnézi.

## 20. Feltevések és nyitott kérdések (a te döntésed)

1. **Időtempó:** valós idejű, szüneteltethető (1 negyedév ≈ 3–5 perc). Vagy inkább körökre osztott legyen?
2. **Platform:** asztali (Windows/Mac/Linux) elsőként. Kell mobil vagy böngészős változat?
3. **Nyelv:** magyar és angol felület az elejétől?
4. **Szervermodell:** saját szerver vagy közösségi (bárki indíthat „közös Földet”)?
5. **Bevétel:** egyszeri vásárlás + saját AI-előfizetés? Vagy ingyenes, adományból / támogatásból?
6. **Csapat:** egyedül fejleszted, vagy van csapatod (grafikus, programozó)? Ez dönti el az M1 terjedelmét.
7. **A szárazságtűrés kompenzációja:** a modellben most 30%-os FELTEVÉS. Lefuttassam élesben a prototípust, hogy valódi cikkekből pontosítsa az értéket?
8. **Valós haszon:** keressünk-e már most kutatói partnert (lásd 18.8)? És legyen-e a nyílt adatbázisba küldés alapból kikapcsolva (javaslatom: igen, a játékos kapcsolja be)?
