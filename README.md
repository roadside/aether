# AETHER

Klímajáték 12 éves kortól. Te vagy a világ klímatudósa: kutatsz, a bizonyítékaiddal meggyőzöd a világ hat nagy országcsoportját, és 2100-ban meglátod, milyen lett a Földed.

## Egy játék

- 2026-tól 2100-ig tizenöt kör, egy kör öt év, körönként négy lépés (könnyű fokozaton öt, nehéz fokozaton három).
- **Kutatás:** témakört választasz, három valódi kérdésből egyet kutatsz ki. Ebből bizonyíték-kártya lesz, valódi tudományos forrásokkal.
- **Tárgyalás:** minden országcsoport mástól tart. Olyan kártyával győzheted meg, amely az ő aggodalmára felel.
- **Felkészülés:** egy csoportnak segíthetsz felkészülni a hőségre, az áradásra és az aszályra. Aki felkészült, többé nem inog meg.
- **Idő:** a Föld és a görbe megmutatja, mit értél el. Minden játékban más a Föld: az érzékenysége és a billenőpontjai rejtve vannak.
- **Vége:** két Föld egymás mellett. A tiéd, és az, amelyik akkor lett volna, ha semmi sem változik.

## Mi valódi, és mi játékszabály?

Valódi adat:
- A klímamodell (`scripts/model.gd`): a kibocsátott CO2 és a melegedés közti arány (IPCC AR6), a metán rövid élettartama, kétrétegű hőmodell. A Föld érzékenysége a tudományos sávon belül játékonként más.
- Az országcsoportok CO2-kibocsátása: Global Carbon Budget 2026, 2025-ös adat (Our World in Data).
- A metán részesedése: Jones és mtsai 2025 (Our World in Data), 2024-es adat.
- A billenőpontok küszöbsávjai: Armstrong McKay és mtsai 2022, Science.
- A CO2-kivonás lehetséges mértéke: Fuss és mtsai 2018 (a sáv alsó értékével számolunk).
- A tengerszint 2100-ban: IPCC AR6 WG1 9.9 táblázat.
- A kártyák kérdései, magyarázatai és forrásai (`temak/`).
- A kártyák kulcsszámai (`adatok/kulcsszamok.json`): egy-egy mondat a megadott tanulmányból, kézzel ellenőrizve. Csak a lektorált mondat jelenik meg a játékban.

Játékszabály (nem a valóság leírása):
- A telő idő: egy kör (öt év) 90 másodpercig tart, utána a játék magától lép tovább. Amíg ablak van nyitva (olvasás, tárgyalás), az idő áll. A menüben kikapcsolható.
- A Földön felvillanó pillanatok („Most figyelnek rád!”, „Új felfedezés!”): 12 másodpercig élnek. Az első annál a csoportnál egy kártyával könnyebbé teszi a meggyőzést abban a körben, a második egy lépést ad. Kitalált játékelemek, nem valós események; a helyük is véletlen.
- Az előre látható baj: a kör elején látszik, melyik csoportot fenyegeti hőhullám, aszály, áradás vagy erdőtűz (a melegedéssel gyakrabban). Ha a kör végéig nem készíted fel őket, a mentés elvisz egy lépést a következő körből. A valóságban ilyen pontosan senki sem lát előre öt évet: ez játékszabály.
- A lendület: egy körön belül minden második megállapodás visszaad egy lépést.
- A segítő csoport: aki elérte a nulla kibocsátást, egy másik csoportot könnyebben meggyőzhetővé tesz.
- A kihívás-lépcső (0–5. szint): ha +2 °C alatt végzel a legmagasabb elért szinten, megnyílik a következő. Szintenként egy nehezítés jön hozzá: gyorsabb körök (75 másodperc), érzékenyebb Föld (a tudományos sávon belül), egy makacs csoport, gyakoribb elbizonytalanodás, eggyel kevesebb lépés.
- A terjedő tévhitek: négy gyakori tévhit egy-egy mondata (a Nap, a kozmikus sugárzás, a „túl kevés CO2”, a felhők). A cáfolat szövege a hozzá tartozó „Honnan tudjuk?” kártya lektorált „Mennyire bizonyított?” szövege. Az, hogy a tévhit melyik csoportnál terjed, és hogy amíg terjed, eggyel több kártya kell nekik, játékszabály.
- A billenőpontok veszélysávja: a sáv határai valódi adatok (Armstrong McKay és mtsai 2022); az arany gyűrű és a „Veszélysávba értünk” hír csak jelzi, hogy a melegedés belépett a sávba.
- A vezetett első kör: az első játék első körében egy sor mindig megmondja a következő mozdulatot, az idő még nem telik, és a lehetőségek körről körre nyílnak meg (küldetések a 2., metán és felkészülés a 3., CO2-kivonás a 4. körtől). Ebben a játékban a nehezítések is később jönnek: megingás a 4., előre látható baj a 3., tévhit az 5. körtől. A súgóból újra kérhető.
- A témakörök képei (`scripts/theme_art.gd`), a Földön mozgó jelek, a műhold, a pergő évszám és a szikrák saját, kódból rajzolt képek és animációk, nem valós felvételek.
- Az országcsoportok kártyáin látható kis tájképek (`scripts/landscape.gd`) saját, kódból festett hangulatképek, nem valós helyek. A szélkerekek és napelemek akkor jelennek meg rajtuk, amikor a csoport célt vállal: ez jelzés, nem adat. Ugyanígy jelzés, hogy a nulla kibocsátás elérése után madarak és több szélkerék látszik, és hogy a felkészületlenül ért baj utáni körben a kép a bajt mutatja.
- „A te történeted” képe (`scripts/story_line.gd`) a játékod saját adataiból rajzol: a két vonal a modell hőmérséklete a te utadon és változatlan kibocsátás mellett, a jelek a játék eseményei (pont: vállalás, védelem, kivonás; csillag: elért nulla; háromszög: baj, megingás, átlépett küszöb).
- Ha egy meggyőzhető csoport kártyájára mutatsz, a görbén szaggatott vonal jelenik meg a csoport színével: ez ugyanannak a klímamodellnek a középértéke arra az esetre, ha a csoport most a legjobb elérhető célt vállalná (a kártyán álló „−0,40 °C” ennek a végpontja).
- Ha még van lépésed, a „Következő 5 év” gomb első megnyomása csak szól, a második vált kört (játékszabály: véletlen kattintás ne vigyen el egy kört). Az óra lejárta ettől függetlenül továbblép.
- A tárgyalás menete, az aggodalmak és a megállapodáskor elhangzó válaszok mondatai, hogy hány kártya kell egy vállaláshoz. A kérhető célok a mostani évtől számítanak (40, 30, 20 vagy 15 év alatt nulla kibocsátás); a gyorsabb cél több kártyába kerül.
- A klímacsúcs (2041 és 2066): egy kártyát az egész világnak megmutathatsz; akinek az aggodalmára felel, és már vállalt célt, öt évvel előbbre hozza.
- A három fokozat (körönként öt, négy vagy három lépés) és „A mai Föld” (aznap mindenki ugyanazt a Földet kapja).
- A rangok (a több játékon át kikutatott kártyák száma szerint) és a záró képernyő összesítése: ki mennyi CO2-t nem bocsátott ki a „ha semmi sem változik” úthoz képest (a modell szerint).
- A felkészülés hatása (a felkészült csoport nem inog meg), a jelvények és az értékelés határai (+1,7 és +2 °C).
- A játék hangjai és alapzenéje kódból készülnek (`tools/jatek_hangok.py`), nem felvételek.
- A megingás: egy vállalást tett csoport elbizonytalanodhat; ha öt éven belül nem erősíted meg egy hozzá illő kártyával, tíz évvel későbbre tolja a célját (legfeljebb 2090-ig). A jövő hírei (hőhullám, aszály, áradás, erdőtűz) szintén a játék részei.
- A billenőpontok rejtett küszöbe: a tudományos sávból sorsoljuk, a mai melegedés fölötti részéből. A küszöb átlépése egyelőre nem hat vissza a hőmérsékletre.
- A csoportok részesedése a teljes mai kibocsátásra vonatkozik (a földhasználatét is arányosan osztjuk szét).
- A világ többi része a hat csoport átlagát követi.
- A küldetések (játékonként három, a Föld-kódból sorsolva) és a döntési helyzetek a körök elején (támogatás, meghívás): a játék kitalált helyzetei.
- A tudáspróba: a kérdés mondata a kártya lektorált kulcsszáma; a jó válasz eggyel több lépést ad.
- A „Kockázatos ötletek” témakör (a Föld mesterséges hűtése): ezek a kártyák tárgyalásra nem használhatók, mert egy csoport aggodalmára sem felelnek. A szövegük ugyanúgy a lektorált témákból jön.
- „Ha minden öt évvel később történik”: ugyanaz a klímamodell, ugyanazzal az érzékenységgel, a játékban megtörtént kibocsátási utat öt évvel eltolva.

## Futtatás

Godot 4.7-tel nyisd meg a `project.godot` fájlt. A nyitány zenéje a `sajat_zene/intro.wav`, ha ott van (nem része a tárolónak); különben a beépített handpan szól.

Ellenőrzés: `godot --path . -- --onteszt --hu` végigjátszik egy játékot, és képeket ment; `godot --path . -- --bejaras` hat teljes játékot játszik végig minden ablakot megnyitva (hibakeresés); `godot --path . -- --elojatek --hu` valós időben, kattintásokkal játszik két kört (óra, vezetés, önálló körváltás); `godot --path . -- --majom --mag=2 --mp=200` valós időben, találomra nyomkodja a gombokat (rejtett hibák keresése; a naplóban nem lehet SCRIPT ERROR); `godot --headless -s tools/egyensuly_teszt.gd -- 100 4` száz Földön méri a nehézséget; `godot --headless -s tools/jatek_teszt.gd` a szabályokat, `tools/modell_teszt.gd` a klímamodellt ellenőrzi.
